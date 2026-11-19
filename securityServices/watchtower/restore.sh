#!/usr/bin/env bash
# restore.sh - Recover Watchtower by redeploying and verifying service health

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="${SCRIPT_DIR}/docker-compose.yml"
SERVICE_NAME="watchtower"

info()  { echo "[INFO]  $*"; }
warn()  { echo "[WARN]  $*"; }
error() { echo "[ERROR] $*" >&2; }

confirm() {
  local prompt="$1"
  local answer
  read -r -p "${prompt} [y/N] " answer
  [[ "${answer}" == "y" || "${answer}" == "Y" ]]
}

info "Running preflight checks..."
if ! command -v docker >/dev/null 2>&1; then
  error "Required tool not found: docker"
  exit 1
fi

if ! docker info >/dev/null 2>&1; then
  error "Cannot connect to Docker daemon."
  exit 1
fi

warn "Watchtower is stateless. This script performs redeploy + verification only."
warn "No backup archive is required and no data restore will be attempted."

if ! confirm "Proceed with stateless recovery for Watchtower?"; then
  info "Aborted by operator."
  exit 0
fi

info "Redeploying Watchtower..."
docker compose -f "${COMPOSE_FILE}" down
docker compose -f "${COMPOSE_FILE}" up -d

if ! docker compose -f "${COMPOSE_FILE}" ps --status running "${SERVICE_NAME}" | grep -q "${SERVICE_NAME}"; then
  error "Watchtower is not running after redeploy."
  exit 1
fi

if docker compose -f "${COMPOSE_FILE}" logs --no-color --tail=80 "${SERVICE_NAME}" | grep -Eiq "Checking all containers|Scheduling first run|Session done"; then
  info "Detected expected startup/scheduling indicators in logs."
else
  warn "No explicit scheduling line detected in recent logs."
  warn "Review full logs with: docker compose logs -f watchtower"
fi

echo
echo "=============================================="
echo " Watchtower recovery completed (redeploy-only)"
echo "=============================================="
