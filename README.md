# loca
Get your Mac's current location from the terminal.

## Installation

```bash
brew install aayush9029/tap/loca
```

Or:

```bash
brew tap aayush9029/tap
brew install loca
```

## Usage

```bash
loca
loca --json
loca --text
loca --timeout 30
loca --accuracy best
loca --status
```

`loca` uses CoreLocation first. If permission is unavailable or times out, it automatically falls back to IP-based city-level location.
Progress logs are shown only in the default mode (no `--json`/`--text`).
Output schema is consistent across both sources: `latitude`, `longitude`, `city`, `region`, `country`, `timestamp`, `source`.

## Options

| Flag | Description |
|------|-------------|
| `-h, --help` | Show help |
| `-v, --version` | Show version |
| `--status` | Print service + permission status only |
| `--text` | Plain text output (no progress logs) |
| `-j, --json` | Output JSON |
| `-t, --timeout <sec>` | Timeout in seconds (default: `20`) |
| `-a, --accuracy <best\|10m\|100m\|1km\|3km>` | Requested location accuracy (default: `100m`) |

## How it works

1. Checks Location Services and authorization state.
2. Requests one location update from `CoreLocation`.
3. If unavailable, falls back to reputable IP geolocation providers.
4. Reverse-geocodes coordinates to normalize city/region/country.
5. Returns the same schema for both sources (`core_location` or `ip_fallback`).

## Requirements

- macOS 13+
- Location Services enabled
- Terminal app (or your shell app) allowed in macOS Location Services

## Signed App Flow

For reliable macOS permission behavior in restrictive terminal hosts, create a signed hardened app wrapper:

```bash
swift build -c release
./scripts/create-permission-app.sh
./dist/Loca.app/Contents/MacOS/loca --json
```

## Local Release (Sign + Notarize)

Everything is local (no CI required):

```bash
# One-time: create notary profile in your keychain (dialog prompts supported)
./scripts/setup-notary-profile.sh loca-notary

# Build universal app, sign with Developer ID + hardened runtime + sandbox,
# notarize, staple, and package release archive:
LOCA_NOTARY_PROFILE=loca-notary ./scripts/package-universal.sh v0.1.0

# Alternative: notarize with ASC API key env vars instead of keychain profile
# LOCA_NOTARY_KEY_ID=... LOCA_NOTARY_ISSUER_ID=... LOCA_NOTARY_KEY_BASE64_PATH=... ./scripts/package-universal.sh v0.1.0
```

This produces `dist/loca-0.1.0-universal-macos.tar.gz` for GitHub Releases/Homebrew.

## License

MIT
