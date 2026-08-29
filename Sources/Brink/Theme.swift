import SwiftUI
import AppKit

// MARK: - Theme choice (persisted)

enum Theme: String, CaseIterable, Identifiable {
    case black, glass, system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .black: return "Black"
        case .glass: return "Liquid Glass"
        case .system: return "System"
        }
    }
}

@MainActor
final class ThemeStore: ObservableObject {
    private static let key = "theme"

    @Published var theme: Theme {
        didSet { UserDefaults.standard.set(theme.rawValue, forKey: Self.key) }
    }

    init() {
        theme = Theme(rawValue: UserDefaults.standard.string(forKey: Self.key) ?? "") ?? .black
    }
}

// MARK: - Resolved palette

struct Palette {
    var isGlass: Bool
    var isDark: Bool

    var fg: Color
    var muted: Color
    var soft: Color
    var track: Color
    var barTrack: Color
    var cardBorder: Color
    var tint: Color        // colour laid over the blur (or the solid surface for .black)
    var stripTint: Color

    static func resolve(_ theme: Theme, systemDark: Bool) -> Palette {
        switch theme {
        case .black:
            return Palette(
                isGlass: false, isDark: true,
                fg: .white,
                muted: .white.opacity(0.48),
                soft: .white.opacity(0.72),
                track: .white.opacity(0.16),
                barTrack: .white.opacity(0.17),
                cardBorder: .clear,
                tint: Color(red: 8/255, green: 8/255, blue: 10/255).opacity(0.95),
                stripTint: Color(red: 10/255, green: 10/255, blue: 12/255).opacity(0.88)
            )
        case .glass:
            return light
        case .system:
            return systemDark ? dark : light
        }
    }

    private static let light = Palette(
        isGlass: true, isDark: false,
        fg: Color(red: 0x17/255, green: 0x17/255, blue: 0x1c/255),
        muted: Color(red: 15/255, green: 20/255, blue: 30/255).opacity(0.52),
        soft: Color(red: 15/255, green: 20/255, blue: 30/255).opacity(0.74),
        track: Color(red: 15/255, green: 20/255, blue: 30/255).opacity(0.15),
        barTrack: Color(red: 15/255, green: 20/255, blue: 30/255).opacity(0.14),
        cardBorder: .white.opacity(0.65),
        tint: .white.opacity(0.42),
        stripTint: .white.opacity(0.55)
    )

    private static let dark = Palette(
        isGlass: true, isDark: true,
        fg: .white,
        muted: .white.opacity(0.52),
        soft: .white.opacity(0.76),
        track: .white.opacity(0.18),
        barTrack: .white.opacity(0.18),
        cardBorder: .white.opacity(0.16),
        tint: Color(red: 28/255, green: 28/255, blue: 34/255).opacity(0.55),
        stripTint: Color(red: 40/255, green: 40/255, blue: 48/255).opacity(0.62)
    )

    var colorScheme: ColorScheme { isDark ? .dark : .light }
    var appearance: NSAppearance.Name { isDark ? .darkAqua : .aqua }
    var material: NSVisualEffectView.Material { isDark ? .hudWindow : .popover }
}

// MARK: - Blur (backdrop) view

struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var appearance: NSAppearance.Name

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.blendingMode = .behindWindow
        v.state = .active
        v.isEmphasized = true
        return v
    }

    func updateNSView(_ v: NSVisualEffectView, context: Context) {
        v.material = material
        v.appearance = NSAppearance(named: appearance)
    }
}

// MARK: - Surface = blur + tint + optional hairline, clipped to any shape

struct Surface<S: Shape>: View {
    var palette: Palette
    var shape: S
    var tint: Color? = nil
    var border: Bool = false

    var body: some View {
        ZStack {
            if palette.isGlass {
                // Give the AppKit view an explicit, finite frame: SwiftUI may otherwise
                // hand it NaN during the first layout pass (AppKit asserts on that).
                GeometryReader { geo in
                    let w = geo.size.width.isFinite ? max(geo.size.width, 1) : 1
                    let h = geo.size.height.isFinite ? max(geo.size.height, 1) : 1
                    VisualEffectBlur(material: palette.material, appearance: palette.appearance)
                        .frame(width: w, height: h)
                }
                .clipShape(shape)
                shape.fill(tint ?? palette.tint)
                if border {
                    shape.stroke(palette.cardBorder, lineWidth: 1)
                }
            } else {
                shape.fill(tint ?? palette.tint)
            }
        }
    }
}
