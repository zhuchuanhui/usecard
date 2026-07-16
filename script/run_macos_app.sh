#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
"$ROOT/script/build_macos_app.sh"
open "$ROOT/UseCard.app"
