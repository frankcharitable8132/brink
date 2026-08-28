import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: UsageStore!
    private var controller: PanelController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        store = UsageStore(providers: [ClaudeProvider(), CodexProvider()])
        controller = PanelController(store: store)
        store.startAutoRefresh(interval: 120)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory) // no Dock icon, no menu bar
let delegate = AppDelegate()
app.delegate = delegate
app.run()
