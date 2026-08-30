import Foundation
import SwiftUI

/// Drives the "what used it" section of the Claude card.
///
/// The limit itself only tells you how much is gone. This pairs each observed
/// increase with the local turns that happened in the same interval, so the card
/// can say *which project* spent it. Everything is computed locally from files
/// Claude Code already wrote; no extra requests, no accounts.
@MainActor
final class CostModel: ObservableObject {
    static let shared = CostModel()

    enum State {
        case unavailable      // no transcripts on this machine — hide the section
        case waiting          // indexed, but no measurable consumption yet
        case ready
    }

    @Published private(set) var rows: [ProjectCost] = []
    @Published private(set) var state: State = .unavailable

    @Published var isExpanded: Bool {
        didSet { UserDefaults.standard.set(isExpanded, forKey: Self.expandedKey) }
    }

    private static let expandedKey = "costExpanded"
    private let store: CostStore?
    private let indexer: CostIndexer?

    private init() {
        isExpanded = UserDefaults.standard.bool(forKey: Self.expandedKey)

        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Brink", isDirectory: true)
        store = CostStore(url: dir.appendingPathComponent("agentcost.sqlite"))
        indexer = store.flatMap { CostIndexer(store: $0) }

        guard let indexer else { return }
        state = .waiting
        indexer.onChange = { [weak self] in
            Task { @MainActor in self?.reload() }
        }
        indexer.start()
        reload()
    }

    /// Called after every usage poll. Samples the limit and attributes any increase.
    func observe(_ snapshots: [ProviderSnapshot]) {
        guard let store,
              let claude = snapshots.first(where: { $0.id == "claude" && !$0.isDemo })
        else { return }

        let samples: [(CostWindow, Double)] = claude.windows.compactMap {
            guard let window = CostWindow.from(label: $0.label) else { return nil }
            return (window, $0.usedPercent)
        }
        guard !samples.isEmpty else { return }

        Task.detached(priority: .utility) {
            for (window, pct) in samples { store.recordSample(window: window, pct: pct) }
            await MainActor.run { self.reload() }
        }
    }

    func reload() {
        guard let store else { return }
        Task.detached(priority: .utility) {
            let fresh = store.currentPeriod(window: .session).presentable()
            await MainActor.run {
                self.rows = fresh
                self.state = fresh.isEmpty ? .waiting : .ready
            }
        }
    }

    /// Diagnostics line for the settings menu.
    func statsLine() -> String? {
        guard let store else { return nil }
        let s = store.stats()
        guard s.events > 0 || s.files > 0 else { return nil }
        if s.errors > 0 {
            return L("%d turns · %d files · %d skipped", s.events, s.files, s.errors)
        }
        return L("%d turns · %d files", s.events, s.files)
    }
}
