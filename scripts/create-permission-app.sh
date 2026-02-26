#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Loca"
BUNDLE_ID="art.aayush.loca"
OUTPUT_DIR="$ROOT_DIR/dist"
SIGN_IDENTITY="${LOCA_SIGN_IDENTITY:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output)
      OUTPUT_DIR="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: $0 [--output <dir>]"
      exit 1
      ;;
  esac
done

APP_BUNDLE="$OUTPUT_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
BUILD_BIN="$ROOT_DIR/.build/release/loca"

if [[ ! -x "$BUILD_BIN" ]]; then
  echo "Release binary not found at $BUILD_BIN"
  echo "Run: swift build -c release"
  exit 1
fi

if [[ -z "$SIGN_IDENTITY" ]]; then
  SIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Developer ID Application/ {print $2; exit}')"
fi

if [[ -z "$SIGN_IDENTITY" ]]; then
  echo "No Developer ID Application signing identity found."
  echo "Set LOCA_SIGN_IDENTITY or install a Developer ID Application certificate."
  exit 1
fi

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS"

cp "$BUILD_BIN" "$APP_MACOS/loca"
chmod +x "$APP_MACOS/loca"

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
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleVersion</key>
  <string>0.1.0</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
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
codesign --force --deep --timestamp --options runtime \
  --entitlements "$ROOT_DIR/scripts/loca-sandbox.entitlements" \
  -s "$SIGN_IDENTITY" \
  "$APP_BUNDLE"

echo "$APP_BUNDLE"
