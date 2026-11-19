#!/bin/sh
set -eu

if [ -z "${OPENCODE_SERVER_PASSWORD:-}" ]; then
  echo "OPENCODE_SERVER_PASSWORD must be set before starting OpenCode" >&2
  exit 1
fi

exec opencode "$@"
