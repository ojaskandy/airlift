#!/bin/bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
BIN_DIR="$HOME/.local/bin"
TARGET="$BIN_DIR/airlift"
PROFILE="$HOME/.zprofile"
MARKER="# Added by Airlift installer"

mkdir -p "$BIN_DIR"
cp "$ROOT/airlift" "$TARGET"
chmod +x "$TARGET"

touch "$PROFILE"
if ! grep -F "$MARKER" "$PROFILE" >/dev/null 2>&1; then
  {
    printf '\n%s\n' "$MARKER"
    printf 'export PATH="$HOME/.local/bin:$PATH"\n'
  } >>"$PROFILE"
fi

printf 'Installed Airlift at %s\n' "$TARGET"
printf 'Restart Terminal or run: export PATH="$HOME/.local/bin:$PATH"\n'
