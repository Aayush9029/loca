#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
INPUT_PNG="${1:-$ROOT_DIR/assets/location.png}"
OUTPUT_ICNS="${2:-$ROOT_DIR/assets/Loca.icns}"

if [[ ! -f "$INPUT_PNG" ]]; then
  echo "Input PNG not found: $INPUT_PNG"
  exit 1
fi

ICONSET_DIR="$(mktemp -d "$ROOT_DIR/.iconset.XXXXXX")/Loca.iconset"
mkdir -p "$ICONSET_DIR"

resize() {
  local size="$1"
  local out="$2"
  sips -z "$size" "$size" "$INPUT_PNG" --out "$ICONSET_DIR/$out" >/dev/null
}

resize 16 icon_16x16.png
resize 32 icon_16x16@2x.png
resize 32 icon_32x32.png
resize 64 icon_32x32@2x.png
resize 128 icon_128x128.png
resize 256 icon_128x128@2x.png
resize 256 icon_256x256.png
resize 512 icon_256x256@2x.png
resize 512 icon_512x512.png
resize 1024 icon_512x512@2x.png

iconutil -c icns "$ICONSET_DIR" -o "$OUTPUT_ICNS"
rm -rf "$(dirname "$ICONSET_DIR")"

echo "$OUTPUT_ICNS"
