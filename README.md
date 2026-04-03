<img src="assets/icon.png" width="128" alt="loca">

# loca

Get your Mac's current location from the terminal.

<p align="center"><img src="assets/demo.gif" alt="loca demo" width="800"></p>

## Install

```bash
brew install aayush9029/tap/loca
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

---

*More CLI tools: [`brew tap aayush9029/tap`](https://github.com/Aayush9029/homebrew-tap)*
