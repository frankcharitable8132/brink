import Foundation
import Security

/// Reads Claude Code's OAuth access token (macOS Keychain or
/// ~/.claude/.credentials.json) and queries Anthropic's usage endpoint —
/// the same request Claude Code itself makes for `/usage`.
///
/// Design notes:
/// - Brink never refreshes tokens itself. Doing so with Claude Code's
///   refresh token could rotate it and log the user out of Claude Code.
///   When the access token expires, we simply re-read Claude Code's store
///   (Claude Code keeps it fresh whenever it runs).
/// - Only the short-lived access token (+ expiry) is cached locally, so the
///   Keychain prompt appears once, not on every refresh cycle.
struct ClaudeProvider: UsageProvider {
    let id = "claude"

    private static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    struct Credentials {
        var accessToken: String
        var expiresAt: Date?

        var isExpired: Bool {
            guard let expiresAt else { return false }
            return expiresAt.timeIntervalSinceNow < 30
        }
    }

    func fetch() async -> ProviderSnapshot {
        var snap = ProviderSnapshot(id: id, name: "Claude",
                                    systemImage: "asterisk",
                                    windows: [], error: nil,
                                    accent: UsageColor.claudeOrange)
        guard let creds = Self.loadCredentials() else {
            var demo = Self.demoSnapshot(name: "Claude", systemImage: "asterisk",
                                         note: L("Claude Code credentials not found"))
            demo.accent = UsageColor.claudeOrange
            return demo
        }

        do {
            var (data, status) = try await Self.requestUsage(token: creds.accessToken)
            if status == 401 {
                // Claude Code rotated its token: drop our cache, re-read its store
                // (Keychain / file) and retry once right away.
                Self.clearOwnCopy()
                if let fresh = Self.loadCredentials(), fresh.accessToken != creds.accessToken {
                    (data, status) = try await Self.requestUsage(token: fresh.accessToken)
                }
            }
            if status == 401 {
                snap.error = L("Unauthorized — open Claude Code once to refresh login")
                return snap
            }
            guard status == 200 else {
                snap.error = L("HTTP %d", status)
                return snap
            }
            snap.windows = Self.parseUsage(data)
            snap.updatedAt = Date()
            if snap.windows.isEmpty { snap.error = L("No usage data in response") }
            return snap
        } catch {
            snap.error = error.localizedDescription
            return snap
        }
    }

