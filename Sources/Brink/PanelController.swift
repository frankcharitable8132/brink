import AppKit
import SwiftUI

@MainActor
final class PanelState: ObservableObject {
    @Published var isExpanded = false
    @Published var hoveredProviderID: String?
}

/// Owns the borderless edge panel and the detail-card panel.
@MainActor
final class PanelController {
    private let store: UsageStore
    private let state = PanelState()

    private var panel: NSPanel!
    private var detailPanel: NSPanel!
    private var collapseTask: Task<Void, Never>?

    private let collapsedWidth: CGFloat = 16
    private let expandedWidth: CGFloat = 120
    private let panelHeight: CGFloat = 320
    private let detailSize = NSSize(width: 316, height: 260)

    private var panelHovered = false
    private var detailHovered = false

    init(store: UsageStore) {
        self.store = store
        makeMainPanel()
        makeDetailPanel()
        positionPanel(expanded: false)
        panel.orderFrontRegardless()
    }

    // MARK: Panels

    private func makeMainPanel() {
        panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        configure(panel)
        let root = PanelRootView(
            store: store, state: state,
            onHoverChanged: { [weak self] inside in
                self?.panelHovered = inside
                self?.hoverChanged()
            },
            onRingHover: { [weak self] id in
                self?.ringHover(id)
            }
        )
        panel.contentView = NSHostingView(rootView: root)
    }

    private func makeDetailPanel() {
        detailPanel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        configure(detailPanel)
    }

    private func configure(_ p: NSPanel) {
        p.level = .statusBar
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false // SwiftUI draws its own shadow
        p.hidesOnDeactivate = false
        p.isMovableByWindowBackground = false
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        p.isFloatingPanel = true
        p.becomesKeyOnlyIfNeeded = true
    }

    // MARK: Geometry

    private var screen: NSScreen? { NSScreen.main ?? NSScreen.screens.first }

    private func positionPanel(expanded: Bool) {
        guard let screen else { return }
        let width = expanded ? expandedWidth : collapsedWidth
        let visible = screen.visibleFrame
        let y = visible.midY - panelHeight / 2
        let frame = NSRect(x: screen.frame.maxX - width, y: y,
                           width: width, height: panelHeight)
        panel.setFrame(frame, display: true, animate: false)
    }

    // MARK: Hover logic

    private func hoverChanged() {
        if panelHovered || detailHovered {
            collapseTask?.cancel()
            collapseTask = nil
            if !state.isExpanded { expand() }
        } else {
            scheduleCollapse()
        }
    }

    private func expand() {
        positionPanel(expanded: true)
        state.isExpanded = true
    }

    private func scheduleCollapse() {
        collapseTask?.cancel()
        collapseTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled, let self else { return }
            guard !self.panelHovered, !self.detailHovered else { return }
            self.state.isExpanded = false
            self.state.hoveredProviderID = nil
            self.hideDetail()
            // Shrink the window after the SwiftUI transition finishes.
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled, !self.state.isExpanded else { return }
            self.positionPanel(expanded: false)
        }
    }

    private func ringHover(_ id: String?) {
        if let id {
            state.hoveredProviderID = id
            showDetail(for: id)
        }
        // Deliberately keep the card up when the ring is un-hovered;
        // it hides when the whole panel collapses.
    }

    // MARK: Detail card

    private func showDetail(for id: String) {
        guard let snap = store.snapshots.first(where: { $0.id == id }) else { return }
        let view = DetailCardView(snapshot: snap)
            .onHover { [weak self] inside in
                self?.detailHovered = inside
                self?.hoverChanged()
            }
        detailPanel.contentView = NSHostingView(rootView: AnyView(view))

        let panelFrame = panel.frame
        let fitting = detailPanel.contentView?.fittingSize ?? detailSize
        let size = NSSize(width: max(fitting.width, 200), height: max(fitting.height, 120))
        var origin = NSPoint(
            x: panelFrame.minX - size.width + 4,
            y: panelFrame.midY - size.height / 2
        )
        if let screen {
            origin.y = max(screen.visibleFrame.minY + 8,
                           min(origin.y, screen.visibleFrame.maxY - size.height - 8))
        }
        detailPanel.setFrame(NSRect(origin: origin, size: size), display: true)
        detailPanel.orderFrontRegardless()
    }

    private func hideDetail() {
        detailPanel.orderOut(nil)
    }
}
