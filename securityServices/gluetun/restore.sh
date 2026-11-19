#!/usr/bin/env bash
# restore.sh - Recover Gluetun by redeploying and verifying service health

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="${SCRIPT_DIR}/docker-compose.yml"
SERVICE_NAME="gluetun"

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

warn "Gluetun is stateless. This script performs redeploy + verification only."
warn "No backup archive is required and no data restore will be attempted."

if ! confirm "Proceed with stateless recovery for Gluetun?"; then
  info "Aborted by operator."
  exit 0
fi

info "Redeploying Gluetun..."
docker compose -f "${COMPOSE_FILE}" down
docker compose -f "${COMPOSE_FILE}" up -d

if ! docker compose -f "${COMPOSE_FILE}" ps --status running "${SERVICE_NAME}" | grep -q "${SERVICE_NAME}"; then
  error "Gluetun is not running after redeploy."
  exit 1
fi

if docker compose -f "${COMPOSE_FILE}" logs --no-color --tail=80 "${SERVICE_NAME}" | grep -Eiq "VPN is up|Initialization complete|healthy"; then
  info "Detected healthy VPN startup indicators in logs."
else
  warn "No explicit VPN-ready log line detected in recent logs."
  warn "Review full logs with: docker compose logs -f gluetun"
fi

echo
echo "=============================================="
echo " Gluetun recovery completed (redeploy-only)"
echo "=============================================="
