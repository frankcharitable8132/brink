# Changelog

All notable changes to Brink are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow [SemVer](https://semver.org/).

## [Unreleased]

## [0.1.0] - 2026-08-29

### Added
- Right-edge slide-out panel with a usage ring per provider and a detail card on hover.
- Claude Code source: reads the OAuth token from the macOS Keychain (`Claude Code-credentials`) or `~/.claude/.credentials.json`; parses Anthropic's structured `limits` response (session / all models / per-model weekly) with a fallback for the older `five_hour` / `seven_day` shape.
- Codex source: reads `~/.codex/auth.json` and the ChatGPT usage endpoint.
- Auto-refresh every 2 minutes; **Refresh now** and **Quit** in the context menu.
- **Launch at login** toggle (SMAppService).
- `build.sh` producing `Brink.app` and `Brink.dmg`; GitHub Actions release on `v*` tags.

### Security
- Only the short-lived access token and its expiry are cached locally (`0600`). Refresh tokens are never stored and Brink never refreshes tokens itself, so it cannot invalidate Claude Code's session.

[Unreleased]: https://github.com/semihtalii/brink/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/semihtalii/brink/releases/tag/v0.1.0
