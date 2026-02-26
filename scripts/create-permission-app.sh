#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Loca"
BUNDLE_ID="art.aayush.loca"
OUTPUT_DIR="$ROOT_DIR/dist"
SIGN_IDENTITY="${LOCA_SIGN_IDENTITY:-}"
USE_TIMESTAMP="${LOCA_SIGN_TIMESTAMP:-0}"
RELEASE_SIGN="${LOCA_RELEASE_SIGN:-0}"
BINARY_PATH=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output)
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --binary)
      BINARY_PATH="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: $0 [--output <dir>] [--binary <path>]"
      exit 1
      ;;
  esac
done

APP_BUNDLE="$OUTPUT_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
BUILD_BIN="${BINARY_PATH:-$ROOT_DIR/.build/release/loca}"
ICON_PATH="$ROOT_DIR/assets/Loca.icns"
LOGIN_KEYCHAIN="${LOCA_KEYCHAIN_PATH:-$HOME/Library/Keychains/login.keychain-db}"

if [[ ! -x "$BUILD_BIN" ]]; then
  echo "Release binary not found at $BUILD_BIN"
  echo "Run: swift build -c release"
  exit 1
fi

if [[ -z "$SIGN_IDENTITY" ]]; then
  if [[ "$RELEASE_SIGN" == "1" ]]; then
    SIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Developer ID Application/ {print $2; exit}')"
  else
    SIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Apple Development/ && $0 !~ /CSSMERR_TP_CERT_REVOKED/ {print $2; exit}')"
    if [[ -z "$SIGN_IDENTITY" ]]; then
      SIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Developer ID Application/ {print $2; exit}')"
    fi
  fi
fi

if [[ -z "$SIGN_IDENTITY" ]]; then
  echo "No suitable signing identity found."
  echo "Set LOCA_SIGN_IDENTITY to a valid code signing identity."
  exit 1
fi

unlock_keychain_with_osascript() {
  local password
  if command -v osascript >/dev/null 2>&1; then
    password="$(osascript <<'APPLESCRIPT'
display dialog "loca needs your macOS login password to unlock Keychain for code signing." with title "Unlock Keychain for Signing" default answer "" with hidden answer buttons {"Cancel", "Unlock"} default button "Unlock"
text returned of result
APPLESCRIPT
)" || true
  fi

  if [[ -z "${password:-}" ]] && [[ -t 1 ]]; then
    printf "Enter your macOS login password to unlock Keychain for signing: " >&2
    stty -echo
    read -r password
    stty echo
    printf "\n" >&2
  fi

  if [[ -z "${password:-}" ]]; then
    return 1
  fi

  security unlock-keychain -p "$password" "$LOGIN_KEYCHAIN" >/dev/null 2>&1 || return 1
  security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$password" "$LOGIN_KEYCHAIN" >/dev/null 2>&1 || true
  return 0
}

run_codesign() {
  local output
  if output="$(codesign "${SIGN_ARGS[@]}" "$APP_BUNDLE" 2>&1)"; then
    return 0
  fi

  if [[ "$output" == *"errSecInternalComponent"* ]] && [[ -t 1 ]]; then
    echo "codesign failed with errSecInternalComponent; attempting keychain unlock..." >&2
    if unlock_keychain_with_osascript; then
      if output="$(codesign "${SIGN_ARGS[@]}" "$APP_BUNDLE" 2>&1)"; then
        return 0
      fi
    fi
    echo "Could not unlock keychain for signing. Use your macOS login password (not root/sudo)." >&2
  fi

  echo "$output" >&2
  return 1
}

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS"
mkdir -p "$APP_RESOURCES"

cp "$BUILD_BIN" "$APP_MACOS/loca"
chmod +x "$APP_MACOS/loca"

if [[ -f "$ICON_PATH" ]]; then
  cp "$ICON_PATH" "$APP_RESOURCES/Loca.icns"
fi

cat >"$APP_CONTENTS/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>loca</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleIconFile</key>
  <string>Loca</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleVersion</key>
  <string>0.1.1</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.1</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSLocationUsageDescription</key>
  <string>loca needs location access to print latitude and longitude.</string>
  <key>NSLocationWhenInUseUsageDescription</key>
  <string>loca needs location access to print latitude and longitude.</string>
  <key>NSLocationAlwaysUsageDescription</key>
  <string>loca needs location access to print latitude and longitude.</string>
  <key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
  <string>loca needs location access to print latitude and longitude.</string>
</dict>
</plist>
EOF

# Always sign with sandbox + location entitlement + hardened runtime.
SIGN_ARGS=(--force --deep --options runtime --entitlements "$ROOT_DIR/scripts/loca-sandbox.entitlements" -s "$SIGN_IDENTITY")
if [[ "$USE_TIMESTAMP" == "1" ]]; then
  SIGN_ARGS+=(--timestamp)
fi

run_codesign

echo "$APP_BUNDLE"
