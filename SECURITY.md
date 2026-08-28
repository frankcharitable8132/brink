# Security

Brink reads login tokens that other tools (Claude Code, Codex CLI) already
keep on your Mac, and uses them to ask those vendors' own APIs for your usage.

## What it touches

| Data | Where it is read from | Where it is sent |
|---|---|---|
| Claude Code access token | macOS Keychain `Claude Code-credentials`, or `~/.claude/.credentials.json` | `api.anthropic.com` only |
| Codex access token + account id | `~/.codex/auth.json` | `chatgpt.com` only |

- All traffic is HTTPS to fixed hosts; App Transport Security is enabled.
- No analytics, no crash reporting, no third-party servers.
- Nothing is logged; tokens never appear in the UI.

## What it stores

`~/Library/Application Support/Brink/credentials.json` (mode `0600`) holds
only the **short-lived Claude access token and its expiry**, so the Keychain
prompt appears once instead of every refresh. Refresh tokens are never written
and never used. Delete the file at any time; Brink will re-read Claude Code's
store on the next refresh.

## Known limitations

- The usage endpoints are not official APIs; they may change or be disabled.
- Releases are currently ad-hoc signed (not notarized). Verify you downloaded
  from this repository's Releases page, or build from source.

## Reporting a vulnerability

Please do **not** open a public issue for security problems. Use GitHub's
private reporting instead: **Security → Report a vulnerability** on this
repository. You'll get a reply within a few days.
