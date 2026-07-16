#!/bin/bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMP_HOME="$(mktemp -d)"
trap 'rm -rf "$TEMP_HOME"' EXIT

bash -n "$ROOT/airlift"
bash -n "$ROOT/install.sh"
chmod +x "$ROOT/tests/fakes/ssh"

"$ROOT/airlift" --version | grep -F "airlift "
"$ROOT/airlift" --help | grep -F "Airlift"

# shellcheck disable=SC1091
source "$ROOT/airlift"
[ "$(shell_quote "plain")" = "'plain'" ]
[ "$(shell_quote "it's safe")" = "'it'\\''s safe'" ]

PATH="$ROOT/tests/fakes:$PATH" \
HOME="$TEMP_HOME" \
XDG_CONFIG_HOME="$TEMP_HOME/.config" \
HOSTNAME="test-pro" \
"$ROOT/airlift" setup worker@air.local --install none --no-awake >/dev/null 2>&1

grep -F "Host spare-air" "$TEMP_HOME/.ssh/config" >/dev/null
grep -F "ForwardAgent no" "$TEMP_HOME/.ssh/config" >/dev/null
grep -F "AIRLIFT_ALIAS=spare-air" "$TEMP_HOME/.config/airlift/config" >/dev/null
grep -F "Added by Airlift" "$TEMP_HOME/.zprofile" >/dev/null

HOME="$TEMP_HOME" "$ROOT/install.sh" >/dev/null
[ -x "$TEMP_HOME/.local/bin/airlift" ]

printf 'smoke tests passed\n'
