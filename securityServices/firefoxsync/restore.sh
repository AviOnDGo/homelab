#!/usr/bin/env bash
# restore.sh - Restore Firefox Sync PostgreSQL from latest Dropbox backup

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="${SCRIPT_DIR}/docker-compose.yml"
VOLUME_NAME="firefoxsync_postgresdata"
DB_CONTAINER="firefoxsync-db"
DB_USER="sync"
DB_NAME="firefoxsync"
DROPBOX_REMOTE="${DROPBOX_REMOTE:-dropbox}"
DROPBOX_PATH="${DROPBOX_PATH:-/Apps/firefoxsync}"
TMP_DIR="/tmp/firefoxsync-restore-$$"

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

wait_for_pg_ready() {
  local attempts=60
  local i

  for ((i = 1; i <= attempts; i++)); do
    if docker exec "${DB_CONTAINER}" pg_isready -U "${DB_USER}" -d "${DB_NAME}" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done

  return 1
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
  | grep -E '\.sql\.zst\.gpg$' \
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
  warn "Restoring will destroy current PostgreSQL data."
  if ! confirm "Remove and recreate volume, then restore?"; then
    info "Keeping existing volume. Skipping restore by operator choice."
    info "Starting full Firefox Sync stack..."
    docker compose -f "${COMPOSE_FILE}" up -d
    exit 0
  fi
else
  info "Volume '${VOLUME_NAME}' does not exist. It will be created."
fi

info "Stopping Firefox Sync stack before restore..."
docker compose -f "${COMPOSE_FILE}" down

if docker volume inspect "${VOLUME_NAME}" >/dev/null 2>&1; then
  info "Removing existing volume '${VOLUME_NAME}'..."
  docker volume rm "${VOLUME_NAME}" >/dev/null
fi

info "Creating volume '${VOLUME_NAME}'..."
docker volume create "${VOLUME_NAME}" >/dev/null

info "Creating Firefox Sync containers..."
docker compose -f "${COMPOSE_FILE}" create

info "Starting database container '${DB_CONTAINER}'..."
docker start "${DB_CONTAINER}" >/dev/null

info "Waiting for PostgreSQL readiness..."
if ! wait_for_pg_ready; then
  error "PostgreSQL did not become ready in '${DB_CONTAINER}'."
  error "Stack is intentionally left down for safety."
  exit 1
fi

info "Restoring database from ${LATEST_FILE} ..."
gpg --batch --yes --passphrase "${PASSPHRASE}" -d "${LOCAL_BACKUP}" \
  | zstd -d \
  | docker exec -i "${DB_CONTAINER}" psql -U "${DB_USER}" -d "${DB_NAME}"

info "Verifying PostgreSQL readiness after restore..."
if ! docker exec "${DB_CONTAINER}" pg_isready -U "${DB_USER}" -d "${DB_NAME}" >/dev/null 2>&1; then
  error "Readiness check failed after restore."
  error "Stack is intentionally left down for safety."
  exit 1
fi

info "Starting full Firefox Sync stack..."
docker compose -f "${COMPOSE_FILE}" up -d

echo
echo "=============================================="
echo " Firefox Sync restore completed successfully"
echo " Restored file: ${LATEST_FILE}"
echo "=============================================="
