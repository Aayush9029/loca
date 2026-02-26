#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="$ROOT_DIR/dist/e2e"
APP_BUNDLE_ID="art.aayush.loca"
APP_PATH="$ROOT_DIR/dist/Loca.app"
APP_BIN="$APP_PATH/Contents/MacOS/loca"
OUT_JSON="$OUT_DIR/loca-output.json"
OUT_LOG="$OUT_DIR/loca-progress.log"
SHOT_BEFORE="$OUT_DIR/screen-before.png"
SHOT_AFTER="$OUT_DIR/screen-after.png"

mkdir -p "$OUT_DIR"

echo "1) Build release binary"
cd "$ROOT_DIR"
swift build -c release

echo "2) Create signed app wrapper"
chmod +x "$ROOT_DIR/scripts/create-permission-app.sh"
"$ROOT_DIR/scripts/create-permission-app.sh" >/dev/null

echo "3) Reset location permission state for app identity (best effort)"
tccutil reset Location "$APP_BUNDLE_ID" || true

if command -v screencapture >/dev/null 2>&1; then
  echo "4) Capture pre-run screenshot"
  screencapture -x "$SHOT_BEFORE" || true
fi

echo "5) Start UI auto-accept helper (best effort)"
osascript <<'APPLESCRIPT' >/dev/null 2>&1 &
tell application "System Events"
  repeat 120 times
    delay 0.5
    try
      set procNames to {"SecurityAgent", "System Settings", "Terminal", "Ghostty", "loca"}
      repeat with pName in procNames
        if exists process pName then
          tell process pName
            repeat with w in windows
              if exists button "Allow While Using App" of w then
                click button "Allow While Using App" of w
                return
              end if
              if exists button "Allow" of w then
                click button "Allow" of w
                return
              end if
              if exists button "OK" of w then
                click button "OK" of w
                return
              end if
            end repeat
          end tell
        end if
      end repeat
    end try
  end repeat
end tell
APPLESCRIPT

echo "6) Run loca from app identity and capture output"
"$APP_BIN" --json >"$OUT_JSON" 2>"$OUT_LOG" || true

if command -v screencapture >/dev/null 2>&1; then
  echo "7) Capture post-run screenshot"
  screencapture -x "$SHOT_AFTER" || true
fi

echo "8) Validate JSON schema"
jq -e '.latitude and .longitude and .city != null and .region != null and .country != null and .timestamp and .source' "$OUT_JSON" >/dev/null

echo
echo "E2E complete."
echo "App path: $APP_PATH"
echo "JSON: $OUT_JSON"
echo "Progress log: $OUT_LOG"
echo "Screenshot before: $SHOT_BEFORE"
echo "Screenshot after: $SHOT_AFTER"
echo
cat "$OUT_LOG"
cat "$OUT_JSON"
