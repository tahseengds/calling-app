#!/usr/bin/env bash
# Build the release Flutter app and upload it to Firebase App Distribution.
#
# Prerequisites:
#   - flutter on PATH
#   - firebase CLI on PATH         ->  npm install -g firebase-tools
#   - authenticated, one of:
#       * firebase login
#       * $FIREBASE_TOKEN
#       * $GOOGLE_APPLICATION_CREDENTIALS -> service-account JSON with the
#         "Firebase App Distribution Admin" role
#   - android/app/google-services.json present (App ID read from it) unless
#     $FIREBASE_APP_ID / -a is supplied
#
# Usage:
#   ./scripts/distribute.sh [-g groups] [-t testers] [-n notes] [-a appId] [-b] [-N]
#     -g  comma-separated tester groups            (default: testers)
#     -t  comma-separated tester emails
#     -n  release notes        (default: "v<version>  -  <sha>  -  <date>")
#     -a  Firebase Android App ID override
#     -b  build an .aab instead of an .apk
#     -N  skip the build; upload the existing artifact
set -euo pipefail

GROUPS="testers"; TESTERS=""; NOTES=""; APPID=""; AAB=0; NOBUILD=0
while getopts "g:t:n:a:bN" opt; do
  case "$opt" in
    g) GROUPS="$OPTARG";;
    t) TESTERS="$OPTARG";;
    n) NOTES="$OPTARG";;
    a) APPID="$OPTARG";;
    b) AAB=1;;
    N) NOBUILD=1;;
    *) echo "Usage: $0 [-g groups] [-t testers] [-n notes] [-a appId] [-b] [-N]" >&2; exit 2;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(dirname "$SCRIPT_DIR")"
cd "$APP_DIR"

command -v flutter  >/dev/null || { echo "flutter not on PATH"; exit 1; }
command -v firebase >/dev/null || { echo "firebase CLI not on PATH (npm install -g firebase-tools)"; exit 1; }

PKG="com.lumin.app"

# ── Resolve the Firebase App ID ───────────────────────────────────────────────
if [[ -z "$APPID" ]]; then
  if [[ -n "${FIREBASE_APP_ID:-}" ]]; then
    APPID="$FIREBASE_APP_ID"
  else
    GS="$APP_DIR/android/app/google-services.json"
    [[ -f "$GS" ]] || { echo "No App ID and '$GS' missing. Pass -a or set FIREBASE_APP_ID." >&2; exit 1; }
    if command -v jq >/dev/null; then
      APPID=$(jq -r --arg p "$PKG" '.client[] | select(.client_info.android_client_info.package_name==$p) | .client_info.mobilesdk_app_id' "$GS" | head -n1)
      [[ -n "$APPID" && "$APPID" != "null" ]] || APPID=$(jq -r '.client[0].client_info.mobilesdk_app_id' "$GS")
    elif command -v python3 >/dev/null; then
      APPID=$(python3 - "$GS" "$PKG" <<'PY'
import json, sys
gs = json.load(open(sys.argv[1])); pkg = sys.argv[2]
for c in gs.get("client", []):
    if c.get("client_info", {}).get("android_client_info", {}).get("package_name") == pkg:
        print(c["client_info"]["mobilesdk_app_id"]); break
else:
    print(gs["client"][0]["client_info"]["mobilesdk_app_id"])
PY
)
    else
      echo "Need jq or python3 to read the App ID from google-services.json, or pass -a." >&2; exit 1
    fi
  fi
fi
echo "Firebase App ID : $APPID"

# ── Build ─────────────────────────────────────────────────────────────────────
if [[ "$AAB" -eq 1 ]]; then
  ARTIFACT="$APP_DIR/build/app/outputs/bundle/release/app-release.aab"
  BUILD=(build appbundle --release)
else
  ARTIFACT="$APP_DIR/build/app/outputs/flutter-apk/app-release.apk"
  BUILD=(build apk --release)
fi

if [[ "$NOBUILD" -eq 0 ]]; then
  echo "Building release artifact (${BUILD[*]})..."
  flutter "${BUILD[@]}"
fi
[[ -f "$ARTIFACT" ]] || { echo "Artifact not found: $ARTIFACT (run a build first)." >&2; exit 1; }
echo "Artifact        : $ARTIFACT"

# ── Release notes ─────────────────────────────────────────────────────────────
if [[ -z "$NOTES" ]]; then
  VER=$(grep -E '^version:' pubspec.yaml | head -n1 | sed -E 's/^version:[[:space:]]*//' | tr -d '\r')
  SHA=$(git rev-parse --short HEAD 2>/dev/null || echo "")
  NOTES="v$VER  -  $SHA  -  $(date '+%Y-%m-%d %H:%M')"
fi
echo "Release notes   : $NOTES"

# ── Distribute ────────────────────────────────────────────────────────────────
ARGS=(appdistribution:distribute "$ARTIFACT" --app "$APPID" --release-notes "$NOTES")
[[ -n "$GROUPS"  ]] && ARGS+=(--groups  "$GROUPS")
[[ -n "$TESTERS" ]] && ARGS+=(--testers "$TESTERS")
[[ -n "${FIREBASE_TOKEN:-}" ]] && ARGS+=(--token "$FIREBASE_TOKEN")

echo "Uploading to Firebase App Distribution..."
firebase "${ARGS[@]}"
echo "Done - release uploaded to Firebase App Distribution."
