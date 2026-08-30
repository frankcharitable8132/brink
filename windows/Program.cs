using System.IO;
using System.Windows;

namespace Brink;

public static class Program
{
    [STAThread]
    public static void Main()
    {
        // Single instance.
        using var mutex = new Mutex(true, "BrinkEdgePanel", out bool isNew);
        if (!isNew) return;

        var app = new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };

        AppDomain.CurrentDomain.UnhandledException += (_, e) =>
            LogError(e.ExceptionObject as Exception);
        app.DispatcherUnhandledException += (_, e) =>
        {
            LogError(e.Exception);
            e.Handled = true;
        };

        var store = new UsageStore(new IUsageProvider[]
        {
            new ClaudeProvider(), new CodexProvider(), new CursorProvider(),
        });
        var panel = new EdgePanelWindow(store);
        panel.Show();
        store.StartAutoRefresh(TimeSpan.FromSeconds(120));

        app.Run();
    }

    private static void LogError(Exception? e)
    {
        try
        {
            Directory.CreateDirectory(Settings.Dir);
            File.AppendAllText(Path.Combine(Settings.Dir, "error.log"),
                $"[{DateTime.Now:yyyy-MM-dd HH:mm:ss}] {e}\r\n");
        }
        catch { }
    }
}
