#!/bin/bash

set -euo pipefail

RAW_BASE_URL="https://raw.githubusercontent.com/ojaskandy/airlift/main"
SOURCE_PATH="${BASH_SOURCE[0]:-}"
ROOT=""

if [ -n "$SOURCE_PATH" ] && [ -f "$SOURCE_PATH" ]; then
  ROOT="$(cd "$(dirname "$SOURCE_PATH")" && pwd)"
fi

if [ "${1:-}" = "--worker" ]; then
  shift
  if [ -n "$ROOT" ] && [ -f "$ROOT/install-worker.sh" ]; then
    exec "$ROOT/install-worker.sh" "$@"
  fi
  command -v curl >/dev/null 2>&1 || {
    printf 'Error: curl is required to download the worker installer.\n' >&2
    exit 1
  }
  worker_installer="$(mktemp "${TMPDIR:-/tmp}/airlift-worker-installer.XXXXXX")"
  if ! curl -fsSL "$RAW_BASE_URL/install-worker.sh" -o "$worker_installer"; then
    rm -f "$worker_installer"
    printf 'Error: could not download the Airlift worker installer from GitHub.\n' >&2
    exit 1
  fi
  if /bin/bash "$worker_installer" "$@"; then
    status="0"
  else
    status="$?"
  fi
  rm -f "$worker_installer"
  exit "$status"
fi

if [ "$#" -gt 0 ]; then
  printf 'Usage: ./install.sh [--worker [--dry-run]]\n' >&2
  exit 1
fi

BIN_DIR="$HOME/.local/bin"
TARGET="$BIN_DIR/airlift"
PROFILE="$HOME/.zprofile"
MARKER="# Added by Airlift installer"
AIRLIFT_SOURCE=""
DOWNLOADED=""

if [ -n "$ROOT" ] && [ -f "$ROOT/airlift" ]; then
  AIRLIFT_SOURCE="$ROOT/airlift"
else
  command -v curl >/dev/null 2>&1 || {
    printf 'Error: curl is required to download the Airlift CLI.\n' >&2
    exit 1
  }
  DOWNLOADED="$(mktemp "${TMPDIR:-/tmp}/airlift-cli.XXXXXX")"
  if ! curl -fsSL "$RAW_BASE_URL/airlift" -o "$DOWNLOADED"; then
    rm -f "$DOWNLOADED"
    printf 'Error: could not download Airlift from GitHub.\n' >&2
    exit 1
  fi
  AIRLIFT_SOURCE="$DOWNLOADED"
fi

mkdir -p "$BIN_DIR"
cp "$AIRLIFT_SOURCE" "$TARGET"
chmod +x "$TARGET"
[ -z "$DOWNLOADED" ] || rm -f "$DOWNLOADED"

touch "$PROFILE"
if ! grep -F "$MARKER" "$PROFILE" >/dev/null 2>&1; then
  {
    printf '\n%s\n' "$MARKER"
    printf 'export PATH="$HOME/.local/bin:$PATH"\n'
  } >>"$PROFILE"
fi

printf 'Installed Airlift at %s\n' "$TARGET"
printf 'Restart Terminal or run: export PATH="$HOME/.local/bin:$PATH"\n'
