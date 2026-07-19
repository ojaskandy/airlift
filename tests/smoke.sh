#!/bin/bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMP_HOME="$(mktemp -d)"
METRICS_DIR="$TEMP_HOME/metrics"
OPEN_LOG="$TEMP_HOME/open.log"
SSH_LOG="$TEMP_HOME/ssh.log"

cleanup() {
  if [ -f "$TEMP_HOME/.airlift/yep-3400.pid" ]; then
    pid="$(cat "$TEMP_HOME/.airlift/yep-3400.pid" 2>/dev/null || true)"
    if [ -n "$pid" ]; then kill "$pid" >/dev/null 2>&1 || true; fi
  fi
  rm -rf "$TEMP_HOME"
}
trap cleanup EXIT

airlift_test() {
  PATH="$ROOT/tests/fakes:$PATH" \
  HOME="$TEMP_HOME" \
  XDG_CONFIG_HOME="$TEMP_HOME/.config" \
  HOSTNAME="test-controller" \
  AIRLIFT_TEST_OPEN_LOG="$OPEN_LOG" \
  AIRLIFT_TEST_SSH_LOG="$SSH_LOG" \
  AIRLIFT_TEST_METRICS_DIR="$METRICS_DIR" \
  "$ROOT/airlift" "$@"
}

