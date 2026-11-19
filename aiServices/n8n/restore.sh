#!/usr/bin/env bash
# restore.sh - Restore n8n SQLite data from the latest filedata backup
# Usage: [PASSPHRASE=<gpg-passphrase>] [DROPBOX_PATH=/Apps/n8n] ./restore.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="${SCRIPT_DIR}/docker-compose.yml"
VOLUME_NAME="n8n_filedata"
CONTAINER_NAME="n8n"
DROPBOX_REMOTE="${DROPBOX_REMOTE:-dropbox}"
DROPBOX_PATH="${DROPBOX_PATH:-/App_acc/n8n}"
TMP_DIR="$(mktemp -d /tmp/n8n-restore-XXXXXX)"

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

for cmd in docker rclone gpg zstd; do
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    error "Required tool not found: ${cmd}"
    exit 1
  fi
done

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

if [[ -z "${PASSPHRASE}" ]]; then
  error "Passphrase cannot be empty"
  exit 1
fi

info "Looking for the latest n8n backup in ${DROPBOX_REMOTE}:${DROPBOX_PATH} ..."
LATEST_FILE="$(
  rclone lsf "${DROPBOX_REMOTE}:${DROPBOX_PATH}" --files-only 2>/dev/null \
    | grep -E '^n8n_.*\.tar\.zst\.gpg$' \
    | sort \
    | tail -n 1 \
    || true
)"

if [[ -z "${LATEST_FILE}" ]]; then
  error "No n8n filedata backups found at ${DROPBOX_REMOTE}:${DROPBOX_PATH}"
  error "Expected a file matching n8n_*.tar.zst.gpg"
  exit 1
fi

info "Latest backup: ${LATEST_FILE}"
rclone copy "${DROPBOX_REMOTE}:${DROPBOX_PATH}/${LATEST_FILE}" "${TMP_DIR}" --progress
LOCAL_BACKUP="${TMP_DIR}/${LATEST_FILE}"

if [[ ! -s "${LOCAL_BACKUP}" ]]; then
  error "Downloaded backup is missing or empty: ${LOCAL_BACKUP}"
  exit 1
fi

if docker ps --filter "name=^${CONTAINER_NAME}$" --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
  warn "This restore will stop n8n and replace data in '${VOLUME_NAME}'"
  if ! confirm "Stop n8n and continue?"; then
    info "Aborted by operator"
    exit 0
  fi
  docker compose -f "${COMPOSE_FILE}" down
else
  info "n8n is not running"
fi

if docker volume inspect "${VOLUME_NAME}" >/dev/null 2>&1; then
  warn "Volume '${VOLUME_NAME}' exists and will be replaced"
  if ! confirm "Wipe '${VOLUME_NAME}' and restore from backup?"; then
    info "Aborted by operator"
    exit 0
  fi
  docker volume rm "${VOLUME_NAME}" >/dev/null
fi

docker volume create "${VOLUME_NAME}" >/dev/null

info "Decrypting and restoring ${LATEST_FILE} ..."
gpg --batch --yes --passphrase "${PASSPHRASE}" -d "${LOCAL_BACKUP}" \
  | zstd -d \
  | docker run --rm -i -v "${VOLUME_NAME}:/restore" alpine sh -c "cd /restore && tar -xf -"

info "Starting n8n ..."
docker compose -f "${COMPOSE_FILE}" up -d

info "Verifying restored SQLite database ..."
if ! docker run --rm -v "${VOLUME_NAME}:/restore" alpine sh -c 'test -s /restore/database.sqlite'; then
  error "Verification failed: /restore/database.sqlite is missing or empty"
  exit 1
fi

if ! docker ps --filter "name=^${CONTAINER_NAME}$" --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
  error "Verification failed: n8n is not running"
  exit 1
fi

echo
echo "=========================================="
echo "n8n restore completed successfully"
echo "Restored backup: ${LATEST_FILE}"
echo "Volume: ${VOLUME_NAME}"
echo "=========================================="
