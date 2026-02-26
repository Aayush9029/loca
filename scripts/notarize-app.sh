#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <path/to/Loca.app> [--profile <notary-profile>]"
  exit 1
fi

APP_PATH="$1"
shift
PROFILE="${LOCA_NOTARY_PROFILE:-}"
KEY_ID="${LOCA_NOTARY_KEY_ID:-}"
ISSUER_ID="${LOCA_NOTARY_ISSUER_ID:-}"
KEY_PATH="${LOCA_NOTARY_KEY_PATH:-}"
KEY_BASE64_PATH="${LOCA_NOTARY_KEY_BASE64_PATH:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile)
      PROFILE="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: $0 <path/to/Loca.app> [--profile <notary-profile>]"
      exit 1
      ;;
  esac
done

if [[ -z "$PROFILE" ]]; then
  if [[ -z "$KEY_ID" || -z "$ISSUER_ID" || ( -z "$KEY_PATH" && -z "$KEY_BASE64_PATH" ) ]]; then
    echo "Notary credentials are required."
    echo "Use either:"
    echo "  1) LOCA_NOTARY_PROFILE / --profile"
    echo "  2) LOCA_NOTARY_KEY_ID + LOCA_NOTARY_ISSUER_ID + (LOCA_NOTARY_KEY_PATH or LOCA_NOTARY_KEY_BASE64_PATH)"
    exit 1
  fi
fi

if [[ ! -d "$APP_PATH" ]]; then
  echo "App bundle not found: $APP_PATH"
  exit 1
fi

TMP_DIR="$(mktemp -d)"
ZIP_PATH="$TMP_DIR/$(basename "$APP_PATH").zip"
RESOLVED_KEY_PATH="$KEY_PATH"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"
if [[ -n "$PROFILE" ]]; then
  echo "Notarizing $(basename "$APP_PATH") with profile '$PROFILE'..."
  xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$PROFILE" --wait
else
  if [[ -z "$RESOLVED_KEY_PATH" && -n "$KEY_BASE64_PATH" ]]; then
    RESOLVED_KEY_PATH="$TMP_DIR/AuthKey_${KEY_ID}.p8"
    base64 --decode < "$KEY_BASE64_PATH" > "$RESOLVED_KEY_PATH"
  fi
  echo "Notarizing $(basename "$APP_PATH") with API key $KEY_ID..."
  xcrun notarytool submit "$ZIP_PATH" \
    --key "$RESOLVED_KEY_PATH" \
    --key-id "$KEY_ID" \
    --issuer "$ISSUER_ID" \
    --wait
fi

echo "Stapling notarization ticket..."
xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"

echo "Gatekeeper assessment:"
spctl -a -vv "$APP_PATH" || true