bash -n "$ROOT/airlift"
bash -n "$ROOT/install.sh"
chmod +x "$ROOT"/tests/fakes/*

"$ROOT/airlift" --version | grep -F "airlift 0.3.0"
"$ROOT/airlift" --help | grep -F "Airlift"

# shellcheck disable=SC1091
source "$ROOT/airlift"
[ "$(shell_quote "plain")" = "'plain'" ]
[ "$(shell_quote "it's safe")" = "'it'\\''s safe'" ]
[ "$(awk -v busy=2 -v slots=4 -v load=1 -v cores=8 'BEGIN { printf "%.1f", (busy / slots) * 1000 + (load / cores) * 100 }')" = "512.5" ]

mkdir -p "$METRICS_DIR"
airlift_test setup worker@air.local --install none --no-awake >/dev/null 2>&1
ln -sf "$ROOT/tests/fakes/codex" "$TEMP_HOME/.local/bin/codex"
ln -sf "$ROOT/tests/fakes/claude" "$TEMP_HOME/.local/bin/claude"
ln -sf "$ROOT/tests/fakes/yepanywhere" "$TEMP_HOME/.local/bin/yepanywhere"
ln -sf "$ROOT/tests/fakes/git" "$TEMP_HOME/.local/bin/git"

grep -F "Host spare-air" "$TEMP_HOME/.ssh/config" >/dev/null
grep -F "ForwardAgent no" "$TEMP_HOME/.ssh/config" >/dev/null
grep -F "AIRLIFT_CONFIG_VERSION='3'" "$TEMP_HOME/.config/airlift/config" >/dev/null
grep -F "AIRLIFT_DEFAULT_NODE='spare-air'" "$TEMP_HOME/.config/airlift/config" >/dev/null
grep -F "AIRLIFT_ALIAS='spare-air'" "$TEMP_HOME/.config/airlift/nodes/spare-air" >/dev/null
grep -F "AIRLIFT_SLOTS='auto'" "$TEMP_HOME/.config/airlift/nodes/spare-air" >/dev/null
grep -F "Added by Airlift" "$TEMP_HOME/.zprofile" >/dev/null

airlift_test join worker@beefy.tail --alias beefy --slots 8 --transport tailscale --install none --no-awake >/dev/null 2>&1
grep -F "Host beefy" "$TEMP_HOME/.ssh/config" >/dev/null
grep -F "AIRLIFT_SLOTS='8'" "$TEMP_HOME/.config/airlift/nodes/beefy" >/dev/null
grep -F "AIRLIFT_TRANSPORT='tailscale'" "$TEMP_HOME/.config/airlift/nodes/beefy" >/dev/null

mkdir -p "$TEMP_HOME/Developer/Dylan's test project"
printf '2\t2\t0.4\t8\t1\t2\tSpare Air\n' >"$METRICS_DIR/spare-air"
printf '0\t8\t0.2\t24\t1\t0\tBeefy Mac\n' >"$METRICS_DIR/beefy"

POOL_OUTPUT="$(airlift_test nodes)"
printf '%s\n' "$POOL_OUTPUT" | grep -F "spare-air" >/dev/null
printf '%s\n' "$POOL_OUTPUT" | grep -F "beefy" >/dev/null
printf '%s\n' "$POOL_OUTPUT" | grep -F "0/8" >/dev/null
printf '%s\n' "$POOL_OUTPUT" | grep -F "tailscale" >/dev/null

: >"$SSH_LOG"
airlift_test clone git@github.com:example/project.git '~/Developer/cloned' --worker all >/dev/null
grep -F "beefy AIRLIFT_URL=" "$SSH_LOG" >/dev/null
grep -F "spare-air AIRLIFT_URL=" "$SSH_LOG" >/dev/null
grep -F "AIRLIFT_PROJECT='~/Developer/cloned'" "$TEMP_HOME/.config/airlift/config" >/dev/null

airlift_test open "~/Developer/Dylan's test project" >/dev/null
grep -F "http://127.0.0.1:3400/new-session?projectId=" "$OPEN_LOG" >/dev/null
[ -f "$TEMP_HOME/.airlift/yep-3400.pid" ]
grep -F "AIRLIFT_PROJECT='~/Developer/" "$TEMP_HOME/.config/airlift/config" >/dev/null
grep -F -- "-fN -M" "$SSH_LOG" | grep -F "beefy" >/dev/null

RUN_OUTPUT="$(airlift_test run --project "~/Developer/Dylan's test project" "fix the test")"
printf '%s\n' "$RUN_OUTPUT" | grep -F "codex[$TEMP_HOME/Developer/Dylan's test project]: fix the test" >/dev/null

CLAUDE_OUTPUT="$(airlift_test run --agent claude --worker spare-air --project "~/Developer/Dylan's test project" "review this")"
printf '%s\n' "$CLAUDE_OUTPUT" | grep -F "claude[$TEMP_HOME/Developer/Dylan's test project]: review this" >/dev/null

# An otherwise attractive worker is excluded when it does not have the checkout.
printf '0\t8\t0.2\t24\t0\t0\tBeefy Mac\n' >"$METRICS_DIR/beefy"
: >"$SSH_LOG"
airlift_test run --project "~/Developer/Dylan's test project" "route around missing checkout" >/dev/null
grep -F "spare-air AIRLIFT_AGENT=" "$SSH_LOG" >/dev/null

airlift_test stop >/dev/null
airlift_test shutdown --worker beefy >/dev/null

# A v0.2 single-worker config migrates without losing its target or project.
LEGACY_HOME="$TEMP_HOME/legacy"
mkdir -p "$LEGACY_HOME/.config/airlift"
cat >"$LEGACY_HOME/.config/airlift/config" <<'EOF'
AIRLIFT_CONFIG_VERSION='2'
AIRLIFT_ALIAS='old-air'
AIRLIFT_TARGET='worker@old.local'
AIRLIFT_LOCAL_PORT='3401'
AIRLIFT_REMOTE_PORT='3400'
AIRLIFT_PROJECT='~/Developer/legacy'
EOF
PATH="$ROOT/tests/fakes:$PATH" HOME="$LEGACY_HOME" XDG_CONFIG_HOME="$LEGACY_HOME/.config" "$ROOT/airlift" config >/dev/null
grep -F "AIRLIFT_CONFIG_VERSION='3'" "$LEGACY_HOME/.config/airlift/config" >/dev/null
grep -F "AIRLIFT_TARGET='worker@old.local'" "$LEGACY_HOME/.config/airlift/nodes/old-air" >/dev/null

HOME="$TEMP_HOME" "$ROOT/install.sh" >/dev/null
[ -x "$TEMP_HOME/.local/bin/airlift" ]

printf 'smoke tests passed\n'
