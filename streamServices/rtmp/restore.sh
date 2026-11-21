#!/usr/bin/env bash
# restore.sh - Recover RTMP by redeploying and verifying service health

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="${SCRIPT_DIR}/docker-compose.yml"
CONFIG_FILE="${SCRIPT_DIR}/nginx.conf"
SERVICE_NAME="rtmp"

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

if [[ ! -s "${CONFIG_FILE}" ]]; then
  error "Missing local configuration: ${CONFIG_FILE}"
  error "Copy nginx.conf.example to nginx.conf and configure stream keys."
  exit 1
fi

warn "RTMP is stateless. This script performs redeploy + verification only."
warn "No recording data or backup archive is restored."

if ! confirm "Proceed with stateless recovery for RTMP?"; then
  info "Aborted by operator."
  exit 0
fi

info "Redeploying RTMP..."
docker compose -f "${COMPOSE_FILE}" down
docker compose -f "${COMPOSE_FILE}" up -d

if ! docker compose -f "${COMPOSE_FILE}" ps --status running "${SERVICE_NAME}" \
  | grep -q "${SERVICE_NAME}"; then
  error "RTMP is not running after redeploy."
  exit 1
fi

if ! docker compose -f "${COMPOSE_FILE}" logs --no-color --tail=80 \
  "${SERVICE_NAME}" | grep -Eiq "emerg|alert|crit|error"; then
  info "No startup errors detected in recent RTMP logs."
else
  error "RTMP startup errors detected in recent logs."
  exit 1
fi

echo
echo "=============================================="
echo " RTMP recovery completed (redeploy-only)"
echo "=============================================="
