using System.IO;
using System.Net.Http;
using System.Text.Json;
using static Brink.L10n;

namespace Brink;

/// Reads the Codex CLI's OAuth token (%USERPROFILE%\.codex\auth.json, or
/// %CODEX_HOME%\auth.json) and queries the ChatGPT backend usage endpoint.
public class CodexProvider : IUsageProvider
{
    public string Id => "codex";

    private const string UsageUrl = "https://chatgpt.com/backend-api/wham/usage";

    private record Auth(string AccessToken, string? AccountId);

    public async Task<ProviderSnapshot> FetchAsync()
    {
        var snap = new ProviderSnapshot { Id = Id, Name = "Codex" };
        var auth = LoadAuth();
        if (auth == null)
            return ClaudeProvider.DemoSnapshot("Codex", L("Codex CLI credentials not found (~/.codex/auth.json)"));

        try
        {
            using var request = new HttpRequestMessage(HttpMethod.Get, UsageUrl);
            request.Headers.TryAddWithoutValidation("Authorization", $"Bearer {auth.AccessToken}");
            if (auth.AccountId != null)
                request.Headers.TryAddWithoutValidation("ChatGPT-Account-Id", auth.AccountId);
            request.Headers.TryAddWithoutValidation("User-Agent", "Brink/1.0");
            using var response = await ClaudeProvider.Http.SendAsync(request);
            var status = (int)response.StatusCode;
            if (status != 200)
            {
                snap.Error = status == 401
                    ? L("Unauthorized — run `codex` once to refresh login")
                    : L("HTTP %d", status);
                return snap;
            }
            var body = await response.Content.ReadAsStringAsync();
            snap.Windows = ParseUsage(body);
            snap.UpdatedAt = DateTime.Now;
            if (snap.Windows.Count == 0) snap.Error = L("No usage data in response");
            return snap;
        }
        catch (Exception e)
        {
            snap.Error = e.Message;
            return snap;
        }
    }

    // MARK: Auth

    private static Auth? LoadAuth()
    {
        var home = Environment.GetEnvironmentVariable("CODEX_HOME")
            ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".codex");
        var file = Path.Combine(home, "auth.json");
        try
        {
            if (!File.Exists(file)) return null;
            using var doc = JsonDocument.Parse(File.ReadAllText(file));
            var root = doc.RootElement;
            JsonElement tokens = default;
            bool hasTokens = root.TryGetProperty("tokens", out tokens)
                && tokens.ValueKind == JsonValueKind.Object;
            var token = (hasTokens ? ClaudeProvider.GetString(tokens, "access_token") : null)
                ?? ClaudeProvider.GetString(root, "access_token");
            if (token == null) return null;
            var account = (hasTokens ? ClaudeProvider.GetString(tokens, "account_id") : null)
                ?? ClaudeProvider.GetString(root, "account_id");
            return new Auth(token, account);
        }
        catch { return null; }
    }

    // MARK: Parsing

    /// Expected shape (fields defensively probed):
    /// { "rate_limit": { "primary_window": { "used_percent": 21, ... },
    ///                   "secondary_window": { "used_percent": 52, ... } } }
    public static List<UsageWindow> ParseUsage(string data)
    {
        var windows = new List<UsageWindow>();
        try
        {
            using var doc = JsonDocument.Parse(data);
            var root = doc.RootElement;
            if (root.ValueKind != JsonValueKind.Object) return windows;
            JsonElement rateLimit = root;
            if (root.TryGetProperty("rate_limit", out var rl) && rl.ValueKind == JsonValueKind.Object)
                rateLimit = rl;
            else if (root.TryGetProperty("rate_limits", out var rls) && rls.ValueKind == JsonValueKind.Object)
                rateLimit = rls;

            (string Key, string Label)[] ordered =
            {
                ("primary_window", "Current session"),
                ("primary", "Current session"),
                ("secondary_window", "Weekly"),
                ("secondary", "Weekly"),
            };
            var seen = new HashSet<string>();
            foreach (var (key, label) in ordered)
            {
                if (seen.Contains(label)) continue;
                if (!rateLimit.TryGetProperty(key, out var dict) || dict.ValueKind != JsonValueKind.Object) continue;
                var pct = ClaudeProvider.GetNumber(dict, "used_percent");
                if (pct == null) continue;
                windows.Add(new UsageWindow { Label = label, UsedPercent = pct.Value, ResetsAt = ResetDate(dict) });
                seen.Add(label);
            }
        }
        catch { }
        return windows;
    }

    private static DateTime? ResetDate(JsonElement dict)
    {
        if (ClaudeProvider.GetNumber(dict, "resets_in_seconds") is double s)
            return DateTime.Now.AddSeconds(s);
        if (ClaudeProvider.GetIsoDate(dict, "resets_at") is DateTime iso)
            return iso;
        if (ClaudeProvider.GetNumber(dict, "resets_at") is double epoch)
        {
            // Could be seconds or milliseconds since epoch.
            var seconds = epoch > 10_000_000_000 ? epoch / 1000.0 : epoch;
            return DateTimeOffset.FromUnixTimeSeconds((long)seconds).LocalDateTime;
        }
        return null;
    }
}
