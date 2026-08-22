#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
APP_PATH="$ROOT/UseCard.app"
STAGING="$ROOT/.build/macos/UseCard.app"
APP_VERSION=$("$ROOT/script/resolve_app_version.sh")

rm -rf "$STAGING"
mkdir -p "$STAGING/Contents/MacOS" "$STAGING/Contents/Resources"

swiftc \
  -target arm64-apple-macosx14.0 \
  "$ROOT/Sources/UseCardCore/Models.swift" \
  "$ROOT/Sources/UseCardCore/SharedHoldings.swift" \
  "$ROOT/Sources/UseCardCore/RecommendationEngine.swift" \
  "$ROOT/Sources/UseCardCore/AlternativePayments.swift" \
  "$ROOT/macos/UseCardMacApp/main.swift" \
  -framework AppKit \
  -framework CryptoKit \
  -o "$STAGING/Contents/MacOS/UseCard"

cp "$ROOT/macos/UseCardMacApp/Info.plist" "$STAGING/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $APP_VERSION" "$STAGING/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $APP_VERSION" "$STAGING/Contents/Info.plist"
cp "$ROOT/macos/UseCardMacApp/Resources/UseCard.icns" "$STAGING/Contents/Resources/UseCard.icns"
cp "$ROOT/macos/UseCardMacApp/Resources/UseCardNight.icns" "$STAGING/Contents/Resources/UseCardNight.icns"
cp "$ROOT/catalog/public/latest.json" "$STAGING/Contents/Resources/latest.json"
cp "$ROOT/catalog/public/official-lineups.json" "$STAGING/Contents/Resources/official-lineups.json"
cp "$ROOT/catalog/public/payment-alternatives.json" "$STAGING/Contents/Resources/payment-alternatives.json"
plutil -lint "$STAGING/Contents/Info.plist" >/dev/null
if [ -n "${DEVELOPMENT_TEAM:-}" ] && [ -n "${CODE_SIGN_IDENTITY:-}" ]; then
  ENTITLEMENTS="$STAGING/Contents/UseCard.entitlements"
  sed "s/\$(TeamIdentifierPrefix)/${DEVELOPMENT_TEAM}./g" \
    "$ROOT/macos/UseCardMacApp/UseCard.entitlements" > "$ENTITLEMENTS"
  codesign --force --sign "$CODE_SIGN_IDENTITY" --entitlements "$ENTITLEMENTS" "$STAGING" >/dev/null
  rm -f "$ENTITLEMENTS"
else
  codesign --force --sign - "$STAGING" >/dev/null
fi

rm -rf "$APP_PATH"
mkdir -p "$(dirname -- "$APP_PATH")"
mv "$STAGING" "$APP_PATH"
printf '%s\n' "Built $APP_PATH (version $APP_VERSION)"
