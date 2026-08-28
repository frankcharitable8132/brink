# Contributing

Thanks for helping out. Brink is small on purpose; contributions that keep it
small are the most welcome.

## Setup

```bash
git clone https://github.com/semihtalii/brink.git
cd Brink
swift build          # debug build
./build.sh           # release .app + .dmg in dist/
open dist/Brink.app
```

Requires macOS 13+ and Xcode Command Line Tools. No Xcode project — it's a plain
Swift Package, so any editor works.

## Adding a provider

1. Create `Sources/Brink/<Name>Provider.swift` implementing `UsageProvider`.
2. Read credentials from wherever that CLI already stores them — never ask the
   user for a new API key.
3. Return a `ProviderSnapshot`; the first `UsageWindow` drives the ring.
4. Append it to the provider list in `main.swift`.
5. Document the credential path and endpoint in the README **Sources** section.

## Ground rules

- Tokens go to the provider's own API host only. No proxies, no telemetry.
- Never store refresh tokens. Never refresh tokens on the user's behalf.
- Keep the UI minimal; new options belong in the context menu, not a settings window.
- Run `./build.sh` before opening a PR; CI does the same on `macos-14`.

## Reporting a bug

Open an issue with your macOS version, which CLIs you have installed, and what
the ring / detail card shows. If an endpoint changed shape, paste the (redacted!)
JSON — remove any tokens and account ids first.
