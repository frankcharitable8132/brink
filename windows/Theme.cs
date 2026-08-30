using Microsoft.Win32;
using System.Windows.Media;
using static Brink.L10n;

namespace Brink;

// MARK: Theme choice (persisted in Settings)

public enum Theme { Black, System }

public static class ThemeExtensions
{
    public static string Title(this Theme t) => t switch
    {
        Theme.Black => L("Black"),
        _ => L("System"),
    };

    public static string Key(this Theme t) => t.ToString().ToLowerInvariant();

    /// "glass" existed in early Windows builds (and still does on macOS); without
    /// real blur it was just a translucent light look, so it folds into System.
    public static Theme FromKey(string key) => key switch
    {
        "glass" or "system" => Theme.System,
        _ => Theme.Black,
    };
}

// MARK: Resolved palette
//
// The macOS app also offers "Liquid Glass" with a real blur behind the panel;
// borderless per-pixel-transparent WPF windows can't get DWM blur, so the
// Windows build sticks to Black and System (translucent light/dark solids).

public class Palette
{
    public bool IsDark;
    public Color Fg, Muted, Soft, Track, BarTrack, CardBorder, Tint, StripTint;
    public bool TextShadow;

    private static Color Rgba(byte r, byte g, byte b, double a) =>
        Color.FromArgb((byte)Math.Round(a * 255), r, g, b);

    public static Palette Resolve(Theme theme) =>
        theme == Theme.Black ? BlackPalette : SystemIsDark() ? Dark : Light;

    /// Windows "apps" light/dark preference.
    public static bool SystemIsDark()
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(
                @"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize");
            return key?.GetValue("AppsUseLightTheme") is int v && v == 0;
        }
        catch { return false; }
    }

    private static readonly Palette BlackPalette = new()
    {
        IsDark = true,
        Fg = Colors.White,
        Muted = Rgba(255, 255, 255, 0.48),
        Soft = Rgba(255, 255, 255, 0.72),
        Track = Rgba(255, 255, 255, 0.16),
        BarTrack = Rgba(255, 255, 255, 0.17),
        CardBorder = Colors.Transparent,
        Tint = Rgba(8, 8, 10, 0.95),
        StripTint = Rgba(10, 10, 12, 0.88),
    };

    private static readonly Palette Light = new()
    {
        IsDark = false,
        Fg = Color.FromRgb(0x17, 0x17, 0x1C),
        Muted = Rgba(15, 20, 30, 0.52),
        Soft = Rgba(15, 20, 30, 0.74),
        Track = Rgba(15, 20, 30, 0.15),
        BarTrack = Rgba(15, 20, 30, 0.14),
        CardBorder = Rgba(255, 255, 255, 0.65),
        Tint = Rgba(250, 250, 252, 0.90),
        StripTint = Rgba(255, 255, 255, 0.80),
    };

    private static readonly Palette Dark = new()
    {
        IsDark = true,
        Fg = Colors.White,
        Muted = Rgba(255, 255, 255, 0.52),
        Soft = Rgba(255, 255, 255, 0.76),
        Track = Rgba(255, 255, 255, 0.18),
        BarTrack = Rgba(255, 255, 255, 0.18),
        CardBorder = Rgba(255, 255, 255, 0.16),
        Tint = Rgba(24, 24, 30, 0.90),
        StripTint = Rgba(255, 255, 255, 0.30),
        TextShadow = true,
    };
}
