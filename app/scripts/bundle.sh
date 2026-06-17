#!/bin/bash
# Assemble FleetMap.app from the SwiftPM build output.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-debug}"
swift build --product FleetMap -c "$CONFIG"

BIN=".build/$CONFIG/FleetMap"
APP="FleetMap.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/FleetMap"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# carry the SwiftPM resource bundle (web assets for the graph view) if present
for b in ".build/$CONFIG"/*.bundle; do
    [ -e "$b" ] && cp -R "$b" "$APP/Contents/Resources/"
done

# Sign the bundle. When SIGN_IDENTITY is set (CI / Developer ID release), sign
# inside-out with the hardened runtime and a secure timestamp so the app can be
# notarized. --deep is intentionally NOT used: Apple no longer honours it for
# Developer ID distribution, so nested bundles are signed explicitly first.
# Otherwise fall back to an ad-hoc signature — enough for launchd/AX locally.
if [ -n "${SIGN_IDENTITY:-}" ]; then
    while IFS= read -r -d '' nested; do
        codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$nested"
    done < <(find "$APP/Contents/Resources" -name '*.bundle' -print0)
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
    codesign --verify --strict --verbose=2 "$APP"
    echo "built + signed $APP ($SIGN_IDENTITY)"
else
    codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true
    echo "built $APP (ad-hoc signed)"
fi
