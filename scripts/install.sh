#!/bin/bash
# Installs MacNotchPlayer.app into /Applications and launches it.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="MacNotchPlayer"
APP="build/${APP_NAME}.app"
DEST="/Applications/${APP_NAME}.app"

[ -d "$APP" ] || { echo "Missing $APP — run build_app.sh first." >&2; exit 1; }

echo "==> Installing to $DEST"
# Quit any running instance first.
osascript -e 'tell application "MacNotchPlayer" to quit' >/dev/null 2>&1 || true
pkill -f "/Applications/${APP_NAME}.app" >/dev/null 2>&1 || true
sleep 1

rm -rf "$DEST"
cp -R "$APP" "$DEST"

# Strip quarantine so Gatekeeper doesn't block the dev-signed app.
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true

echo "==> Launching"
open "$DEST"
echo "==> Installed. Look for the music icon in the menu bar; hover the notch."
