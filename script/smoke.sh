#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"

npm --prefix services/catalog run typecheck
npm --prefix services/catalog test

mkdir -p .build/manual
swiftc \
  Sources/UseCardCore/Models.swift \
  Sources/UseCardCore/RecommendationEngine.swift \
  Tools/UseCardSmoke/main.swift \
  -o .build/manual/usecard-smoke
.build/manual/usecard-smoke

jq -e '.schemaVersion == 1 and (.products | length) > 0' catalog/public/latest.json >/dev/null
jq -e '.schemaVersion == 1 and .productCount > 0' catalog/public/manifest.json >/dev/null
jq -e 'type == "array" and all(.[]; (.issuerID | type == "string") and (.cards | type == "array"))' catalog/public/official-lineups.json >/dev/null
cmp -s catalog/config/official-card-lineups.json catalog/public/official-lineups.json
