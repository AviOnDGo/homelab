#!/usr/bin/env bash
# restore.sh - Restore Pi-hole filedata from latest Dropbox backup

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="${SCRIPT_DIR}/docker-compose.yml"
VOLUME_NAME="pihole_filedata"
CONTAINER_NAME="pihole"
DROPBOX_REMOTE="${DROPBOX_REMOTE:-dropbox}"
DROPBOX_PATH="${DROPBOX_PATH:-/Apps/pihole}"
TMP_DIR="/tmp/pihole-restore-$$"

cleanup() {
  rm -rf "${TMP_DIR}"
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

info "Running preflight checks..."
for cmd in docker rclone gpg zstd; do
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    error "Required tool not found: ${cmd}"
    exit 1
  fi
done

if ! docker info >/dev/null 2>&1; then
  error "Cannot connect to Docker daemon."
  exit 1
fi

docker compose --env-file "${SCRIPT_DIR}/.env" -f "${COMPOSE_FILE}" config --quiet

if ! rclone lsd "${DROPBOX_REMOTE}:" >/dev/null 2>&1; then
  error "Cannot reach rclone remote '${DROPBOX_REMOTE}'."
  exit 1
fi

read -r -s -p "Enter GPG passphrase: " PASSPHRASE
echo

if [[ -z "${PASSPHRASE}" ]]; then
  error "Passphrase cannot be empty."
  exit 1
fi

info "Locating latest backup in ${DROPBOX_REMOTE}:${DROPBOX_PATH} ..."
LATEST_FILE=$(rclone lsf "${DROPBOX_REMOTE}:${DROPBOX_PATH}" --files-only 2>/dev/null \
  | grep -E '\.tar\.zst\.gpg$' \
  | sort \
  | tail -n 1 \
  || true)

if [[ -z "${LATEST_FILE}" ]]; then
  error "No backup files found at ${DROPBOX_REMOTE}:${DROPBOX_PATH}."
  exit 1
fi

mkdir -p "${TMP_DIR}"
info "Downloading latest backup: ${LATEST_FILE}"
rclone copy "${DROPBOX_REMOTE}:${DROPBOX_PATH}/${LATEST_FILE}" "${TMP_DIR}" --progress
LOCAL_BACKUP="${TMP_DIR}/${LATEST_FILE}"

if [[ ! -s "${LOCAL_BACKUP}" ]]; then
  error "Downloaded backup is missing or empty: ${LOCAL_BACKUP}"
  exit 1
fi

if docker volume inspect "${VOLUME_NAME}" >/dev/null 2>&1; then
  warn "Volume '${VOLUME_NAME}' already exists."
  warn "Restoring will overwrite current Pi-hole data."
  if ! confirm "Remove and recreate volume, then restore?"; then
    info "Keeping existing volume. Skipping restore by operator choice."
    info "Starting Pi-hole service..."
    docker compose --env-file "${SCRIPT_DIR}/.env" -f "${COMPOSE_FILE}" up -d
    exit 0
  fi
else
  info "Volume '${VOLUME_NAME}' does not exist. It will be created."
fi

info "Stopping Pi-hole service before restore..."
docker compose --env-file "${SCRIPT_DIR}/.env" -f "${COMPOSE_FILE}" down

if docker volume inspect "${VOLUME_NAME}" >/dev/null 2>&1; then
  info "Removing existing volume '${VOLUME_NAME}'..."
  docker volume rm "${VOLUME_NAME}" >/dev/null
fi

info "Creating volume '${VOLUME_NAME}'..."
docker volume create "${VOLUME_NAME}" >/dev/null

info "Restoring backup into volume '${VOLUME_NAME}' ..."
gpg --batch --yes --passphrase "${PASSPHRASE}" -d "${LOCAL_BACKUP}" \
  | zstd -d \
  | docker run --rm -i -v "${VOLUME_NAME}:/restore" alpine sh -c "cd /restore && tar -xf -"

info "Starting Pi-hole service..."
docker compose --env-file "${SCRIPT_DIR}/.env" -f "${COMPOSE_FILE}" up -d

info "Verifying restored files..."
if ! docker exec "${CONTAINER_NAME}" ls -lh /etc/pihole/gravity.db >/dev/null 2>&1; then
  error "gravity.db not found after restore."
  exit 1
fi

if ! docker exec "${CONTAINER_NAME}" ls -lh /etc/pihole/pihole-FTL.db >/dev/null 2>&1; then
  error "pihole-FTL.db not found after restore."
  exit 1
fi

echo
echo "=============================================="
echo " Pi-hole restore completed successfully"
echo " Restored file: ${LATEST_FILE}"
echo "=============================================="
