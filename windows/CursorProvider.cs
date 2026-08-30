using System.IO;
using System.Net.Http;
using System.Text.Json;
using static Brink.L10n;

namespace Brink;

/// Reads the Cursor CLI's session JWT and queries Cursor's `usage-summary`
/// endpoint — the source behind the "You've used N% of your included usage"
/// message in the Cursor app.
///
/// Windows credential lookup (the macOS build reads the Keychain item
/// "cursor-access-token" / "cursor-user"):
///  1) %USERPROFILE%\.cursor\cli-config.json — authInfo.accessToken, when the
///     CLI stores the token in the config itself
///  2) Credential Manager generic entries "cursor-access-token" / "cursor-user"
/// The numeric userId always comes from cli-config.json (authInfo.userId) and
/// prefixes the session cookie as "<userId>::<jwt>".
///
/// Brink never touches the refresh token — refreshing would rotate it and log
/// the user out of `cursor-agent`. Cursor exposes no public usage API, so every
/// field is probed defensively.
public class CursorProvider : IUsageProvider
{
    public string Id => "cursor";

    private const string UsageUrl = "https://cursor.com/api/usage-summary";

    private static string? _tokenCache;
    private static string? _userIdCache;

    public async Task<ProviderSnapshot> FetchAsync()
    {
        var snap = new ProviderSnapshot { Id = Id, Name = "Cursor" };
        var token = LoadToken();
        var userId = LoadUserId();
        if (token == null || userId == null)
            return ClaudeProvider.DemoSnapshot("Cursor",
                L("Cursor CLI credentials not found — run `cursor-agent login`"));

        try
        {
            var (data, status) = await RequestUsageAsync(token, userId);
            if (status is 401 or 403)
            {
                // cursor-agent rotated its token: drop cache, re-read once.
                ClearCache();
                var fresh = LoadToken();
                if (fresh != null && fresh != token)
                    (data, status) = await RequestUsageAsync(fresh, userId);
            }
            if (status is 401 or 403)
            {
                snap.Error = L("Unauthorized — run `cursor-agent login` to refresh");
                return snap;
            }
            if (status != 200)
            {
                snap.Error = L("HTTP %d", status);
                return snap;
            }
            snap.Windows = ParseUsage(data);
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

    private static async Task<(string Data, int Status)> RequestUsageAsync(string token, string userId)
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, UsageUrl);
        // Session-cookie auth: "WorkosCursorSessionToken=<userId>::<jwt>", ":" percent-encoded.
        request.Headers.TryAddWithoutValidation("Cookie",
            $"WorkosCursorSessionToken={userId}%3A%3A{token}");
        request.Headers.TryAddWithoutValidation("User-Agent", "Brink/1.0");
        using var response = await ClaudeProvider.Http.SendAsync(request);
        var body = await response.Content.ReadAsStringAsync();
        return (body, (int)response.StatusCode);
    }

    // MARK: Parsing

    /// usage-summary shape (fields probed defensively):
    /// { individualUsage: { plan: { totalPercentUsed, autoPercentUsed, apiPercentUsed, ... },
    ///                      onDemand: { enabled, limit, used } },
    ///   isUnlimited, billingCycleEnd }
    /// Labels are stored as keys and localized at render time.
    public static List<UsageWindow> ParseUsage(string data)
    {
        var windows = new List<UsageWindow>();
        try
        {
            using var doc = JsonDocument.Parse(data);
            var root = doc.RootElement;
            if (root.ValueKind != JsonValueKind.Object) return windows;
            var reset = ClaudeProvider.GetIsoDate(root, "billingCycleEnd");

            // Unlimited plans have no meaningful percentage to show.
            if (GetFlag(root, "isUnlimited"))
            {
                windows.Add(new UsageWindow { Label = "Included usage", UsedPercent = 0, ResetsAt = reset });
                return windows;
            }

            JsonElement plan = default, onDemand = default;
            bool hasPlan = false, hasOnDemand = false;
            if (root.TryGetProperty("individualUsage", out var individual)
                && individual.ValueKind == JsonValueKind.Object)
            {
                hasPlan = individual.TryGetProperty("plan", out plan)
                    && plan.ValueKind == JsonValueKind.Object;
                hasOnDemand = individual.TryGetProperty("onDemand", out onDemand)
                    && onDemand.ValueKind == JsonValueKind.Object;
            }

            if (hasPlan)
            {
                // Headline window — total included usage (matches the app's banner).
                if (ClaudeProvider.GetNumber(plan, "totalPercentUsed") is double total)
                    windows.Add(new UsageWindow { Label = "Included usage", UsedPercent = total, ResetsAt = reset });
                if (ClaudeProvider.GetNumber(plan, "autoPercentUsed") is double auto)
                    windows.Add(new UsageWindow { Label = "Auto", UsedPercent = auto, ResetsAt = reset });
                if (ClaudeProvider.GetNumber(plan, "apiPercentUsed") is double api)
                    windows.Add(new UsageWindow { Label = "API", UsedPercent = api, ResetsAt = reset });
            }

            // On-demand / usage-based spend, only when the user has enabled it.
            if (hasOnDemand && GetFlag(onDemand, "enabled")
                && ClaudeProvider.GetNumber(onDemand, "used") is double used
                && ClaudeProvider.GetNumber(onDemand, "limit") is double limit && limit > 0)
            {
                windows.Add(new UsageWindow
                {
                    Label = "On-demand",
                    UsedPercent = used / limit * 100,
                    ResetsAt = reset,
                });
            }
        }
        catch { }
        return windows;
    }

    /// Bool-or-number flag: true, 1 and "1" all count.
    private static bool GetFlag(JsonElement obj, string key)
    {
        if (obj.ValueKind != JsonValueKind.Object || !obj.TryGetProperty(key, out var v)) return false;
        return v.ValueKind switch
        {
            JsonValueKind.True => true,
            JsonValueKind.Number => v.GetDouble() != 0,
            JsonValueKind.String => v.GetString() == "1" || v.GetString() == "true",
            _ => false,
        };
    }

    // MARK: Credentials

    private static string ConfigPath => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".cursor", "cli-config.json");

    private static string? LoadToken()
    {
        if (_tokenCache != null) return _tokenCache;

        if (ReadConfigString("accessToken") is string fromConfig && fromConfig.Length > 0)
            return _tokenCache = fromConfig;

        foreach (var target in new[] { "cursor-access-token", "cursor-user" })
        {
            var value = CredentialManager.ReadGeneric(target)?.Trim();
            if (!string.IsNullOrEmpty(value))
                return _tokenCache = value;
        }
        return null;
    }

    /// The numeric Cursor userId lives in cli-config.json under authInfo.userId.
    private static string? LoadUserId()
    {
        if (_userIdCache != null) return _userIdCache;
        var id = ReadConfigString("userId");
        if (id != null) _userIdCache = id;
        return id;
    }

    private static string? ReadConfigString(string key)
    {
        try
        {
            if (!File.Exists(ConfigPath)) return null;
            using var doc = JsonDocument.Parse(File.ReadAllText(ConfigPath));
            if (!doc.RootElement.TryGetProperty("authInfo", out var auth)
                || auth.ValueKind != JsonValueKind.Object) return null;
            if (!auth.TryGetProperty(key, out var v)) return null;
            return v.ValueKind switch
            {
                JsonValueKind.String => v.GetString(),
                JsonValueKind.Number => ((long)v.GetDouble()).ToString(),
                _ => null,
            };
        }
        catch { return null; }
    }

    private static void ClearCache()
    {
        _tokenCache = null;
        _userIdCache = null;
    }
}
