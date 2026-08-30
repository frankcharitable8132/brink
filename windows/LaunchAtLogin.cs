using Microsoft.Win32;

namespace Brink;

/// Start-at-login via the classic HKCU Run key.
public static class LaunchAtLogin
{
    private const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string Name = "Brink";

    private static string ExePath => Environment.ProcessPath ?? "";

    public static bool IsEnabled
    {
        get
        {
            using var key = Registry.CurrentUser.OpenSubKey(RunKey);
            return key?.GetValue(Name) is string;
        }
    }

    public static void Set(bool enabled)
    {
        try
        {
            using var key = Registry.CurrentUser.CreateSubKey(RunKey);
            if (enabled) key.SetValue(Name, $"\"{ExePath}\"");
            else key.DeleteValue(Name, throwOnMissingValue: false);
        }
        catch { }
    }
}
