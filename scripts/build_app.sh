#!/bin/bash
# Builds MacNotchPlayer.app: compiles the release binary, assembles the bundle,
# embeds the mediaremote-adapter resources, and codesigns everything.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="MacNotchPlayer"
APP="build/${APP_NAME}.app"
SIGN_ID="${SIGN_ID:-Apple Development: artpadan@gmail.com (BPF43W7H5B)}"

echo "==> swift build (release)"
swift build -c release
BIN_PATH="$(swift build -c release --show-bin-path)"

echo "==> Assembling ${APP}"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN_PATH/${APP_NAME}" "$APP/Contents/MacOS/${APP_NAME}"
cp "Info.plist" "$APP/Contents/Info.plist"

# Bundle the adapter resources (script + helper framework + license).
cp "Resources/mediaremote-adapter.pl" "$APP/Contents/Resources/"
cp -R "Resources/MediaRemoteAdapter.framework" "$APP/Contents/Resources/"
cp "Resources/MediaRemoteAdapter-LICENSE.txt" "$APP/Contents/Resources/" 2>/dev/null || true

echo "==> Codesigning (identity: ${SIGN_ID})"
# Sign the embedded framework first, then the app bundle.
codesign --force --options runtime --timestamp=none \
    --sign "$SIGN_ID" \
    "$APP/Contents/Resources/MediaRemoteAdapter.framework/Versions/A/MediaRemoteAdapter"
codesign --force --options runtime --timestamp=none \
    --sign "$SIGN_ID" \
    "$APP/Contents/Resources/MediaRemoteAdapter.framework"
codesign --force --options runtime --timestamp=none \
    --sign "$SIGN_ID" \
    "$APP/Contents/MacOS/${APP_NAME}"
codesign --force --options runtime --timestamp=none \
    --sign "$SIGN_ID" \
    "$APP"

echo "==> Verifying signature"
codesign --verify --deep --strict --verbose=2 "$APP"

echo "==> Done: $APP"
