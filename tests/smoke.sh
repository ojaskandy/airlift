#!/bin/bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMP_HOME="$(mktemp -d)"
cleanup() {
  if [ -f "$TEMP_HOME/.airlift/yep-3400.pid" ]; then
    pid="$(cat "$TEMP_HOME/.airlift/yep-3400.pid" 2>/dev/null || true)"
    if [ -n "$pid" ]; then
      kill "$pid" >/dev/null 2>&1 || true
    fi
  fi
  rm -rf "$TEMP_HOME"
}
trap cleanup EXIT

bash -n "$ROOT/airlift"
bash -n "$ROOT/install.sh"
chmod +x "$ROOT"/tests/fakes/*

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
grep -F "AIRLIFT_CONFIG_VERSION='2'" "$TEMP_HOME/.config/airlift/config" >/dev/null
grep -F "AIRLIFT_ALIAS='spare-air'" "$TEMP_HOME/.config/airlift/config" >/dev/null
grep -F "AIRLIFT_LOCAL_PORT='3400'" "$TEMP_HOME/.config/airlift/config" >/dev/null
grep -F "Added by Airlift" "$TEMP_HOME/.zprofile" >/dev/null

mkdir -p "$TEMP_HOME/Developer/Dylan's test project"
OPEN_LOG="$TEMP_HOME/open.log"
PATH="$ROOT/tests/fakes:$PATH" \
HOME="$TEMP_HOME" \
XDG_CONFIG_HOME="$TEMP_HOME/.config" \
AIRLIFT_TEST_OPEN_LOG="$OPEN_LOG" \
"$ROOT/airlift" open "~/Developer/Dylan's test project" >/dev/null

grep -F "http://127.0.0.1:3400/new-session?projectId=" "$OPEN_LOG" >/dev/null
[ -f "$TEMP_HOME/.airlift/yep-3400.pid" ]
grep -F "AIRLIFT_PROJECT='~/Developer/" "$TEMP_HOME/.config/airlift/config" >/dev/null

PATH="$ROOT/tests/fakes:$PATH" \
HOME="$TEMP_HOME" \
XDG_CONFIG_HOME="$TEMP_HOME/.config" \
"$ROOT/airlift" stop >/dev/null

PATH="$ROOT/tests/fakes:$PATH" \
HOME="$TEMP_HOME" \
XDG_CONFIG_HOME="$TEMP_HOME/.config" \
AIRLIFT_TEST_OPEN_LOG="$OPEN_LOG" \
"$ROOT/airlift" open >/dev/null

[ "$(wc -l <"$OPEN_LOG" | tr -d ' ')" = "2" ]

PATH="$ROOT/tests/fakes:$PATH" \
HOME="$TEMP_HOME" \
XDG_CONFIG_HOME="$TEMP_HOME/.config" \
"$ROOT/airlift" shutdown >/dev/null

HOME="$TEMP_HOME" "$ROOT/install.sh" >/dev/null
[ -x "$TEMP_HOME/.local/bin/airlift" ]

printf 'smoke tests passed\n'
