#!/usr/bin/env bash
# restore.sh — Restore OpenWebUI data from latest Dropbox backup
# Usage: [PASSPHRASE=<gpg-passphrase>] [DROPBOX_PATH=/Apps/openwebui] ./restore.sh
# Optional drill mode (non-destructive):
#   OPENWEBUI_TARGET_VOLUME=openwebui_restore_drill SKIP_SERVICE_OPS=1 ./restore.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_VOLUME_NAME="openwebui_filedata"
TARGET_VOLUME_NAME="${OPENWEBUI_TARGET_VOLUME:-$DEFAULT_VOLUME_NAME}"
CONTAINER_NAME="openwebui"
DROPBOX_REMOTE="dropbox"
DROPBOX_PATH="${DROPBOX_PATH:-/App_acc/openwebui}"
TMP_DIR="/tmp/openwebui-restore-$$"
SKIP_SERVICE_OPS="${SKIP_SERVICE_OPS:-0}"
SLO_SECONDS=600

RESTORE_START_EPOCH=$(date +%s)
PHASE_START_EPOCH=0

cleanup() {
  rm -rf "$TMP_DIR"
  unset PASSPHRASE
}
trap cleanup EXIT

ts() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

phase_start() {
  local phase="$1"
  PHASE_START_EPOCH=$(date +%s)
  echo "[$(ts)] PHASE START: ${phase}"
}

phase_end() {
  local phase="$1"
  local phase_end_epoch
  phase_end_epoch=$(date +%s)
  local elapsed=$((phase_end_epoch - PHASE_START_EPOCH))
  echo "[$(ts)] PHASE END: ${phase} (elapsed=${elapsed}s)"
}

info()  { echo "[$(ts)] [INFO]  $*"; }
warn()  { echo "[$(ts)] [WARN]  $*"; }
error() { echo "[$(ts)] [ERROR] $*" >&2; }

confirm() {
  local prompt="$1"
  local answer
  read -r -p "$prompt [y/N] " answer
  [[ "$answer" == "y" || "$answer" == "Y" ]]
}

phase_start "preflight"
for cmd in docker rclone gpg zstd tar; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    error "Required tool not found: $cmd"
    exit 1
  fi
done

if ! docker info >/dev/null 2>&1; then
  error "Cannot connect to Docker daemon"
  exit 1
fi

if ! rclone lsd "${DROPBOX_REMOTE}:" >/dev/null 2>&1; then
  error "Cannot reach rclone remote '${DROPBOX_REMOTE}'"
  error "Run: rclone config"
  exit 1
fi
phase_end "preflight"

phase_start "passphrase"
if [[ -z "${PASSPHRASE:-}" ]]; then
  read -r -s -p "Enter GPG passphrase: " PASSPHRASE
  echo
fi

if [[ -z "${PASSPHRASE:-}" ]]; then
  error "Passphrase cannot be empty"
  exit 1
fi
phase_end "passphrase"

phase_start "locate-backup"
LATEST_FILE=$(rclone lsf "${DROPBOX_REMOTE}:${DROPBOX_PATH}" --files-only 2>/dev/null | sort | tail -n 1 || true)
if [[ -z "$LATEST_FILE" ]]; then
  error "No backup files found at ${DROPBOX_REMOTE}:${DROPBOX_PATH}"
  exit 1
fi
info "Latest backup: $LATEST_FILE"
phase_end "locate-backup"

phase_start "download-backup"
mkdir -p "$TMP_DIR"
rclone copy "${DROPBOX_REMOTE}:${DROPBOX_PATH}/${LATEST_FILE}" "$TMP_DIR" --progress
LOCAL_BACKUP="${TMP_DIR}/${LATEST_FILE}"
phase_end "download-backup"

if [[ "$SKIP_SERVICE_OPS" != "1" && "$TARGET_VOLUME_NAME" == "$DEFAULT_VOLUME_NAME" ]]; then
  phase_start "service-stop"
  if docker ps --filter "name=^${CONTAINER_NAME}$" --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    warn "This restore will stop OpenWebUI and overwrite data in '${TARGET_VOLUME_NAME}'."
    if ! confirm "Stop OpenWebUI and continue?"; then
      info "Aborted by operator"
      exit 0
    fi
    docker compose -f "${SCRIPT_DIR}/docker-compose.yml" down
  else
    info "OpenWebUI is not running"
  fi
  phase_end "service-stop"
else
  info "Skipping service stop/start operations (SKIP_SERVICE_OPS=${SKIP_SERVICE_OPS}, target volume=${TARGET_VOLUME_NAME})"
fi

phase_start "prepare-volume"
if docker volume inspect "$TARGET_VOLUME_NAME" >/dev/null 2>&1; then
  warn "Volume '${TARGET_VOLUME_NAME}' exists and will be replaced"
  if ! confirm "Wipe volume '${TARGET_VOLUME_NAME}' and restore from backup?"; then
    info "Aborted by operator"
    exit 0
  fi
  docker volume rm "$TARGET_VOLUME_NAME" >/dev/null
fi

docker volume create "$TARGET_VOLUME_NAME" >/dev/null
phase_end "prepare-volume"

phase_start "decrypt-and-restore"
gpg --batch --yes --passphrase "$PASSPHRASE" -d "$LOCAL_BACKUP" \
  | zstd -d \
  | docker run --rm -i -v "${TARGET_VOLUME_NAME}:/restore" alpine sh -c "cd /restore && tar -xf -"
phase_end "decrypt-and-restore"

if [[ "$SKIP_SERVICE_OPS" != "1" && "$TARGET_VOLUME_NAME" == "$DEFAULT_VOLUME_NAME" ]]; then
  phase_start "service-start"
  docker compose -f "${SCRIPT_DIR}/docker-compose.yml" up -d
  phase_end "service-start"
fi

phase_start "core-verification"
# Verify critical SQLite files exist in target volume.
if ! docker run --rm -v "${TARGET_VOLUME_NAME}:/vol" alpine sh -c 'test -f /vol/webui.db && test -f /vol/webui.db-wal && test -f /vol/webui.db-shm'; then
  error "Core verification failed: required SQLite files missing"
  exit 1
fi

if [[ "$SKIP_SERVICE_OPS" != "1" && "$TARGET_VOLUME_NAME" == "$DEFAULT_VOLUME_NAME" ]]; then
  if ! docker ps --filter "name=^${CONTAINER_NAME}$" --format '{{.Status}}' | grep -qi "healthy\|up"; then
    error "Core verification failed: container is not running/healthy"
    exit 1
  fi
fi
phase_end "core-verification"

TOTAL_ELAPSED=$(( $(date +%s) - RESTORE_START_EPOCH ))
SLO_STATUS="PASS"
if (( TOTAL_ELAPSED > SLO_SECONDS )); then
  SLO_STATUS="FAIL"
fi

echo ""
echo "=========================================="
echo "OpenWebUI restore completed"
echo "Target volume: ${TARGET_VOLUME_NAME}"
echo "Total elapsed: ${TOTAL_ELAPSED}s"
echo "Core-service SLO (<= ${SLO_SECONDS}s): ${SLO_STATUS}"
echo "Note: RAG/vector index readiness is out-of-SLO and may rebuild after restore."
echo "=========================================="
