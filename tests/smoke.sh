#!/bin/bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMP_HOME="$(mktemp -d)"
METRICS_DIR="$TEMP_HOME/metrics"
OPEN_LOG="$TEMP_HOME/open.log"
SSH_LOG="$TEMP_HOME/ssh.log"
LOCAL_METRICS_FILE="$METRICS_DIR/this-mac"

cleanup() {
  if [ -n "${DASH_PID:-}" ]; then
    kill "$DASH_PID" >/dev/null 2>&1 || true
    wait "$DASH_PID" >/dev/null 2>&1 || true
  fi
  pkill -f "airlift-dash" >/dev/null 2>&1 || true
  if [ -f "$TEMP_HOME/.airlift/yep-3400.pid" ]; then
    pid="$(cat "$TEMP_HOME/.airlift/yep-3400.pid" 2>/dev/null || true)"
    if [ -n "$pid" ]; then kill "$pid" >/dev/null 2>&1 || true; fi
  fi
  rm -rf "$TEMP_HOME"
}
trap cleanup EXIT
trap 'printf "smoke failed at line %s\n" "$LINENO" >&2' ERR

airlift_test() {
  PATH="$ROOT/tests/fakes:$PATH" \
  HOME="$TEMP_HOME" \
  XDG_CONFIG_HOME="$TEMP_HOME/.config" \
  HOSTNAME="test-controller" \
  AIRLIFT_TEST_OPEN_LOG="$OPEN_LOG" \
  AIRLIFT_TEST_SSH_LOG="$SSH_LOG" \
  AIRLIFT_TEST_METRICS_DIR="$METRICS_DIR" \
  AIRLIFT_TEST_LOCAL_METRICS_FILE="$LOCAL_METRICS_FILE" \
  AIRLIFT_TEST_SELF_UUID="controller-uuid" \
  "$ROOT/airlift" "$@"
}

