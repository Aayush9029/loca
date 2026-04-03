<p align="center">
  <img src="assets/icon.png" width="128" alt="loca">
  <h1 align="center">loca</h1>
  <p align="center">Get your Mac's current location from the terminal</p>
</p>

<p align="center">
  <a href="https://github.com/Aayush9029/loca/releases/latest"><img src="https://img.shields.io/github/v/release/Aayush9029/loca" alt="Release"></a>
  <a href="https://github.com/Aayush9029/loca/blob/main/LICENSE"><img src="https://img.shields.io/github/license/Aayush9029/loca" alt="License"></a>
</p>

<p align="center">
  <img src="assets/demo.gif" alt="loca demo" width="800">
</p>

## Install

```bash
brew install aayush9029/tap/loca
```

Or tap first:

```bash
brew tap aayush9029/tap
brew install loca
```

## Usage

```bash
loca                        # get current location
loca --json                 # JSON output
loca --status               # check permission/service state
loca --timeout 30           # custom timeout
loca --accuracy best        # high accuracy mode
```

Falls back to IP-based location if CoreLocation is unavailable.

## License

MIT
