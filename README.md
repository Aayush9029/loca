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
loca --timeout 30
loca --accuracy best
loca --status
```

`loca` uses CoreLocation first. If permission is unavailable or times out, it automatically falls back to IP-based city-level location.
In interactive terminals, progress messages are shown on `stderr` while location is resolving.
Output schema is consistent across both sources: `latitude`, `longitude`, `city`, `region`, `country`, `timestamp`, `source`.

## Options

| Flag | Description |
|------|-------------|
| `-h, --help` | Show help |
| `-v, --version` | Show version |
| `--status` | Print service + permission status only |
| `-j, --json` | Output JSON |
| `-f, --format <text\|json>` | Output format (default: `text`) |
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

## License

MIT
