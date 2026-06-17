#!/bin/bash
# Package FleetMap.app into a distributable DMG with an /Applications drop target.
# Prints the resulting DMG filename to stdout so CI can capture it.
#
# Usage: ./scripts/make-dmg.sh <version> [app-path]
#   SIGN_IDENTITY (optional) — Developer ID identity to sign the DMG with.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?usage: make-dmg.sh <version> [app-path]}"
APP="${2:-FleetMap.app}"
[ -d "$APP" ] || { echo "no $APP — run bundle.sh first" >&2; exit 1; }

DMG="FleetMap-${VERSION}.dmg"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"   # drag-to-install target

rm -f "$DMG"
hdiutil create \
    -volname "FleetMap $VERSION" \
    -srcfolder "$STAGE" \
    -fs HFS+ \
    -format UDZO -ov \
    "$DMG" >/dev/null

# Sign the DMG itself when a Developer ID identity is available. notarization
# staples its ticket to the DMG, so signing it first is the recommended order.
if [ -n "${SIGN_IDENTITY:-}" ]; then
    codesign --force --sign "$SIGN_IDENTITY" --timestamp "$DMG" >&2
fi

echo "$DMG"