bash -n "$ROOT/airlift"
bash -n "$ROOT/install.sh"
bash -n "$ROOT/install-worker.sh"
bash -n "$ROOT/install-controller.sh"
chmod +x "$ROOT"/tests/fakes/*

WORKER_DRY_RUN="$("$ROOT/install-worker.sh" --dry-run)"
printf '%s\n' "$WORKER_DRY_RUN" | grep -F "systemsetup -setremotelogin on" >/dev/null
printf '%s\n' "$WORKER_DRY_RUN" | grep -F "Would preserve the existing Remote Login ACL" >/dev/null

# Exercise the exact `bash -c "$(curl ...)" -- --dry-run` invocation shape
# without depending on GitHub or changing this test Mac.
WORKER_ONE_COMMAND_DRY_RUN="$(/bin/bash -c "$(< "$ROOT/install-worker.sh")" -- --dry-run)"
printf '%s\n' "$WORKER_ONE_COMMAND_DRY_RUN" | grep -F "systemsetup -setremotelogin on" >/dev/null

WORKER_WRAPPER_DRY_RUN="$("$ROOT/install.sh" --worker --dry-run)"
printf '%s\n' "$WORKER_WRAPPER_DRY_RUN" | grep -F "systemsetup -setremotelogin on" >/dev/null

"$ROOT/airlift" --version | grep -F "airlift 0.4.5"
"$ROOT/airlift" --help | grep -F "Airlift"
"$ROOT/airlift" --help | grep -F "dashboard"
"$ROOT/airlift" --help | grep -F "forget"
[ -f "$ROOT/dashboard.html" ]

# shellcheck disable=SC1091
source "$ROOT/airlift"
[ "$(shell_quote "plain")" = "'plain'" ]
[ "$(shell_quote "it's safe")" = "'it'\\''s safe'" ]
[ "$(awk -v busy=2 -v slots=4 -v load_value=1 -v cores=8 'BEGIN { printf "%.1f", (busy / slots) * 1000 + (load_value / cores) * 100 }')" = "512.5" ]
if rsync_common_excludes | grep -F -- "--exclude=.git" >/dev/null; then
  printf 'push sync should keep .git available on the worker\n' >&2
  exit 1
fi
rsync_pull_excludes | grep -F -- "--exclude=.git" >/dev/null

UNPAIRED_NODES="$(airlift_test nodes)"
printf '%s\n' "$UNPAIRED_NODES" | grep -F "this-mac" >/dev/null
printf '%s\n' "$UNPAIRED_NODES" | grep -F "local" >/dev/null

mkdir -p "$METRICS_DIR" "$TEMP_HOME/.local/bin"
printf '8\t2\t8.0\t8\t1\t0\tTest Controller\t8589934592\t17179869184\t70\tNominal\t10\t100\t200\t1000\tApple Test 8c\t21474836480\t107374182400\t100\tAC Power\t\n' >"$LOCAL_METRICS_FILE"
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
grep -F "AIRLIFT_HARDWARE_UUID='uuid-spare-air'" "$TEMP_HOME/.config/airlift/nodes/spare-air" >/dev/null
grep -F "AIRLIFT_SLOTS='auto'" "$TEMP_HOME/.config/airlift/nodes/spare-air" >/dev/null
grep -F "Added by Airlift" "$TEMP_HOME/.zprofile" >/dev/null

airlift_test join worker@beefy.tail --alias beefy --slots 8 --transport tailscale --install none --no-awake >/dev/null 2>&1
grep -F "Host beefy" "$TEMP_HOME/.ssh/config" >/dev/null
grep -F "AIRLIFT_SLOTS='8'" "$TEMP_HOME/.config/airlift/nodes/beefy" >/dev/null
grep -F "AIRLIFT_TRANSPORT='tailscale'" "$TEMP_HOME/.config/airlift/nodes/beefy" >/dev/null

mkdir -p "$TEMP_HOME/Developer/Dylan's test project"
printf '2\t2\t0.4\t8\t1\t2\tSpare Air\t8589934592\t17179869184\t68\tNominal\t12\t450\t300\t2800\tApple M2 10c\t21474836480\t107374182400\t100\tAC Power\tclaude|1001|512000|claude -p fix\n' >"$METRICS_DIR/spare-air"
printf '0\t8\t0.2\t24\t1\t0\tBeefy Mac\t4294967296\t34359738368\t45\tNominal\t2\t80\t180\t900\tApple M3 Max 40c\t32212254720\t214748364800\t91\tAC Power\t\n' >"$METRICS_DIR/beefy"

POOL_OUTPUT="$(airlift_test nodes)"
printf '%s\n' "$POOL_OUTPUT" | grep -F "spare-air" >/dev/null
printf '%s\n' "$POOL_OUTPUT" | grep -F "beefy" >/dev/null
printf '%s\n' "$POOL_OUTPUT" | grep -F "0/8" >/dev/null
printf '%s\n' "$POOL_OUTPUT" | grep -F "tailscale" >/dev/null
printf '%s\n' "$POOL_OUTPUT" | grep -F "8.0/16G" >/dev/null
printf '%s\n' "$POOL_OUTPUT" | grep -F "68C" >/dev/null
printf '%s\n' "$POOL_OUTPUT" | grep -F "12%/0.5W" >/dev/null
printf '%s\n' "$POOL_OUTPUT" | grep -F "20.0/100G" >/dev/null

POOL_JSON="$(airlift_test nodes --json)"
printf '%s\n' "$POOL_JSON" | python3 -c '
import json, sys
data = json.load(sys.stdin)
ids = {machine["alias"] for machine in data["machines"]}
assert "this-mac" in ids
assert "spare-air" in ids
assert "beefy" in ids
spare = next(machine for machine in data["machines"] if machine["alias"] == "spare-air")
controller = next(machine for machine in data["machines"] if machine["alias"] == "this-mac")
assert float(controller["score"]) > 0
assert spare["mem_total"] == 17179869184
assert spare["cpu_temp_c"] == 68
assert spare["thermal_pressure"] == "Nominal"
assert spare["gpu_active_pct"] == 12
assert spare["gpu_power_mw"] == 450
assert spare["gpu_name"] == "Apple M2 10c"
assert spare["disk_total"] == 107374182400
assert spare["battery_pct"] == 100
assert spare["tasks"][0]["agent"] == "claude"
assert data["version"] == "0.4.5"
'

printf '0\t8\t0.2\t24\t1\t0\tBeefy Mac\t4294967296\t34359738368\t-\t-\t-\t80\t180\t900\tApple M3 Max 40c\t32212254720\t214748364800\t91\tAC Power\t\n' >"$METRICS_DIR/beefy"
POOL_JSON_WITH_MISSING_SENSORS="$(airlift_test nodes --json)"
printf '%s\n' "$POOL_JSON_WITH_MISSING_SENSORS" | python3 -c '
import json, sys
data = json.load(sys.stdin)
beefy = next(machine for machine in data["machines"] if machine["alias"] == "beefy")
assert beefy["cpu_temp_c"] is None
assert beefy["thermal_pressure"] == ""
assert beefy["gpu_active_pct"] is None
assert beefy["gpu_power_mw"] == 80
assert beefy["gpu_freq_mhz"] == 180
assert beefy["cpu_power_mw"] == 900
assert beefy["gpu_name"] == "Apple M3 Max 40c"
assert beefy["disk_total"] == 214748364800
assert beefy["battery_pct"] == 91
assert beefy["power_source"] == "AC Power"
'

DASH_PORT="$((34000 + ($$ % 1000)))"
airlift_test dashboard --port "$DASH_PORT" --no-open >/dev/null 2>&1 &
DASH_PID="$!"
ready="0"
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
  if curl -fsS "http://127.0.0.1:$DASH_PORT/" >/dev/null 2>&1; then
    ready="1"
    break
  fi
  sleep 0.2
done
[ "$ready" = "1" ]
curl -fsS "http://127.0.0.1:$DASH_PORT/" | grep -F "House pool" >/dev/null
curl -fsS "http://127.0.0.1:$DASH_PORT/" | grep -F "Add a Mac" >/dev/null
curl -fsS "http://127.0.0.1:$DASH_PORT/" | grep -F "./install-worker.sh" >/dev/null
curl -fsS "http://127.0.0.1:$DASH_PORT/api/pool" | python3 -c '
import json, sys
data = json.load(sys.stdin)
assert any(machine["alias"] == "this-mac" for machine in data["machines"])
'
kill "$DASH_PID" >/dev/null 2>&1 || true
wait "$DASH_PID" >/dev/null 2>&1 || true
DASH_PID=""

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
grep -F "AIRLIFT_AUTH_DIR=" "$SSH_LOG" | grep -F "AIRLIFT_AGENT='codex'" >/dev/null
grep -F "AIRLIFT_IN_EXEC=1" "$SSH_LOG" >/dev/null

CLAUDE_OUTPUT="$(airlift_test run --agent claude --worker spare-air --project "~/Developer/Dylan's test project" "review this")"
printf '%s\n' "$CLAUDE_OUTPUT" | grep -F "claude[$TEMP_HOME/Developer/Dylan's test project]: review this" >/dev/null

# Automatic routing includes the controller and keeps work local when its score wins.
printf '0\t4\t0\t8\t1\t0\tIdle Controller\t4294967296\t17179869184\t45\tNominal\t2\t80\t180\t900\tApple Test 8c\t21474836480\t107374182400\t100\tAC Power\t\n' >"$LOCAL_METRICS_FILE"
: >"$SSH_LOG"
LOCAL_AUTO="$(airlift_test run --project "~/Developer/Dylan's test project" "use this Mac")"
printf '%s\n' "$LOCAL_AUTO" | grep -F "codex[$TEMP_HOME/Developer/Dylan's test project]: use this Mac" >/dev/null
if grep -F "AIRLIFT_AGENT=" "$SSH_LOG" >/dev/null; then
  printf 'auto routing ignored the lower-scored controller\n' >&2
  exit 1
fi

# A remote score may win only with controller-owned authentication staged.
printf '8\t2\t8.0\t8\t1\t0\tBusy Controller\t8589934592\t17179869184\t70\tNominal\t10\t100\t200\t1000\tApple Test 8c\t21474836480\t107374182400\t100\tAC Power\t\n' >"$LOCAL_METRICS_FILE"
: >"$SSH_LOG"
AUTH_FALLBACK="$(AIRLIFT_TEST_AUTH_MISSING=1 airlift_test run --project "~/Developer/Dylan's test project" "keep my account local")"
printf '%s\n' "$AUTH_FALLBACK" | grep -F "codex[$TEMP_HOME/Developer/Dylan's test project]: keep my account local" >/dev/null
if grep -F "AIRLIFT_AGENT=" "$SSH_LOG" >/dev/null; then
  printf 'auto routing used worker authentication after staging failed\n' >&2
  exit 1
fi
EXPLICIT_AUTH_ERROR="$TEMP_HOME/explicit-auth.stderr"
if AIRLIFT_TEST_AUTH_MISSING=1 airlift_test run --worker beefy --project "~/Developer/Dylan's test project" "do not borrow auth" \
  >/dev/null 2>"$EXPLICIT_AUTH_ERROR"
then
  printf 'explicit worker routing used worker authentication after staging failed\n' >&2
  exit 1
fi
grep -F "Refusing to use beefy's codex account" "$EXPLICIT_AUTH_ERROR" >/dev/null
if grep -F "test-key" "$SSH_LOG" >/dev/null; then
  printf 'controller credential leaked into SSH command arguments\n' >&2
  exit 1
fi
if [ -d "$TEMP_HOME/.airlift/auth" ] && find "$TEMP_HOME/.airlift/auth" -type f -print -quit | grep . >/dev/null; then
  printf 'per-job controller authentication was not cleaned up\n' >&2
  exit 1
fi

printf '0\t8\t0.2\t24\t1\t0\tHot Studio\t33285996544\t34359738368\t96\tSerious\t95\t12000\t1200\t18000\tApple M3 Max 40c\t32212254720\t214748364800\t91\tAC Power\t\n' >"$METRICS_DIR/beefy"
printf '0\t2\t0.2\t8\t1\t0\tCool Spare\t4294967296\t17179869184\t54\tNominal\t4\t100\t200\t1100\tApple M2 10c\t21474836480\t107374182400\t100\tAC Power\t\n' >"$METRICS_DIR/spare-air"
: >"$SSH_LOG"
airlift_test run --project "~/Developer/Dylan's test project" "avoid hot worker" >/dev/null
grep -F "spare-air AIRLIFT_AGENT=" "$SSH_LOG" >/dev/null

# Missing checkout is no longer fatal for run/exec: least-used worker still wins.
printf '0\t8\t0.2\t24\t0\t0\tBeefy Mac\t4294967296\t34359738368\t45\tNominal\t2\t80\t180\t900\tApple M3 Max 40c\t32212254720\t214748364800\t91\tAC Power\t\n' >"$METRICS_DIR/beefy"
: >"$SSH_LOG"
airlift_test run --project "~/Developer/Dylan's test project" "route onto empty worker" >/dev/null
grep -F "beefy AIRLIFT_AGENT=" "$SSH_LOG" >/dev/null

# Offline pool falls back to the local binary.
rm -f "$METRICS_DIR/spare-air" "$METRICS_DIR/beefy"
OFFLINE_STDERR="$TEMP_HOME/offline.stderr"
LOCAL_FALLBACK="$(airlift_test run --project "~/Developer/Dylan's test project" "stay local" 2>"$OFFLINE_STDERR")"
printf '%s\n' "$LOCAL_FALLBACK" | grep -F "codex[$TEMP_HOME/Developer/Dylan's test project]: stay local" >/dev/null
if grep -F "Could not resolve hostname" "$OFFLINE_STDERR" >/dev/null; then
  printf 'offline worker probe leaked an SSH diagnostic\n' >&2
  exit 1
fi

# A bare agent launched from HOME must not sync the controller's entire home folder.
printf '0\t8\t0.2\t24\t1\t0\tBeefy Mac\t4294967296\t34359738368\t45\tNominal\t2\t80\t180\t900\tApple M3 Max 40c\t32212254720\t214748364800\t91\tAC Power\t\n' >"$METRICS_DIR/beefy"
: >"$SSH_LOG"
HOME_EXEC="$(airlift_test exec --agent codex --cwd "$TEMP_HOME" -- --version 2>&1)"
printf '%s\n' "$HOME_EXEC" | grep -F "home folder not synced" >/dev/null
grep -F "beefy AIRLIFT_AGENT=" "$SSH_LOG" >/dev/null

airlift_test stop >/dev/null
airlift_test shutdown --worker beefy >/dev/null

# Retiring a worker removes its generated SSH entry and repairs the default.
airlift_test forget spare-air >/dev/null
[ ! -f "$TEMP_HOME/.config/airlift/nodes/spare-air" ]
if grep -F "Host spare-air" "$TEMP_HOME/.ssh/config" >/dev/null; then
  printf 'forgotten worker remains in SSH config\n' >&2
  exit 1
fi
grep -F "AIRLIFT_DEFAULT_NODE='beefy'" "$TEMP_HOME/.config/airlift/config" >/dev/null

# Forgetting the final worker leaves installed agent shims usable in local mode.
airlift_test forget beefy >/dev/null
grep -F "AIRLIFT_DEFAULT_NODE=''" "$TEMP_HOME/.config/airlift/config" >/dev/null
NO_WORKER_EXEC="$(airlift_test exec --agent codex --cwd "$TEMP_HOME/Developer/Dylan's test project" -- --version 2>&1)"
printf '%s\n' "$NO_WORKER_EXEC" | grep -F "no workers configured" >/dev/null

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

INSTALL_PATH="$TEMP_HOME/.local/bin:$ROOT/tests/fakes:/usr/bin:/bin"
HOME="$TEMP_HOME" PATH="$INSTALL_PATH" "$ROOT/install.sh" >/dev/null
[ -x "$TEMP_HOME/.local/bin/airlift" ]
[ -x "$TEMP_HOME/.local/bin/claude" ]
[ -x "$TEMP_HOME/.local/bin/codex" ]
[ -f "$TEMP_HOME/.local/share/airlift/dashboard.html" ]
grep -F "exec --agent claude" "$TEMP_HOME/.local/bin/claude" >/dev/null
grep -F "AIRLIFT_REAL_CLAUDE='$ROOT/tests/fakes/claude'" "$TEMP_HOME/.config/airlift/real-binaries" >/dev/null
grep -F "AIRLIFT_REAL_CODEX='$ROOT/tests/fakes/codex'" "$TEMP_HOME/.config/airlift/real-binaries" >/dev/null

# Reinstalling while Airlift's shims are first on PATH keeps the real binaries.
HOME="$TEMP_HOME" PATH="$INSTALL_PATH" "$ROOT/install.sh" >/dev/null
grep -F "AIRLIFT_REAL_CLAUDE='$ROOT/tests/fakes/claude'" "$TEMP_HOME/.config/airlift/real-binaries" >/dev/null
grep -F "AIRLIFT_REAL_CODEX='$ROOT/tests/fakes/codex'" "$TEMP_HOME/.config/airlift/real-binaries" >/dev/null

# A controller can reuse its own Conductor-managed agent binary without using a worker's login.
DISCOVERY_HOME="$TEMP_HOME/conductor-discovery"
DISCOVERY_CLAUDE="$DISCOVERY_HOME/Library/Application Support/com.conductor.app/agent-binaries/claude/2.1.201/claude"
mkdir -p "$(dirname "$DISCOVERY_CLAUDE")"
cp "$ROOT/tests/fakes/claude" "$DISCOVERY_CLAUDE"
HOME="$DISCOVERY_HOME" PATH="/usr/bin:/bin" "$ROOT/install.sh" >/dev/null
grep -F "AIRLIFT_REAL_CLAUDE='$DISCOVERY_CLAUDE'" "$DISCOVERY_HOME/.config/airlift/real-binaries" >/dev/null

printf 'smoke tests passed\n'
