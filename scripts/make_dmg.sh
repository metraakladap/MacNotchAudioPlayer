#!/bin/bash
# Packages build/MacNotchPlayer.app into a distributable DMG with a drag-to-
# /Applications layout.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="MacNotchPlayer"
APP="build/${APP_NAME}.app"
DMG="build/${APP_NAME}.dmg"
VOL="Notch Player"
STAGE="build/dmg-stage"

[ -d "$APP" ] || { echo "Missing $APP — run build_app.sh first." >&2; exit 1; }

echo "==> Staging DMG contents"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

echo "==> Creating $DMG"
hdiutil create \
    -volname "$VOL" \
    -srcfolder "$STAGE" \
    -ov -format UDZO \
    "$DMG"

rm -rf "$STAGE"
echo "==> Done: $DMG"
