#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <version>"
  echo "Example: $0 v0.1.0"
  exit 1
fi

VERSION="$1"
NAME="loca"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="$ROOT_DIR/dist"
BUILD_DIR="$ROOT_DIR/.build/release-artifacts"

mkdir -p "$OUT_DIR" "$BUILD_DIR"

swift build -c release --arch arm64 --arch x86_64

ARM_BIN="$ROOT_DIR/.build/arm64-apple-macosx/release/$NAME"
X86_BIN="$ROOT_DIR/.build/x86_64-apple-macosx/release/$NAME"
APPLE_UNIVERSAL_BIN="$ROOT_DIR/.build/apple/Products/Release/$NAME"
UNIVERSAL_BIN="$BUILD_DIR/$NAME"

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

ARCHIVE="$OUT_DIR/$NAME-${VERSION#v}-universal-macos.tar.gz"
tar -C "$BUILD_DIR" -czf "$ARCHIVE" "$NAME"

if command -v shasum >/dev/null 2>&1; then
  SHA256=$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')
  echo "Archive: $ARCHIVE"
  echo "SHA256: $SHA256"
else
  echo "Archive: $ARCHIVE"
fi
