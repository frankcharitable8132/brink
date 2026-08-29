# Changelog

All notable changes to Brink are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow [SemVer](https://semver.org/).

## [Unreleased]

## [0.2.0] - 2026-08-29

### Added
- Notifications: when any usage window (session / weekly / per-model) reaches 100 %, and again when it resets — the reset one is scheduled for the exact reset time. Toggle + test item in the menu.
- Localization in 10 languages, following the macOS system language by default; **Language** menu to override.
- Panel folds away when the mouse moves far (> 480 pt) from the edge.

### Changed
- Liquid Glass / System now use Apple's adaptive `.regular` glass with system text styles, so type flips light/dark with the background.
- Slimmer proportions from the v2 design (78 pt tab, 48 pt rings, 296 pt card); card shadow removed.
- Right-click menu available on the detail card as well.

### Fixed
- Token rotation by Claude Code no longer shows "Unauthorized" until the next cycle — Brink re-reads and retries immediately.
- CI builds on `macos-26` (required for the Liquid Glass SDK).

## [0.1.0] - 2026-08-29

### Added
- Appearance menu: **Black**, **Liquid Glass**, **System** — real Liquid Glass (`.glassEffect`) on macOS 26+, `NSVisualEffectView` blur on older systems; choice persisted.
- Notch-style tab shape, hover-scaling rings, detail card that glides between rings with a crossfade.
- Provider logos as template images.
- Right-click anywhere on the panel or the detail card for the settings menu.
- If Claude Code rotates its token, Brink re-reads it and retries immediately instead of showing "Unauthorized" until the next cycle.
- `BRINK_PREVIEW=1` starts expanded with the first card open (screenshots / design review).
- Right-edge slide-out panel with a usage ring per provider and a detail card on hover.
- Claude Code source: reads the OAuth token from the macOS Keychain (`Claude Code-credentials`) or `~/.claude/.credentials.json`; parses Anthropic's structured `limits` response (session / all models / per-model weekly) with a fallback for the older `five_hour` / `seven_day` shape.
- Codex source: reads `~/.codex/auth.json` and the ChatGPT usage endpoint.
- Auto-refresh every 2 minutes; **Refresh now** and **Quit** in the context menu.
- **Launch at login** toggle (SMAppService).
- `build.sh` producing `Brink.app` and `Brink.dmg`; GitHub Actions release on `v*` tags.

### Security
- Only the short-lived access token and its expiry are cached locally (`0600`). Refresh tokens are never stored and Brink never refreshes tokens itself, so it cannot invalidate Claude Code's session.

[Unreleased]: https://github.com/semihtalii/brink/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/semihtalii/brink/releases/tag/v0.2.0
[0.1.0]: https://github.com/semihtalii/brink/releases/tag/v0.1.0
