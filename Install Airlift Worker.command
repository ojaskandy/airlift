#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALLER="$SCRIPT_DIR/install-worker.sh"
DOWNLOADED=""

if [ ! -f "$INSTALLER" ]; then
  DOWNLOADED="$(mktemp "${TMPDIR:-/tmp}/airlift-worker-installer.XXXXXX")"
  if /usr/bin/curl -fsSL \
    "https://raw.githubusercontent.com/ojaskandy/airlift/main/install-worker.sh" \
    -o "$DOWNLOADED"; then
    INSTALLER="$DOWNLOADED"
  else
    printf 'Could not download the Airlift worker installer from GitHub.\n' >&2
    rm -f "$DOWNLOADED"
    printf '\nPress Return to close this window.\n'
    read -r _
    exit 1
  fi
fi

if /bin/bash "$INSTALLER"; then
  status="0"
else
  status="$?"
fi
[ -z "$DOWNLOADED" ] || rm -f "$DOWNLOADED"

printf '\nPress Return to close this window.\n'
read -r _
exit "$status"
