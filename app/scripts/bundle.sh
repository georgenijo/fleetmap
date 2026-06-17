#!/bin/bash
# Assemble FleetMap.app from the SwiftPM build output.
#
# VARIANT (env var, or 2nd arg) selects the bundle identity:
#   unset / "stable" → FleetMap.app, id com.georgenijo.fleetmap   (the release build)
#   "dev"            → "FleetMap Dev.app", id com.georgenijo.fleetmap.dev
# A dev build installs side-by-side with the stable one — separate Dock icon,
# menu-bar item, and UserDefaults domain (so it defaults to the orbital UI).
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-debug}"
VARIANT="${VARIANT:-${2:-stable}}"
swift build --product FleetMap -c "$CONFIG"

BIN=".build/$CONFIG/FleetMap"

if [ "$VARIANT" = "dev" ]; then
    APP="FleetMap Dev.app"
else
    APP="FleetMap.app"
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/FleetMap"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# For the dev variant, derive a patched Info.plist (distinct id + name) from the
# stable one rather than hand-maintaining a second full plist. The .dev id gives
# it its own UserDefaults domain, so it defaults to the orbital UI (App.swift).
if [ "$VARIANT" = "dev" ]; then
    PLIST="$APP/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.georgenijo.fleetmap.dev" "$PLIST"
    /usr/libexec/PlistBuddy -c "Set :CFBundleName FleetMap Dev" "$PLIST"
    /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName FleetMap Dev" "$PLIST"
fi

# carry the SwiftPM resource bundle (web assets for the graph + orbital views) if present
for b in ".build/$CONFIG"/*.bundle; do
    [ -e "$b" ] && cp -R "$b" "$APP/Contents/Resources/"
done

# Sign the bundle. When SIGN_IDENTITY is set (CI / Developer ID release), sign
# inside-out with the hardened runtime and a secure timestamp so the app can be
# notarized. --deep is intentionally NOT used: Apple no longer honours it for
# Developer ID distribution, so nested bundles are signed explicitly first.
# Otherwise fall back to an ad-hoc signature — enough for launchd/AX locally.
if [ -n "${SIGN_IDENTITY:-}" ]; then
    # Sign only the .app. The nested SwiftPM resource bundle is resources-only
    # (web assets, no Mach-O), so codesign rejects signing it as code
    # ("bundle format unsuitable"); the app signature seals it as a sealed
    # resource instead. --deep is intentionally avoided per Apple guidance.
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
    codesign --verify --strict --verbose=2 "$APP"
    echo "built + signed $APP ($SIGN_IDENTITY)"
else
    codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true
    echo "built $APP (ad-hoc signed)"
fi
