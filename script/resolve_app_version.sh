#!/bin/sh
set -eu

# APP_VERSION is useful for local verification. Tagged GitHub Actions builds
# use GITHUB_REF_NAME, while a local checkout uses an exact matching Git tag.
RAW_VERSION=${APP_VERSION:-}

if [ -z "$RAW_VERSION" ] && [ "${GITHUB_REF_TYPE:-}" = "tag" ]; then
  RAW_VERSION=${GITHUB_REF_NAME:-}
fi

if [ -z "$RAW_VERSION" ]; then
  RAW_VERSION=$(git describe --tags --exact-match HEAD 2>/dev/null || true)
fi

if [ -z "$RAW_VERSION" ]; then
  RAW_VERSION=0.0.0
fi

VERSION=${RAW_VERSION#v}
case "$VERSION" in
  ''|*[!0-9.]*|.*|*.|*..*)
    printf '%s\n' "Invalid app version '$RAW_VERSION'. Use a numeric tag such as v1.2.3." >&2
    exit 1
    ;;
esac

case "$VERSION" in
  *.*.*)
    PATCH=${VERSION#*.*.}
    case "$PATCH" in
      *.*)
        printf '%s\n' "Invalid app version '$RAW_VERSION'. Use exactly three numeric parts such as v1.2.3." >&2
        exit 1
        ;;
    esac
    ;;
  *)
    printf '%s\n' "Invalid app version '$RAW_VERSION'. Use exactly three numeric parts such as v1.2.3." >&2
    exit 1
    ;;
esac

printf '%s\n' "$VERSION"
