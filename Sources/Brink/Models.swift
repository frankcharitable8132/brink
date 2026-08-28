import Foundation
import SwiftUI

// MARK: - Data model

struct UsageWindow: Identifiable {
    var id: String { label }
    var label: String            // "Current session", "All models (weekly)"...
    var usedPercent: Double      // 0...100
    var resetsAt: Date?

    var fraction: Double { min(max(usedPercent / 100.0, 0), 1) }

    var resetText: String? {
        guard let resetsAt else { return nil }
        let seconds = resetsAt.timeIntervalSinceNow
        if seconds <= 0 { return "Resets soon" }
        if seconds < 3600 {
            return "Resets in \(Int(seconds / 60)) min"
        }
        if seconds < 86400 {
            let h = Int(seconds / 3600)
            let m = Int(seconds.truncatingRemainder(dividingBy: 3600) / 60)
            return m > 0 ? "Resets in \(h) h \(m) min" : "Resets in \(h) h"
        }
        let fmt = DateFormatter()
        fmt.dateFormat = "EEE HH:mm"
        return "Resets \(fmt.string(from: resetsAt))"
    }
}

struct ProviderSnapshot: Identifiable {
    let id: String               // "claude", "codex"
    var name: String
    var systemImage: String
    var windows: [UsageWindow]
    var error: String?
    var isDemo: Bool = false
    var accent: Color? = nil     // fixed brand color; nil = percent-based scale
    var updatedAt: Date?

    var primary: UsageWindow? { windows.first }
}

// MARK: - Ring color scale

enum UsageColor {
    static let claudeOrange = Color(red: 0.85, green: 0.47, blue: 0.34) // #D97757

    static func color(for snapshot: ProviderSnapshot, percent: Double) -> Color {
        snapshot.accent ?? color(for: percent)
    }

    static func color(for percent: Double) -> Color {
        if percent < 50.0 { return Color(red: 0.13, green: 0.90, blue: 0.47) } // green  #21E678
        if percent < 80.0 { return Color(red: 0.96, green: 0.89, blue: 0.00) } // yellow #F5E300
        return Color(red: 1.00, green: 0.23, blue: 0.00)                       // red-orange #FF3B00
    }
}

// MARK: - Provider protocol

protocol UsageProvider {
    var id: String { get }
    func fetch() async -> ProviderSnapshot
}

// MARK: - Store

@MainActor
final class UsageStore: ObservableObject {
    @Published var snapshots: [ProviderSnapshot] = []
    @Published var lastRefresh: Date?

    private let providers: [UsageProvider]
    private var timer: Timer?

    init(providers: [UsageProvider]) {
        self.providers = providers
        self.snapshots = providers.map {
            ProviderSnapshot(id: $0.id, name: $0.id.capitalized,
                             systemImage: "hourglass", windows: [], error: nil)
        }
    }

    func startAutoRefresh(interval: TimeInterval = 120) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshAll() }
        }
        refreshAll()
    }

    func refreshAll() {
        Task {
            var results: [ProviderSnapshot] = []
            for provider in providers {
                let snap = await provider.fetch()
                results.append(snap)
            }
            let final = results
            await MainActor.run {
                self.snapshots = final
                self.lastRefresh = Date()
            }
        }
    }
}
