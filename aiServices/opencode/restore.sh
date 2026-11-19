#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -gt 0 ]]; then
  echo "OpenCode container data is not persisted; no session archive can be restored." \
    >&2
  echo "Restore the Obsidian vault using its host-level backup procedure." >&2
  exit 1
fi

echo "No OpenCode container data is persisted, so there is nothing to restore."
echo "Restore the Obsidian vault using its host-level backup procedure."
