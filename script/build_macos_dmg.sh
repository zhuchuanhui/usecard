#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
APP_VERSION=$("$ROOT/script/resolve_app_version.sh")
DIST_DIR="$ROOT/dist"
DMG_PATH="$DIST_DIR/UseCard-$APP_VERSION.dmg"
DMG_SOURCE=$(mktemp -d "${TMPDIR:-/tmp}/usecard-dmg.XXXXXX")

cleanup() {
  rm -rf "$DMG_SOURCE"
}
trap cleanup EXIT INT TERM

"$ROOT/script/build_macos_app.sh"
mkdir -p "$DIST_DIR"
rm -f "$DMG_PATH"
cp -R "$ROOT/UseCard.app" "$DMG_SOURCE/UseCard.app"
ln -s /Applications "$DMG_SOURCE/Applications"

hdiutil create \
  -volname "UseCard $APP_VERSION" \
  -srcfolder "$DMG_SOURCE" \
  -ov \
  -format UDZO \
  "$DMG_PATH" >/dev/null

printf '%s\n' "Built $DMG_PATH"
