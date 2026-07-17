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

# Doctor must name the account behind each agent, not just report "ready".
# A mismatch means the cockpit's provider picker would spend someone else's quota.

# The remote scripts prepend ~/.local/bin to PATH, which is where Airlift installs
# the agents. Stage the fakes there so a real codex/claude cannot shadow them.
mkdir -p "$TEMP_HOME/.local/bin"
ln -sf "$ROOT/tests/fakes/codex" "$TEMP_HOME/.local/bin/codex"
ln -sf "$ROOT/tests/fakes/claude" "$TEMP_HOME/.local/bin/claude"

mkdir -p "$TEMP_HOME/.codex"
node -e '
  const fs = require("fs");
  const claims = {
    email: "ojas@example.com",
    "https://api.openai.com/auth": { chatgpt_plan_type: "pro" },
  };
  const payload = Buffer.from(JSON.stringify(claims)).toString("base64url");
  fs.writeFileSync(
    process.argv[1],
    JSON.stringify({
      auth_mode: "chatgpt",
      tokens: { id_token: ["header", payload, "signature"].join(".") },
    })
  );
' "$TEMP_HOME/.codex/auth.json"

DOCTOR_LOG="$TEMP_HOME/doctor.log"
PATH="$ROOT/tests/fakes:$PATH" \
HOME="$TEMP_HOME" \
XDG_CONFIG_HOME="$TEMP_HOME/.config" \
"$ROOT/airlift" doctor >"$DOCTOR_LOG" 2>&1

grep -F "ojas@example.com (pro)" "$DOCTOR_LOG" >/dev/null
grep -F "dylan@example.com (max)" "$DOCTOR_LOG" >/dev/null
grep -F "DIFFERENT accounts" "$DOCTOR_LOG" >/dev/null

# A dead keep-awake must be loud, not silent.
grep -F "Keep-awake: NOT ACTIVE" "$DOCTOR_LOG" >/dev/null
grep -F "sleeps after 1 idle minutes on AC" "$DOCTOR_LOG" >/dev/null

# Low disk headroom must be called out before a clone or build fills the disk.
grep -F "Only 13Gi free" "$DOCTOR_LOG" >/dev/null
grep -F "at least 25Gi" "$DOCTOR_LOG" >/dev/null

HOME="$TEMP_HOME" "$ROOT/install.sh" >/dev/null
[ -x "$TEMP_HOME/.local/bin/airlift" ]

printf 'smoke tests passed\n'
