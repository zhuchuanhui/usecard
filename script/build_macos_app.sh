#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
APP_PATH="$ROOT/UseCard.app"
STAGING="$ROOT/.build/macos/UseCard.app"

rm -rf "$STAGING"
mkdir -p "$STAGING/Contents/MacOS" "$STAGING/Contents/Resources"

swiftc \
  -target arm64-apple-macosx14.0 \
  "$ROOT/Sources/UseCardCore/Models.swift" \
  "$ROOT/Sources/UseCardCore/RecommendationEngine.swift" \
  "$ROOT/macos/UseCardMacApp/main.swift" \
  -framework AppKit \
  -framework CryptoKit \
  -o "$STAGING/Contents/MacOS/UseCard"

cp "$ROOT/macos/UseCardMacApp/Info.plist" "$STAGING/Contents/Info.plist"
cp "$ROOT/catalog/public/latest.json" "$STAGING/Contents/Resources/latest.json"
cp "$ROOT/catalog/public/official-lineups.json" "$STAGING/Contents/Resources/official-lineups.json"
plutil -lint "$STAGING/Contents/Info.plist" >/dev/null
codesign --force --sign - "$STAGING" >/dev/null

rm -rf "$APP_PATH"
mkdir -p "$(dirname -- "$APP_PATH")"
mv "$STAGING" "$APP_PATH"
printf '%s\n' "Built $APP_PATH"
