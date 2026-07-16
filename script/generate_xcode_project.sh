#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
VERSION=2.45.4

if command -v xcodegen >/dev/null 2>&1; then
  XCODEGEN=$(command -v xcodegen)
else
  TEMP_DIR=$(mktemp -d)
  trap 'rm -rf "$TEMP_DIR"' EXIT INT TERM
  curl -fsSL "https://github.com/yonaskolb/XcodeGen/releases/download/${VERSION}/xcodegen.zip" -o "$TEMP_DIR/xcodegen.zip"
  unzip -q "$TEMP_DIR/xcodegen.zip" -d "$TEMP_DIR"
  XCODEGEN="$TEMP_DIR/xcodegen/bin/xcodegen"
fi

cd "$ROOT/ios"
"$XCODEGEN" generate
