import SwiftUI
import AppKit

// MARK: - Left-rounded rectangle (macOS 13 compatible)

struct LeftRoundedRect: Shape {
    var radius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let r = min(radius, rect.height / 2, rect.width)
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + r, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.minY + r),
                          control: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - r))
        path.addQuadCurve(to: CGPoint(x: rect.minX + r, y: rect.maxY),
                          control: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Usage ring

struct UsageRing: View {
    let snapshot: ProviderSnapshot
    var size: CGFloat = 52

    private var percent: Double { snapshot.primary?.usedPercent ?? 0 }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.22), lineWidth: 4.5)
                Circle()
                    .trim(from: 0, to: snapshot.primary?.fraction ?? 0)
                    .stroke(UsageColor.color(for: snapshot, percent: percent),
                            style: StrokeStyle(lineWidth: 4.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: snapshot.systemImage)
                    .font(.system(size: size * 0.32, weight: .semibold))
                    .foregroundColor(.white)
            }
            .frame(width: size, height: size)
            .opacity(snapshot.windows.isEmpty ? 0.35 : 1)

            Text(snapshot.windows.isEmpty ? "--" : "\(Int(percent.rounded()))%")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
        }
    }
}

// MARK: - Expanded column of rings

struct RingColumnView: View {
    @ObservedObject var store: UsageStore
    var onRingHover: (String?) -> Void

    var body: some View {
        VStack(spacing: 22) {
            ForEach(store.snapshots) { snap in
                UsageRing(snapshot: snap)
                    .onHover { inside in
                        onRingHover(inside ? snap.id : nil)
                    }
            }
        }
        .padding(.vertical, 26)
        .padding(.horizontal, 18)
        .background(
            LeftRoundedRect(radius: 26)
                .fill(Color.black)
        )
    }
}

// MARK: - Collapsed strip

struct CollapsedStripView: View {
    var body: some View {
        LeftRoundedRect(radius: 5)
            .fill(Color.black)
            .frame(width: 7)
            .padding(.vertical, 40)
    }
}

// MARK: - Panel root

struct PanelRootView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var state: PanelState
    var onHoverChanged: (Bool) -> Void
    var onRingHover: (String?) -> Void

    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            if state.isExpanded {
                RingColumnView(store: store, onRingHover: onRingHover)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                CollapsedStripView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        .contentShape(Rectangle())
        .onHover(perform: onHoverChanged)
        .contextMenu {
            Button("Refresh now") { store.refreshAll() }
            Divider()
            Toggle("Launch at login", isOn: Binding(
                get: { LaunchAtLogin.isEnabled },
                set: { LaunchAtLogin.set($0) }
            ))
            Divider()
            Button("Quit Brink") { NSApp.terminate(nil) }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: state.isExpanded)
    }
}

// MARK: - Detail card (the speech-bubble in the mockup)

struct DetailCardView: View {
    let snapshot: ProviderSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: snapshot.systemImage)
                    .font(.system(size: 15, weight: .bold))
                Text("\(snapshot.name) Usage")
                    .font(.system(size: 16, weight: .semibold))
                if snapshot.isDemo {
                    Text("DEMO")
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Capsule().fill(Color.white.opacity(0.18)))
                }
            }
            .foregroundColor(.white)

            if snapshot.windows.isEmpty {
                Text(snapshot.error ?? "No data")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.6))
            } else {
                ForEach(snapshot.windows) { window in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(window.label)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white)
                            Spacer()
                            if let reset = window.resetText {
                                Text(reset)
                                    .font(.system(size: 11))
                                    .foregroundColor(.white.opacity(0.5))
                            }
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.white.opacity(0.22))
                                Capsule()
                                    .fill(UsageColor.color(for: snapshot, percent: window.usedPercent))
                                    .frame(width: max(6, geo.size.width * window.fraction))
                            }
                        }
                        .frame(height: 6)
                        Text("\(Int(window.usedPercent.rounded()))% Used")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
            }

            if let error = snapshot.error, !snapshot.windows.isEmpty || snapshot.isDemo {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundColor(.orange.opacity(0.85))
                    .lineLimit(2)
            }
        }
        .padding(16)
        .frame(width: 300, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.black)
        )
        .padding(8) // room for shadow
        .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
    }
}
