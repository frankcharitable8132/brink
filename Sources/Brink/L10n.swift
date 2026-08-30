import Foundation

/// Localized string lookup. Keys are the English text; translations live in
/// `Resources/<lang>.lproj/Localizable.strings`.
///
/// Language comes from the user's system preferences unless overridden in the
/// menu (Language → …). Unknown languages fall back to English.
enum L10n {
    static let overrideKey = "language"   // "" = system default, else a code below

    /// Where Brink's resources (logos, .lproj folders) live.
    ///
    /// In the packaged app `build.sh` copies them into `Contents/Resources`, so
    /// `Bundle.main` serves them the standard macOS way. Only when running straight
    /// from `swift build` (no .app) do we fall back to SwiftPM's `Bundle.module`.
    /// Never touch `Bundle.module` first: its accessor only knows the build-machine
    /// path and the .app root, and crashes on any other Mac (issue #8).
    static let resources: Bundle = {
        if Bundle.main.url(forResource: "claude", withExtension: "png") != nil { return Bundle.main }
        return Bundle.module
    }()

    /// (code, native name) — order shown in the menu.
    static let available: [(code: String, name: String)] = [
        ("en", "English"), ("tr", "Türkçe"), ("de", "Deutsch"), ("fr", "Français"),
        ("es", "Español"), ("pt-BR", "Português (Brasil)"), ("it", "Italiano"),
        ("ja", "日本語"), ("zh-Hans", "简体中文"), ("ko", "한국어"),
    ]

    static var override: String {
        get { UserDefaults.standard.string(forKey: overrideKey) ?? "" }
        set {
            UserDefaults.standard.set(newValue, forKey: overrideKey)
            cachedBundle = nil
        }
    }

    private static var cachedBundle: Bundle?

    /// Bundle to read strings from: the chosen language's .lproj, or the module
    /// bundle (which follows the system language) when no override is set.
    static var bundle: Bundle {
        if let cachedBundle { return cachedBundle }
        let code = override
        let b: Bundle
        // SwiftPM lower-cases .lproj folder names (zh-Hans → zh-hans); try both.
        if !code.isEmpty,
           let path = resources.path(forResource: code, ofType: "lproj")
                   ?? resources.path(forResource: code.lowercased(), ofType: "lproj"),
           let lb = Bundle(path: path) {
            b = lb
        } else {
            b = resources
        }
        cachedBundle = b
        return b
    }
}

func L(_ key: String, _ args: CVarArg...) -> String {
    let format = NSLocalizedString(key, tableName: nil, bundle: L10n.bundle, value: key, comment: "")
    return args.isEmpty ? format : String(format: format, locale: .current, arguments: args)
}

extension String {
    /// "Resets in 5 min" → "resets in 5 min" (used mid-sentence in notifications).
    var lowercasedFirst: String { prefix(1).lowercased() + dropFirst() }
}
