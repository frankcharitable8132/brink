import Foundation
import CoreServices

/// Reads Claude Code's session transcripts and extracts *only* token counts.
///
/// What it reads, per record, and nothing else:
///   timestamp, cwd, gitBranch, sessionId, requestId, version,
///   message.model, message.usage.{input,output,cache_read,cache_creation}_tokens
///
/// It never touches `message.content`, `toolUseResult`, `attachment` records, or
/// the `tool-results/` and `subagents/` sibling directories. Transcripts can hold
/// secrets an agent read from a project; this feature must never be a way for them
/// to leave the machine — and nothing here is ever sent anywhere.
///
/// Reading is incremental: each file's byte offset is stored, so later passes only
/// parse what was appended. A trailing partial line (Claude Code mid-write) is left
/// unconsumed until its newline arrives.
final class CostIndexer {
    private let store: CostStore
    private let root: URL
    private let queue = DispatchQueue(label: "com.semihtali.brink.indexer", qos: .utility)
    private var stream: FSEventStreamRef?
    private var gitRootCache: [String: String] = [:]
    private var scanScheduled = false

    /// Called on the indexer queue after a pass that changed something.
    var onChange: (() -> Void)?

    init?(store: CostStore) {
        self.store = store
        let home = FileManager.default.homeDirectoryForCurrentUser
        let base = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"].map {
            URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath)
        } ?? home.appendingPathComponent(".claude")
        root = base.appendingPathComponent("projects")
        guard FileManager.default.fileExists(atPath: root.path) else { return nil }
    }

    deinit { stopWatching() }

    // MARK: Scanning

    func start() {
        scan()
        startWatching()
    }

    func scan() {
        queue.async { [weak self] in self?.performScan() }
    }

    private func performScan() {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
        guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys,
                                                     options: [.skipsHiddenFiles]) else { return }
        var files: [(url: URL, mtime: Date)] = []
        for case let url as URL in e where url.pathExtension == "jsonl" {
            let m = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            files.append((url, m ?? .distantPast))
        }
        // Newest first: the current period becomes correct before the backfill finishes.
        files.sort { $0.mtime > $1.mtime }

        var changed = false
        for f in files where indexFile(f.url) { changed = true }
        if changed { onChange?() }
    }

    /// Returns true when new rows were written.
    @discardableResult
    private func indexFile(_ url: URL) -> Bool {
        let path = url.path
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path) else { return false }
        let size = (attrs[.size] as? Int) ?? 0
        let inode = (attrs[.systemFileNumber] as? Int) ?? 0
        let mtime = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0

        var offset = 0
        if let cursor = store.fileCursor(path) {
            if cursor.inode != inode || size < cursor.offset {
                offset = 0                          // rotated or truncated: re-read
            } else if size == cursor.offset {
                return false                        // nothing appended
            } else {
                offset = cursor.offset
            }
        }
        guard size > offset else { return false }

        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        do { try handle.seek(toOffset: UInt64(offset)) } catch { return false }
        guard let data = try? handle.readToEnd(), !data.isEmpty else { return false }

        var events: [UsageEvent] = []
        var malformed = 0
        var consumed = 0

        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return }
            let buf = UnsafeBufferPointer(start: base, count: raw.count)
            var start = 0
            for i in 0..<buf.count {
                guard buf[i] == 0x0A else { continue }
                if i > start {
                    let slice = UnsafeBufferPointer(rebasing: buf[start..<i])
                    switch parse(slice) {
                    case .event(let e): events.append(e)
                    case .malformed:    malformed += 1
                    case .skip:         break
                    }
                }
                start = i + 1
                consumed = start          // only advance past complete lines
            }
        }

        guard consumed > 0 else { return false }   // no complete line yet
        store.commit(events: events, path: path, inode: inode, size: size,
                     offset: offset + consumed, mtime: mtime)
        store.recordParseErrors(path: path, count: malformed, reason: "malformed line")
        return !events.isEmpty
    }

    // MARK: Parsing

    private enum ParseResult {
        case event(UsageEvent)
        case skip          // not an assistant turn, or synthetic — expected, not an error
        case malformed     // broken JSON or a missing field we require
    }

    private static let marker = Array("\"assistant\"".utf8)

    private lazy var isoWithMillis: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private lazy var isoPlain = ISO8601DateFormatter()

    private func parse(_ line: UnsafeBufferPointer<UInt8>) -> ParseResult {
        // Cheap pre-filter: most lines are user turns or attachments and never
        // reach the JSON parser.
        guard Self.contains(line, Self.marker) else { return .skip }
        guard let obj = (try? JSONSerialization.jsonObject(with: Data(line))) as? [String: Any] else {
            return .malformed
        }
        guard obj["type"] as? String == "assistant" else { return .skip }

        guard let message = obj["message"] as? [String: Any],
              let usage = message["usage"] as? [String: Any],
              let model = message["model"] as? String else { return .malformed }
        // Synthetic turns are local error placeholders, not billed requests.
        guard model != "<synthetic>" else { return .skip }

        guard let cwd = obj["cwd"] as? String,
              let sessionId = obj["sessionId"] as? String ?? obj["session_id"] as? String,
              let stamp = obj["timestamp"] as? String,
              let date = isoWithMillis.date(from: stamp) ?? isoPlain.date(from: stamp),
              let input = int(usage["input_tokens"]),
              let output = int(usage["output_tokens"]) else { return .malformed }

        let cacheRead = int(usage["cache_read_input_tokens"]) ?? 0
        let cacheWrite = int(usage["cache_creation_input_tokens"]) ?? 0
        let ts = Int(date.timeIntervalSince1970)

        // Claude Code appends the same turn several times while streaming, each
        // write carrying a larger output count. Collapse them by request id and
        // keep the maximum (see CostStore.commit).
        let key: String
        if let requestId = obj["requestId"] as? String, !requestId.isEmpty {
            key = "r:\(requestId)"
        } else {
            key = "s:\(sessionId):\(ts):\(input):\(output):\(cacheRead):\(cacheWrite)"
        }

        var branch = obj["gitBranch"] as? String
        if branch?.isEmpty ?? false { branch = nil }

        return .event(UsageEvent(
            ts: ts,
            sessionId: sessionId,
            dedupeKey: key,
            project: projectRoot(for: cwd),
            cwd: cwd,
            branch: branch,
            model: model,
            input: input,
            output: output,
            cacheRead: cacheRead,
            cacheWrite: cacheWrite,
            ccVersion: obj["version"] as? String
        ))
    }

    private func int(_ any: Any?) -> Int? {
        if let i = any as? Int { return i }
        if let d = any as? Double { return Int(d) }
        return nil
    }

    private static func contains(_ haystack: UnsafeBufferPointer<UInt8>, _ needle: [UInt8]) -> Bool {
        guard haystack.count >= needle.count else { return false }
        let last = haystack.count - needle.count
        for i in 0...last where haystack[i] == needle[0] {
            var match = true
            for j in 1..<needle.count where haystack[i + j] != needle[j] { match = false; break }
            if match { return true }
        }
        return false
    }

    // MARK: Project grouping

    /// Sessions started from subfolders of one repo should read as one project, so
    /// the cwd is walked up to its git root. A folder in one project directory can
    /// hold dozens of distinct cwds, which would otherwise fill the list with
    /// `Sources`, `windows`, `docs` rows. Falls back to the cwd itself.
    private func projectRoot(for cwd: String) -> String {
        if let cached = gitRootCache[cwd] { return cached }
        var dir = URL(fileURLWithPath: cwd)
        var result = cwd
        for _ in 0..<12 {
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent(".git").path) {
                result = dir.path
                break
            }
            let parent = dir.deletingLastPathComponent()
            if parent.path == dir.path || parent.path == "/" { break }
            dir = parent
        }
        gitRootCache[cwd] = result
        return result
    }

    // MARK: Watching

    private func startWatching() {
        var context = FSEventStreamContext(version: 0,
                                           info: Unmanaged.passUnretained(self).toOpaque(),
                                           retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<CostIndexer>.fromOpaque(info).takeUnretainedValue().coalescedScan()
        }
        guard let s = FSEventStreamCreate(nil, callback, &context,
                                          [root.path] as CFArray,
                                          FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                                          2.0,   // latency doubles as debounce
                                          FSEventStreamCreateFlags(kFSEventStreamCreateFlagNoDefer)) else { return }
        FSEventStreamSetDispatchQueue(s, queue)
        FSEventStreamStart(s)
        stream = s
    }

    private func stopWatching() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    /// FSEvents can fire repeatedly while a session is being written; collapse
    /// bursts into one pass.
    private func coalescedScan() {
        queue.async { [weak self] in
            guard let self, !self.scanScheduled else { return }
            self.scanScheduled = true
            self.queue.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                guard let self else { return }
                self.scanScheduled = false
                self.performScan()
            }
        }
    }
}
