#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <version>"
  echo "Example: $0 v0.1.1"
  exit 1
fi

VERSION="$1"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="$ROOT_DIR/dist"
BUILD_DIR="$ROOT_DIR/.build/release-artifacts"
APP_NAME="Loca.app"
NOTARY_PROFILE="${LOCA_NOTARY_PROFILE:-}"
RELEASE_SIGN="${LOCA_RELEASE_SIGN:-1}"
SIGN_TIMESTAMP="${LOCA_SIGN_TIMESTAMP:-1}"
NOTARY_KEY_ID="${LOCA_NOTARY_KEY_ID:-}"
NOTARY_ISSUER_ID="${LOCA_NOTARY_ISSUER_ID:-}"
NOTARY_KEY_PATH="${LOCA_NOTARY_KEY_PATH:-}"
NOTARY_KEY_BASE64_PATH="${LOCA_NOTARY_KEY_BASE64_PATH:-}"

mkdir -p "$OUT_DIR" "$BUILD_DIR"

swift build -c release --arch arm64 --arch x86_64

ARM_BIN="$ROOT_DIR/.build/arm64-apple-macosx/release/loca"
X86_BIN="$ROOT_DIR/.build/x86_64-apple-macosx/release/loca"
APPLE_UNIVERSAL_BIN="$ROOT_DIR/.build/apple/Products/Release/loca"
UNIVERSAL_BIN="$BUILD_DIR/loca"

if [[ -f "$APPLE_UNIVERSAL_BIN" ]]; then
  cp "$APPLE_UNIVERSAL_BIN" "$UNIVERSAL_BIN"
elif [[ -f "$ARM_BIN" && -f "$X86_BIN" ]]; then
  lipo -create -output "$UNIVERSAL_BIN" "$ARM_BIN" "$X86_BIN"
else
  echo "Could not locate release binary outputs."
  echo "Checked:"
  echo "  $APPLE_UNIVERSAL_BIN"
  echo "  $ARM_BIN"
  echo "  $X86_BIN"
  exit 1
fi

chmod +x "$UNIVERSAL_BIN"

# Build signed app bundle around the universal binary.
LOCA_RELEASE_SIGN="$RELEASE_SIGN" \
LOCA_SIGN_TIMESTAMP="$SIGN_TIMESTAMP" \
  "$ROOT_DIR/scripts/create-permission-app.sh" --output "$BUILD_DIR" --binary "$UNIVERSAL_BIN" >/dev/null

if [[ -n "$NOTARY_PROFILE" || ( -n "$NOTARY_KEY_ID" && -n "$NOTARY_ISSUER_ID" && ( -n "$NOTARY_KEY_PATH" || -n "$NOTARY_KEY_BASE64_PATH" ) ) ]]; then
  if [[ -n "$NOTARY_PROFILE" ]]; then
    "$ROOT_DIR/scripts/notarize-app.sh" "$BUILD_DIR/$APP_NAME" --profile "$NOTARY_PROFILE"
  else
    "$ROOT_DIR/scripts/notarize-app.sh" "$BUILD_DIR/$APP_NAME"
  fi
fi

ARCHIVE="$OUT_DIR/loca-${VERSION#v}-universal-macos.tar.gz"
tar -C "$BUILD_DIR" -czf "$ARCHIVE" "$APP_NAME"

if command -v shasum >/dev/null 2>&1; then
  SHA256=$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')
  echo "Archive: $ARCHIVE"
  echo "SHA256: $SHA256"
else
  echo "Archive: $ARCHIVE"
fi