    private static func requestUsage(token: String) async throws -> (Data, Int) {
        var request = URLRequest(url: usageURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("Brink/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    // MARK: Parsing

    /// Newer responses carry a structured `limits` array:
    /// `{kind: session|weekly_all|weekly_scoped, percent, resets_at, scope:{model:{display_name}}}`.
    /// Older responses only have `five_hour`, `seven_day`, `seven_day_sonnet`,
    /// `seven_day_opus` dicts with `utilization` (0-100) and `resets_at`.
    static func parseUsage(_ data: Data) -> [UsageWindow] {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return []
        }
        let fromLimits = parseLimitsArray(root["limits"])
        if !fromLimits.isEmpty { return fromLimits }
        return parseLegacyWindows(root)
    }

    static func parseLimitsArray(_ any: Any?) -> [UsageWindow] {
        guard let limits = any as? [[String: Any]] else { return [] }
        var windows: [UsageWindow] = []
        for item in limits {
            guard let kind = item["kind"] as? String,
                  let pct = Self.number(item["percent"]) else { continue }
            let resets = Self.isoDate(item["resets_at"])
            let label: String
            switch kind {
            case "session":
                label = "Current session"
            case "weekly_all":
                label = "All models"
            case "weekly_scoped":
                let scope = item["scope"] as? [String: Any]
                let model = scope?["model"] as? [String: Any]
                let surface = scope?["surface"] as? [String: Any]
                let name = (model?["display_name"] as? String)
                    ?? (surface?["display_name"] as? String)
                    ?? "Scoped"
                label = name
            default:
                // Unknown kind — still surface it rather than silently drop.
                label = kind.replacingOccurrences(of: "_", with: " ").capitalized
            }
            // Avoid duplicate ids (UsageWindow.id == label).
            if windows.contains(where: { $0.label == label }) { continue }
            windows.append(UsageWindow(label: label, usedPercent: pct, resetsAt: resets))
        }
        return windows
    }

    static func parseLegacyWindows(_ root: [String: Any]) -> [UsageWindow] {
        var windows: [UsageWindow] = []
        let ordered: [(String, String)] = [
            ("five_hour", "Current session"),
            ("seven_day", "All models"),
            ("seven_day_sonnet", "Sonnet"),
            ("seven_day_opus", "Opus"),
        ]
        for (key, label) in ordered {
            guard let dict = root[key] as? [String: Any] else { continue }
            guard let pct = Self.number(dict["utilization"]) else { continue }
            let resets = Self.isoDate(dict["resets_at"])
            windows.append(UsageWindow(label: label, usedPercent: pct, resetsAt: resets))
        }
        return windows
    }

    static func number(_ any: Any?) -> Double? {
        if let d = any as? Double { return d }
        if let i = any as? Int { return Double(i) }
        if let s = any as? String { return Double(s) }
        return nil
    }

    static func isoDate(_ any: Any?) -> Date? {
        guard let s = any as? String else { return nil }
        let f1 = ISO8601DateFormatter()
        f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f1.date(from: s) { return d }
        let f2 = ISO8601DateFormatter()
        return f2.date(from: s)
    }

    // MARK: Credentials

    /// Lookup order is chosen to keep the macOS Keychain prompt to a minimum:
    ///  1) In-memory cache (no I/O while the app is running)
    ///  2) Brink's own cache of the access token (written after a successful read)
    ///  3) ~/.claude/.credentials.json (file store used by Claude Code on some setups)
    ///  4) Keychain item "Claude Code-credentials" — this is what triggers the
    ///     macOS prompt. Clicking "Always Allow" makes it silent afterwards.
    /// Expired tokens are discarded so Claude Code's fresher copy is picked up.
    static func loadCredentials() -> Credentials? {
        if let cached = memoryCache, !cached.isExpired { return cached }

        if let data = try? Data(contentsOf: ownStoreURL),
           let creds = parseCredentialsJSON(data), !creds.isExpired {
            memoryCache = creds
            return creds
        }

        let claudeFile = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/.credentials.json")
        if let data = try? Data(contentsOf: claudeFile),
           let creds = parseCredentialsJSON(data), !creds.isExpired {
            saveOwnCopy(creds)
            return creds
        }

        // Don't hammer the Keychain (and the user with prompts) if it keeps failing.
        if let last = lastKeychainAttempt, Date().timeIntervalSince(last) < keychainRetryInterval {
            return nil
        }
        lastKeychainAttempt = Date()
        if let data = keychainData(service: "Claude Code-credentials"),
           let creds = parseCredentialsJSON(data), !creds.isExpired {
            saveOwnCopy(creds)
            return creds
        }
        return nil
    }

    // MARK: Own credential cache (~/Library/Application Support/Brink/credentials.json)
    // Holds ONLY the short-lived access token and its expiry — never the refresh token.

    private static var memoryCache: Credentials?
    private static var lastKeychainAttempt: Date?
    private static let keychainRetryInterval: TimeInterval = 10 * 60

    static var ownStoreURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Brink", isDirectory: true)
            .appendingPathComponent("credentials.json")
    }

    static func saveOwnCopy(_ creds: Credentials) {
        memoryCache = creds
        var oauth: [String: Any] = ["accessToken": creds.accessToken]
        if let e = creds.expiresAt { oauth["expiresAt"] = Int(e.timeIntervalSince1970 * 1000) }
        guard let data = try? JSONSerialization.data(withJSONObject: ["claudeAiOauth": oauth]) else { return }
        let dir = ownStoreURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        try? data.write(to: ownStoreURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: ownStoreURL.path)
    }

    static func clearOwnCopy() {
        memoryCache = nil
        lastKeychainAttempt = nil
        try? FileManager.default.removeItem(at: ownStoreURL)
    }

    static func parseCredentialsJSON(_ data: Data) -> Credentials? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String else {
            return nil
        }
        var expires: Date?
        if let ms = number(oauth["expiresAt"]) {
            expires = Date(timeIntervalSince1970: ms / 1000.0)
        }
        return Credentials(accessToken: token, expiresAt: expires)
    }

    static func keychainData(service: String, account: String? = nil) -> Data? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        if let account { query[kSecAttrAccount as String] = account }
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else { return nil }
        return item as? Data
    }

    // MARK: Demo fallback

    static func demoSnapshot(name: String, systemImage: String, note: String) -> ProviderSnapshot {
        ProviderSnapshot(
            id: name.lowercased(), name: name, systemImage: systemImage,
            windows: [
                UsageWindow(label: "Current session", usedPercent: 73,
                            resetsAt: Date().addingTimeInterval(51 * 60)),
                UsageWindow(label: "All models", usedPercent: 7,
                            resetsAt: Date().addingTimeInterval(36 * 3600)),
                UsageWindow(label: "Fable", usedPercent: 4,
                            resetsAt: Date().addingTimeInterval(36 * 3600)),
            ],
            error: note, isDemo: true, updatedAt: Date()
        )
    }
}
