# Brink for Windows

Windows port of [Brink](https://github.com/semihtalii/brink) — your Claude Code,
Codex and Cursor usage limits at a glance, from the right screen edge.
Prebuilt exe: [Releases](https://github.com/semihtalii/brink/releases/latest)
(`Brink-Windows-x64.zip`).

Built with C# / WPF (.NET 8). No dock icon, no taskbar entry: a thin strip hugs
the right edge of the screen; move the mouse to it and it expands into a tab
with a usage ring per provider. Hover a ring for the detail card, right-click
anywhere on the panel for settings.

## Features (parity with the macOS app)

- Edge-activated slide-out panel with usage rings (Claude, Codex, Cursor)
- Detail bubble listing every usage window with reset countdowns
- Themes: Black and System (follows the Windows light/dark app theme, live).
  macOS's "Liquid Glass" is intentionally dropped: borderless WPF windows can't
  get real backdrop blur, and a translucent solid is just System-light anyway.
- Toast notifications when a limit fills up and again when it resets
  (reset toasts are scheduled, so they arrive even while idle)
- 10 languages, following the system language (same `.strings` files as macOS)
- Launch at login (HKCU Run key)
- Reads the CLIs' existing credentials — no API keys:
  - Claude: `%USERPROFILE%\.claude\.credentials.json`, falling back to the
    Windows Credential Manager entry `Claude Code-credentials`
  - Codex: `%CODEX_HOME%\auth.json` or `%USERPROFILE%\.codex\auth.json`
  - Cursor: `%USERPROFILE%\.cursor\cli-config.json`, falling back to the
    Credential Manager entry `cursor-access-token`

## Build & run

```
dotnet build Brink.csproj -c Release
bin\Release\net8.0-windows10.0.17763.0\Brink.exe
```

Self-contained single exe (no .NET runtime needed on the target machine):

```
dotnet publish Brink.csproj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true
```

Settings and the error log live in `%APPDATA%\Brink\`.
