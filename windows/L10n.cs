using System.Globalization;
using System.IO;
using System.Reflection;
using System.Text;
using System.Text.RegularExpressions;

namespace Brink;

/// Localized string lookup. Keys are the English text; translations live in
/// embedded `Resources/Strings/<code>.strings` files (Apple .strings format,
/// carried over unchanged from the macOS app).
///
/// Language comes from the user's system unless overridden in the menu.
/// Unknown languages fall back to English (the key itself).
public static class L10n
{
    /// (code, native name) — order shown in the menu.
    public static readonly (string Code, string Name)[] Available =
    {
        ("en", "English"), ("tr", "Türkçe"), ("de", "Deutsch"), ("fr", "Français"),
        ("es", "Español"), ("pt-BR", "Português (Brasil)"), ("it", "Italiano"),
        ("ja", "日本語"), ("zh-Hans", "简体中文"), ("ko", "한국어"),
    };

    private static Dictionary<string, string>? _table;
    private static string? _loadedCode;

    public static string Override
    {
        get => Settings.Shared.Language;
        set
        {
            Settings.Shared.Language = value;
            Settings.Shared.Save();
            _table = null;
            _loadedCode = null;
        }
    }

    public static CultureInfo Culture
    {
        get
        {
            var code = EffectiveCode();
            try { return code == "en" ? CultureInfo.CurrentCulture : new CultureInfo(code); }
            catch { return CultureInfo.CurrentCulture; }
        }
    }

    private static string EffectiveCode()
    {
        var overrideCode = Override;
        if (!string.IsNullOrEmpty(overrideCode)) return overrideCode;
        var ui = CultureInfo.CurrentUICulture.Name;                 // e.g. "tr-TR"
        foreach (var (code, _) in Available)
            if (ui.Equals(code, StringComparison.OrdinalIgnoreCase)) return code;
        var lang = CultureInfo.CurrentUICulture.TwoLetterISOLanguageName; // "tr"
        if (lang == "zh") return "zh-Hans";
        if (lang == "pt") return "pt-BR";
        foreach (var (code, _) in Available)
            if (code.Equals(lang, StringComparison.OrdinalIgnoreCase)) return code;
        return "en";
    }

    private static Dictionary<string, string> Table()
    {
        var code = EffectiveCode();
        if (_table != null && _loadedCode == code) return _table;
        _table = LoadStrings(code);
        _loadedCode = code;
        return _table;
    }

    private static Dictionary<string, string> LoadStrings(string code)
    {
        var dict = new Dictionary<string, string>();
        var assembly = Assembly.GetExecutingAssembly();
        var suffix = "." + code + ".strings";
        var name = assembly.GetManifestResourceNames()
            .FirstOrDefault(n => n.EndsWith(suffix, StringComparison.OrdinalIgnoreCase));
        if (name == null) return dict;
        using var stream = assembly.GetManifestResourceStream(name);
        if (stream == null) return dict;
        using var reader = new StreamReader(stream, Encoding.UTF8);
        var text = reader.ReadToEnd();
        // "key" = "value";  with \" and \n escapes.
        var rx = new Regex("\"((?:[^\"\\\\]|\\\\.)*)\"\\s*=\\s*\"((?:[^\"\\\\]|\\\\.)*)\"\\s*;");
        foreach (Match m in rx.Matches(text))
            dict[Unescape(m.Groups[1].Value)] = Unescape(m.Groups[2].Value);
        return dict;
    }

    private static string Unescape(string s) =>
        s.Replace("\\\"", "\"").Replace("\\n", "\n").Replace("\\\\", "\\");

    /// printf-style formatting for the carried-over format strings:
    /// %@ and %d consume the next argument, %% is a literal percent sign.
    public static string L(string key, params object[] args)
    {
        var format = Table().TryGetValue(key, out var v) ? v : key;
        if (args.Length == 0 && !format.Contains('%')) return format;
        var sb = new StringBuilder();
        int arg = 0;
        for (int i = 0; i < format.Length; i++)
        {
            char c = format[i];
            if (c != '%' || i + 1 >= format.Length) { sb.Append(c); continue; }
            char next = format[i + 1];
            if (next == '%') { sb.Append('%'); i++; }
            else if (next == '@' || next == 'd')
            {
                sb.Append(arg < args.Length ? Convert.ToString(args[arg++], Culture) : "");
                i++;
            }
            else sb.Append(c);
        }
        return sb.ToString();
    }

    /// "Resets in 5 min" → "resets in 5 min" (used mid-sentence in notifications).
    public static string LowercasedFirst(this string s) =>
        s.Length == 0 ? s : char.ToLower(s[0], Culture) + s[1..];
}
