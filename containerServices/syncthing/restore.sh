#!/usr/bin/env bash
# restore.sh - Restore Syncthing config from the latest filedata backup
# Usage:
#   [PASSPHRASE=<gpg-passphrase>] \
#   [SYNCTHING_DROPBOX_PATH=/App_acc/syncthing] \
#   ./restore.sh
#
# Optional non-destructive drill mode:
#   SYNCTHING_STATE_VOLUME=syncthing_restore_drill \
#   SYNCTHING_DATA_VOLUME=syncthing_data_restore_drill \
#   SKIP_SERVICE_OPS=1 ./restore.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="${SCRIPT_DIR}/docker-compose.yml"

SERVICE_NAME="syncthing"
DROPBOX_REMOTE="${DROPBOX_REMOTE:-dropbox}"
SYNCTHING_DROPBOX_PATH="${SYNCTHING_DROPBOX_PATH:-/App_acc/syncthing}"

DEFAULT_STATE_VOLUME="syncthing_filedata"
DEFAULT_DATA_VOLUME="syncthing_data"
SYNCTHING_STATE_VOLUME="${SYNCTHING_STATE_VOLUME:-$DEFAULT_STATE_VOLUME}"
SYNCTHING_DATA_VOLUME="${SYNCTHING_DATA_VOLUME:-$DEFAULT_DATA_VOLUME}"

SKIP_SERVICE_OPS="${SKIP_SERVICE_OPS:-0}"
TMP_DIR="$(mktemp -d /tmp/syncthing-restore-XXXXXX)"

cleanup() {
  rm -rf "${TMP_DIR}"
  unset PASSPHRASE
}
trap cleanup EXIT

info()  { echo "[INFO]  $*"; }
warn()  { echo "[WARN]  $*"; }
error() { echo "[ERROR] $*" >&2; }

confirm() {
  local prompt="$1"
  local answer
  read -r -p "${prompt} [y/N] " answer
  [[ "${answer}" == "y" || "${answer}" == "Y" ]]
}

require_tools() {
  for cmd in docker rclone gpg zstd tar; do
    if ! command -v "${cmd}" >/dev/null 2>&1; then
      error "Required tool not found: ${cmd}"
      exit 1
    fi
  done
}

latest_backup() {
  local dropbox_path="$1"
  local pattern="$2"

  rclone lsf "${DROPBOX_REMOTE}:${dropbox_path}" --files-only 2>/dev/null \
    | grep -E "${pattern}" \
    | sort \
    | tail -n 1 \
    || true
}

download_backup() {
  local dropbox_path="$1"
  local filename="$2"
  rclone copy "${DROPBOX_REMOTE}:${dropbox_path}/${filename}" "${TMP_DIR}" --progress
}

volume_exists() {
  local volume="$1"
  docker volume inspect "${volume}" >/dev/null 2>&1
}

create_volume_if_missing() {
  local volume="$1"
  if ! volume_exists "${volume}"; then
    info "Creating volume '${volume}'"
    docker volume create "${volume}" >/dev/null
  fi
}

clear_volume_contents() {
  local volume="$1"
  docker run --rm -v "${volume}:/restore" alpine sh -lc \
    'rm -rf /restore/* /restore/.[!.]* /restore/..?* 2>/dev/null || true'
}

restore_into_volume() {
  local local_backup="$1"
  local volume="$2"

  gpg --batch --yes --passphrase "${PASSPHRASE}" -d "${local_backup}" \
    | zstd -d \
    | docker run --rm -i -v "${volume}:/restore" alpine sh -lc "cd /restore && tar -xf -"
}

chown_volume() {
  local volume="$1"
  docker run --rm -v "${volume}:/data" alpine chown -R 1000:1000 /data
}

require_tools

if ! docker info >/dev/null 2>&1; then
  error "Cannot connect to Docker daemon"
  exit 1
fi

if ! rclone lsd "${DROPBOX_REMOTE}:" >/dev/null 2>&1; then
  error "Cannot reach rclone remote '${DROPBOX_REMOTE}'"
  error "Run 'rclone config' and verify the remote before retrying"
  exit 1
fi

if [[ -z "${PASSPHRASE:-}" ]]; then
  read -r -s -p "Enter GPG passphrase: " PASSPHRASE
  echo
fi

if [[ -z "${PASSPHRASE:-}" ]]; then
  error "Passphrase cannot be empty"
  exit 1
fi

STATE_BACKUP_FILE="$(latest_backup "${SYNCTHING_DROPBOX_PATH}" '^syncthing_.*\.tar\.zst\.gpg$')"
if [[ -z "${STATE_BACKUP_FILE}" ]]; then
  error "No Syncthing backup found at ${DROPBOX_REMOTE}:${SYNCTHING_DROPBOX_PATH}"
  exit 1
fi

info "Latest Syncthing backup: ${STATE_BACKUP_FILE}"

download_backup "${SYNCTHING_DROPBOX_PATH}" "${STATE_BACKUP_FILE}"

LOCAL_STATE_BACKUP="${TMP_DIR}/${STATE_BACKUP_FILE}"

if [[ ! -s "${LOCAL_STATE_BACKUP}" ]]; then
  error "Downloaded backup artifact is missing or empty"
  exit 1
fi

if [[ "${SKIP_SERVICE_OPS}" != "1" ]] && docker ps --filter "name=^${SERVICE_NAME}$" --format '{{.Names}}' | grep -q "^${SERVICE_NAME}$"; then
  warn "This restore is destructive and will stop Syncthing."
  if ! confirm "Stop Syncthing and continue?"; then
    info "Aborted by operator"
    exit 0
  fi
  docker compose -f "${COMPOSE_FILE}" down
fi

STATE_VOLUME_EXISTS=0
if volume_exists "${SYNCTHING_STATE_VOLUME}"; then
  STATE_VOLUME_EXISTS=1
  warn "Existing volume will be cleared before restore: ${SYNCTHING_STATE_VOLUME}"
  if ! confirm "Continue with volume clear and restore?"; then
    info "Aborted by operator"
    exit 0
  fi
fi

create_volume_if_missing "${SYNCTHING_STATE_VOLUME}"
create_volume_if_missing "${SYNCTHING_DATA_VOLUME}"

if [[ "${STATE_VOLUME_EXISTS}" == "1" ]]; then
  clear_volume_contents "${SYNCTHING_STATE_VOLUME}"
fi

info "Restoring Syncthing config volume..."
restore_into_volume "${LOCAL_STATE_BACKUP}" "${SYNCTHING_STATE_VOLUME}"

info "Ensuring Syncthing data volume ownership is 1000:1000..."
chown_volume "${SYNCTHING_DATA_VOLUME}"

if [[ "${SKIP_SERVICE_OPS}" != "1" ]]; then
  info "Starting Syncthing service..."
  docker compose -f "${COMPOSE_FILE}" up -d
fi

STATE_COUNT="$(docker run --rm -v "${SYNCTHING_STATE_VOLUME}:/restore" alpine sh -lc 'find /restore -mindepth 1 | wc -l')"

info "Post-restore object count (${SYNCTHING_STATE_VOLUME}): ${STATE_COUNT}"

echo
echo "=========================================="
echo "Syncthing restore completed successfully"
echo "Config backup: ${STATE_BACKUP_FILE}"
echo "Config volume: ${SYNCTHING_STATE_VOLUME}"
echo "Data volume ownership ensured: ${SYNCTHING_DATA_VOLUME}"
echo "=========================================="
