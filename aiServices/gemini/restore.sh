#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

printf '%s\n' \
  "Gemini CLI is stateless; no service data or Docker volume needs restoring." \
  "The workspace is the host Obsidian vault mounted at /workspace." \
  "The vault path and API key are configured in:" \
  "${SCRIPT_DIR}/.env" \
  "Rebuild the image if needed with:" \
  "  docker compose -f ${SCRIPT_DIR}/docker-compose.yml build gemini"
