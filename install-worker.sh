#!/bin/bash

set -euo pipefail

RAW_BASE_URL="${AIRLIFT_RAW_BASE_URL:-https://raw.githubusercontent.com/ojaskandy/airlift/v0.4}"
BIN_DIR="$HOME/.local/bin"
TARGET="$BIN_DIR/airlift"
PROFILE="$HOME/.zprofile"
MARKER="# Added by Airlift installer"
DRY_RUN="0"

say() {
  printf '%s\n' "$*"
}

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Airlift worker setup

Usage:
  ./install-worker.sh [--dry-run]

This installs the Airlift CLI for the current user, asks macOS for administrator
approval, enables Remote Login (SSH), ensures the current user is allowed to
log in, and prints the command another Mac should use to join this worker.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run)
      DRY_RUN="1"
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      usage
      die "Unknown option: $1"
      ;;
  esac
done

worker_user() {
  if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
    printf '%s' "$SUDO_USER"
  else
    id -un
  fi
}

install_cli() {
  local source_path="${BASH_SOURCE[0]:-}"
  local local_airlift=""
  local downloaded=""

  case "$source_path" in
    */*)
      local script_dir
      script_dir="$(cd "$(dirname "$source_path")" && pwd)"
      if [ -f "$script_dir/airlift" ]; then
        local_airlift="$script_dir/airlift"
      fi
      ;;
  esac

  if [ -z "$local_airlift" ]; then
    command -v curl >/dev/null 2>&1 || die "curl is required to download the Airlift CLI."
    downloaded="$(mktemp "${TMPDIR:-/tmp}/airlift-cli.XXXXXX")"
    if ! curl -fsSL "$RAW_BASE_URL/airlift" -o "$downloaded"; then
      rm -f "$downloaded"
      die "Could not download Airlift from GitHub."
    fi
    local_airlift="$downloaded"
  fi

  mkdir -p "$BIN_DIR"
  cp "$local_airlift" "$TARGET"
  chmod 755 "$TARGET"
  [ -z "$downloaded" ] || rm -f "$downloaded"

  touch "$PROFILE"
  if ! grep -F "$MARKER" "$PROFILE" >/dev/null 2>&1; then
    {
      printf '\n%s\n' "$MARKER"
      printf 'export PATH="$HOME/.local/bin:$PATH"\n'
    } >>"$PROFILE"
  fi
  export PATH="$BIN_DIR:$PATH"
  say "✓ Installed Airlift at $TARGET"
}

remote_login_failure() {
  local detail="$1"
  say "" >&2
  printf 'macOS did not allow Airlift to enable Remote Login:\n%s\n\n' "$detail" >&2
  say "Enable it manually in:" >&2
  say "  System Settings → General → Sharing → Remote Login" >&2
  say "Then rerun this installer." >&2
  /usr/bin/open "x-apple.systempreferences:com.apple.preferences.sharing" >/dev/null 2>&1 || true
  exit 1
}

enable_remote_login() {
  local user="$1"
  local state output membership

  say ""
  say "macOS will ask for an administrator password to enable Remote Login."
  /usr/bin/sudo -v || die "Administrator approval is required to enable Remote Login."

  if ! state="$(/usr/bin/sudo /usr/sbin/systemsetup -getremotelogin 2>&1)"; then
    remote_login_failure "$state"
  fi

  case "$state" in
    *"On"*|*"on"*)
      say "✓ Remote Login is already enabled."
      ;;
    *)
      if ! output="$(/usr/bin/sudo /usr/sbin/systemsetup -setremotelogin on 2>&1)"; then
        remote_login_failure "$output"
      fi
      if ! state="$(/usr/bin/sudo /usr/sbin/systemsetup -getremotelogin 2>&1)"; then
        remote_login_failure "$state"
      fi
      case "$state" in
        *"On"*|*"on"*) say "✓ Enabled Remote Login." ;;
        *) remote_login_failure "Remote Login did not report as enabled after systemsetup completed." ;;
      esac
      ;;
  esac

  # Preserve the Mac's existing SSH ACL. If it is restricted, add only the
  # account running this installer so Airlift cannot accidentally be locked out.
  if /usr/bin/dscl . -read /Groups/com.apple.access_ssh >/dev/null 2>&1; then
    membership="$(/usr/sbin/dseditgroup -o checkmember -m "$user" com.apple.access_ssh 2>&1 || true)"
    case "$membership" in
      yes*) say "✓ $user is allowed to use Remote Login." ;;
      *)
        /usr/bin/sudo /usr/sbin/dseditgroup -o edit -a "$user" -t user com.apple.access_ssh
        membership="$(/usr/sbin/dseditgroup -o checkmember -m "$user" com.apple.access_ssh 2>&1 || true)"
        case "$membership" in
          yes*) say "✓ Allowed $user to use Remote Login." ;;
          *) die "Remote Login is on, but macOS did not add $user to its SSH access list." ;;
        esac
        ;;
    esac
  fi
}

install_metrics_sampler() {
  if airlift metrics install; then
    say "✓ Temperature and GPU metrics are enabled."
  else
    say "!"
    say "Airlift is installed, but the temperature/GPU sampler did not install."
    say "You can retry later with: airlift metrics install"
  fi
}

print_join_command() {
  local user="$1"
  local host alias
  host="$(/usr/sbin/scutil --get LocalHostName 2>/dev/null || hostname -s)"
  [ -n "$host" ] || host="$(hostname -s)"
  alias="$(printf '%s' "$host" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9._-]/-/g')"

  say ""
  say "Airlift worker is ready."
  say ""
  say "On each controller Mac, run:"
  say "  airlift join ${user}@${host}.local --alias $alias"
  say ""
  say "For different Wi-Fi networks, install Tailscale on both Macs and use"
  say "the worker's MagicDNS name with: --transport tailscale"
  say ""
  say "Remote Login keeps the Mac's existing Allowed users policy. Review it in:"
  say "  System Settings → General → Sharing → Remote Login"
}

main() {
  local user
  [ "$(id -u)" -ne 0 ] || die "Run this installer without sudo; it will ask for administrator approval when needed."
  user="$(worker_user)"

  if [ "$DRY_RUN" = "1" ]; then
    cat <<EOF
Airlift worker dry run

Would install the CLI at:
  $TARGET

Would request administrator approval and run Apple's supported command:
  sudo /usr/sbin/systemsetup -setremotelogin on

Would install the Airlift CPU temperature/GPU sampler:
  airlift metrics install

Would preserve the existing Remote Login ACL and ensure this user is allowed:
  $user
EOF
    return
  fi

  [ "$(uname -s)" = "Darwin" ] || die "Airlift worker setup requires macOS."
  install_cli
  enable_remote_login "$user"
  install_metrics_sampler
  print_join_command "$user"
}

main "$@"
