#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Reuse local/cached libraries, or an optional mirror of the original archive.
if python3 "$ROOT/scripts/validate-dependencies.py" --frameworks-only >/dev/null 2>&1; then
  echo "Using existing iOS arm64 Rime frameworks."
  exit 0
fi
if [[ -n "${LIBRIME_FRAMEWORKS_URL:-}" ]]; then
  TEMP_DIR="$(mktemp -d)"
  trap 'rm -rf "$TEMP_DIR"' EXIT
  curl -fL --retry 3 --connect-timeout 30 "$LIBRIME_FRAMEWORKS_URL" -o "$TEMP_DIR/Frameworks.tgz"
  if [[ -n "${LIBRIME_FRAMEWORKS_SHA256:-}" ]]; then
    echo "$LIBRIME_FRAMEWORKS_SHA256  $TEMP_DIR/Frameworks.tgz" | shasum -a 256 -c -
  fi
  tar -xzf "$TEMP_DIR/Frameworks.tgz" -C "$ROOT" Frameworks
else
  bash "$ROOT/scripts/build-rime-ios.sh"
fi
python3 "$ROOT/scripts/validate-dependencies.py" --frameworks-only
