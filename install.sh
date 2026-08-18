#!/bin/bash

set -euo pipefail

RAW_BASE_URL="${AIRLIFT_RAW_BASE_URL:-https://raw.githubusercontent.com/ojaskandy/airlift/v0.4}"
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

SHARE_DIR="$HOME/.local/share/airlift"
mkdir -p "$SHARE_DIR"
if [ -n "$ROOT" ] && [ -f "$ROOT/dashboard.html" ]; then
  cp "$ROOT/dashboard.html" "$SHARE_DIR/dashboard.html"
else
  command -v curl >/dev/null 2>&1 || {
    printf 'Error: curl is required to download the Airlift dashboard.\n' >&2
    exit 1
  }
  if ! curl -fsSL "$RAW_BASE_URL/dashboard.html" -o "$SHARE_DIR/dashboard.html"; then
    printf 'Error: could not download the Airlift dashboard from GitHub.\n' >&2
    exit 1
  fi
fi
printf 'Pool board: airlift dashboard\n'
printf 'For local CPU temperature and GPU stats, run once: airlift metrics install\n'

install_shim() {
  local agent="$1"
  local shim="$BIN_DIR/$agent"
  rm -f "$shim"
  cat >"$shim" <<EOF
#!/bin/bash
set -euo pipefail
AIRLIFT_BIN="\$HOME/.local/bin/airlift"
CONFIG="\${XDG_CONFIG_HOME:-\$HOME/.config}/airlift/real-binaries"
real=""
if [ -f "\$CONFIG" ]; then
  # shellcheck disable=SC1090
  source "\$CONFIG"
  case "$agent" in
    claude) real="\${AIRLIFT_REAL_CLAUDE:-}" ;;
    codex) real="\${AIRLIFT_REAL_CODEX:-}" ;;
  esac
fi
if [ -n "\${AIRLIFT_IN_EXEC:-}" ]; then
  [ -n "\$real" ] && [ -x "\$real" ] || { printf 'Error: no real %s binary recorded.\\n' "$agent" >&2; exit 1; }
  exec "\$real" "\$@"
fi
exec "\$AIRLIFT_BIN" exec --agent $agent --cwd "\$PWD" -- "\$@"
EOF
  chmod +x "$shim"
}

# Record real binaries before shims hide them.
mkdir -p "${XDG_CONFIG_HOME:-$HOME/.config}/airlift"
REAL_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/airlift/real-binaries"
AIRLIFT_REAL_CLAUDE=""
AIRLIFT_REAL_CODEX=""
if [ -f "$REAL_FILE" ]; then
  # shellcheck disable=SC1090
  source "$REAL_FILE"
fi

find_real_agent() {
  local agent="$1"
  local recorded="$2"
  if [ -n "$recorded" ] && [ -x "$recorded" ] && [ "$recorded" != "$BIN_DIR/$agent" ]; then
    printf '%s' "$recorded"
    return 0
  fi

  local directory candidate
  local old_ifs="$IFS"
  IFS=:
  for directory in $PATH; do
    [ -n "$directory" ] || directory="."
    candidate="$directory/$agent"
    [ "$candidate" != "$BIN_DIR/$agent" ] || continue
    if [ -x "$candidate" ] && [ ! -d "$candidate" ]; then
      IFS="$old_ifs"
      printf '%s' "$candidate"
      return 0
    fi
  done
  IFS="$old_ifs"

  local conductor_dir
  conductor_dir="$HOME/Library/Application Support/com.conductor.app/agent-binaries/$agent"
  if [ -d "$conductor_dir" ]; then
    candidate="$(find "$conductor_dir" -type f -name "$agent" -perm -111 -print 2>/dev/null | sort -V | tail -n 1)"
    if [ -n "$candidate" ] && [ -x "$candidate" ]; then
      printf '%s' "$candidate"
      return 0
    fi
  fi
  return 1
}

claude_real="$(find_real_agent claude "${AIRLIFT_REAL_CLAUDE:-}" || true)"
codex_real="$(find_real_agent codex "${AIRLIFT_REAL_CODEX:-}" || true)"
{
  printf "AIRLIFT_REAL_CLAUDE='%s'\n" "$claude_real"
  printf "AIRLIFT_REAL_CODEX='%s'\n" "$codex_real"
} >"$REAL_FILE"
chmod 600 "$REAL_FILE"
install_shim claude
install_shim codex
printf 'Installed claude/codex shims at %s (they hop via Airlift)\n' "$BIN_DIR"
