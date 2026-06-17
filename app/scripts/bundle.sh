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

# ad-hoc sign so launchd/AX accept it locally
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true

echo "built $APP"
