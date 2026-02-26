#!/usr/bin/env bash
set -euo pipefail

PROFILE="${1:-loca-notary}"
DEFAULT_TEAM_ID="${LOCA_TEAM_ID:-4538W4A79B}"

read_with_osascript() {
  local prompt="$1"
  local title="$2"
  local hidden="${3:-0}"
  local default_value="${4:-}"

  if [[ "$hidden" == "1" ]]; then
    osascript <<APPLESCRIPT
display dialog "$prompt" with title "$title" default answer "$default_value" with hidden answer buttons {"Cancel", "OK"} default button "OK"
text returned of result
APPLESCRIPT
  else
    osascript <<APPLESCRIPT
display dialog "$prompt" with title "$title" default answer "$default_value" buttons {"Cancel", "OK"} default button "OK"
text returned of result
APPLESCRIPT
  fi
}

APPLE_ID=""
APP_PASSWORD=""
TEAM_ID=""

if command -v osascript >/dev/null 2>&1; then
  APPLE_ID="$(read_with_osascript "Enter Apple ID email for notarization." "Loca Notary Setup" 0 "")" || true
  APP_PASSWORD="$(read_with_osascript "Enter app-specific password for notarization (not your macOS login password)." "Loca Notary Setup" 1 "")" || true
  TEAM_ID="$(read_with_osascript "Enter Apple Developer Team ID." "Loca Notary Setup" 0 "$DEFAULT_TEAM_ID")" || true
fi

if [[ -z "${APPLE_ID:-}" ]]; then
  read -r -p "Apple ID email: " APPLE_ID
fi
if [[ -z "${APP_PASSWORD:-}" ]]; then
  printf "App-specific password: "
  stty -echo
  read -r APP_PASSWORD
  stty echo
  printf "\n"
fi
if [[ -z "${TEAM_ID:-}" ]]; then
  read -r -p "Apple Developer Team ID [$DEFAULT_TEAM_ID]: " TEAM_ID
  TEAM_ID="${TEAM_ID:-$DEFAULT_TEAM_ID}"
fi

if [[ -z "$APPLE_ID" || -z "$APP_PASSWORD" || -z "$TEAM_ID" ]]; then
  echo "Missing Apple ID, app-specific password, or Team ID."
  exit 1
fi

xcrun notarytool store-credentials "$PROFILE" \
  --apple-id "$APPLE_ID" \
  --team-id "$TEAM_ID" \
  --password "$APP_PASSWORD"

echo "Stored notary profile: $PROFILE"
