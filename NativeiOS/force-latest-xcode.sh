#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "== HALO FORCE LATEST XCODE =="
echo "This closes Xcode first so it cannot keep an older generated project in memory."

if pgrep -x Xcode >/dev/null 2>&1; then
  osascript -e 'tell application "Xcode" to quit' >/dev/null 2>&1 || true

  for _ in {1..20}; do
    if ! pgrep -x Xcode >/dev/null 2>&1; then
      break
    fi
    sleep 1
  done

  if pgrep -x Xcode >/dev/null 2>&1; then
    echo "ERROR: Xcode is still open, likely because it is waiting for you to save/discard a local editor change."
    echo "Resolve that Xcode prompt, quit Xcode completely, then rerun this command."
    exit 2
  fi
fi

exec bash "$SCRIPT_DIR/run-fresh-simulator.sh"
