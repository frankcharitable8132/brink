using System.IO;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace Brink;

/// Persisted preferences — %APPDATA%\Brink\settings.json
/// (the WPF stand-in for UserDefaults in the macOS app).
public class Settings
{
    public string Theme { get; set; } = "black";          // black | glass | system
    public string Language { get; set; } = "";            // "" = system default
    public List<string> HiddenProviders { get; set; } = new();
    public List<string> ShownDemoProviders { get; set; } = new();
    public bool NotificationsEnabled { get; set; } = true;

    [JsonIgnore]
    public static Settings Shared { get; } = Load();

    public static string Dir =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "Brink");

    private static string FilePath => Path.Combine(Dir, "settings.json");

    private static Settings Load()
    {
        var settings = new Settings();
        try
        {
            if (File.Exists(FilePath))
                settings = JsonSerializer.Deserialize<Settings>(File.ReadAllText(FilePath)) ?? new Settings();
        }
        catch { }
        // "glass" existed in early builds; it folds into System (see ThemeExtensions).
        if (settings.Theme == "glass") settings.Theme = "system";
        return settings;
    }

    public void Save()
    {
        try
        {
            Directory.CreateDirectory(Dir);
            File.WriteAllText(FilePath, JsonSerializer.Serialize(this,
                new JsonSerializerOptions { WriteIndented = true }));
        }
        catch { }
    }

    // Provider visibility (Providers menu). At least one ring always stays.
    //
    // Two lists: HiddenProviders (user switched a real provider off) and
    // ShownDemoProviders (user switched on a provider whose CLI isn't logged
    // in, to see its DEMO ring). By default a provider shows only when it has
    // real data.

    public bool IsVisible(ProviderSnapshot snap)
    {
        if (HiddenProviders.Contains(snap.Id)) return false;
        if (snap.IsDemo) return ShownDemoProviders.Contains(snap.Id);
        return true;
    }

    public void SetVisible(ProviderSnapshot snap, bool visible, List<ProviderSnapshot> all)
    {
        if (visible)
        {
            HiddenProviders.Remove(snap.Id);
            if (snap.IsDemo && !ShownDemoProviders.Contains(snap.Id))
                ShownDemoProviders.Add(snap.Id);
        }
        else
        {
            if (snap.IsDemo) ShownDemoProviders.Remove(snap.Id);
            if (all.Count(IsVisible) > 1 && !HiddenProviders.Contains(snap.Id))
                HiddenProviders.Add(snap.Id);
        }
        Save();
    }

    public List<ProviderSnapshot> Visible(List<ProviderSnapshot> snapshots)
    {
        var shown = snapshots.Where(IsVisible).ToList();
        // Nothing real to show (no CLI logged in, nothing switched on): one
        // neutral ring whose card explains what to install — never fake numbers.
        return shown.Count == 0 ? new List<ProviderSnapshot> { Placeholder(snapshots) } : shown;
    }

    public const string PlaceholderId = "none";

    public static ProviderSnapshot Placeholder(List<ProviderSnapshot> snapshots)
    {
        var lines = string.Join("\n",
            snapshots.Select(s => $"○ {s.Name} — {s.Error ?? L10n.L("No data")}"));
        var text = string.Join("\n\n", new[]
        {
            L10n.L("No CLI found"),
            L10n.L("Brink reads your local logins. Sign in to Claude Code, Codex CLI or Cursor CLI and its ring appears automatically."),
            lines,
        });
        return new ProviderSnapshot { Id = PlaceholderId, Name = "Brink", Error = text };
    }
}
