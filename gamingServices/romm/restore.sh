#!/usr/bin/env bash
# restore.sh - Restore RomM filedata from Filen and PostgreSQL from Dropbox
# Usage: [PASSPHRASE=<gpg-passphrase>] [DROPBOX_PATH=/App_acc/romm] ./restore.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="${SCRIPT_DIR}/docker-compose.yml"
FILEDATA_DIR="${SCRIPT_DIR}/../../backupServices/filedata"
FILEDATA_ENV="${FILEDATA_DIR}/.env"
FILEDATA_COMPOSE="${FILEDATA_DIR}/docker-compose.local.yml"
FILEDATA_IMAGE="homelab/filedata-backup:local"
POSTGRES_VOLUME="romm_postgresdata"
FILEDATA_VOLUME="romm_filedata"
DB_CONTAINER="romm-db"
FILEDATA_CONTAINER="filedata-backup"
DROPBOX_REMOTE="${DROPBOX_REMOTE:-dropbox}"
DROPBOX_PATH="${DROPBOX_PATH:-/App_acc/romm}"
TMP_DIR="$(mktemp -d /tmp/romm-restore-XXXXXX)"

if [[ -f "${SCRIPT_DIR}/.env" ]]; then
  set -a
  source "${SCRIPT_DIR}/.env"
  set +a
fi

DB_USER="${DB_USER:-romm}"
DB_NAME="${DB_NAME:-romm}"

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

stop_volume_users() {
  local volume="$1"
  local users

  users="$(docker ps -aq --filter "volume=${volume}" || true)"
  if [[ -z "${users}" ]]; then
    return 0
  fi

  info "Stopping containers using ${volume}..."
  docker rm -f ${users} >/dev/null
}

wait_for_pg_ready() {
  local attempts=60
  local i

  for ((i = 1; i <= attempts; i++)); do
    # The entrypoint's temporary initialization server accepts only Unix sockets.
    if docker exec "${DB_CONTAINER}" pg_isready \
      -h 127.0.0.1 -U "${DB_USER}" -d postgres >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done

  return 1
}

ensure_database_exists() {
  local database_exists

  if ! database_exists="$(docker exec -i "${DB_CONTAINER}" psql \
    -X \
    -U "${DB_USER}" \
    -d postgres \
    --set=ON_ERROR_STOP=1 \
    --set="db_name=${DB_NAME}" \
    --tuples-only \
    --no-align <<'SQL'
SELECT 1 FROM pg_database WHERE datname = :'db_name';
SQL
  )"; then
    error "Could not check whether database '${DB_NAME}' exists."
    return 1
  fi

  if [[ "${database_exists}" == "1" ]]; then
    return 0
  fi

  info "Database '${DB_NAME}' does not exist; creating it..."
  docker exec "${DB_CONTAINER}" createdb \
    -U "${DB_USER}" \
    --maintenance-db=postgres \
    "${DB_NAME}"
}

find_latest_backup() {
  rclone lsf "${DROPBOX_REMOTE}:${DROPBOX_PATH}" --files-only 2>/dev/null \
    | grep -E '^romm_.*\.sql\.zst\.gpg$' \
    | sort \
    | tail -n 1 \
    || true
}

download_backup() {
  local filename="$1"

  echo "[INFO]  Downloading ${filename} to ${TMP_DIR} ..." >&2
  rclone copy "${DROPBOX_REMOTE}:${DROPBOX_PATH}/${filename}" "${TMP_DIR}"
  local local_path="${TMP_DIR}/${filename}"

  if [[ ! -s "${local_path}" ]]; then
    error "Downloaded backup is missing or empty: ${local_path}"
    exit 1
  fi

  printf '%s' "${local_path}"
}

restore_postgres() {
  local local_backup="$1"

  info "Restoring PostgreSQL dump into ${DB_CONTAINER} ..."
  gpg --batch --yes --passphrase "${PASSPHRASE}" -d "${local_backup}" \
    | zstd -d \
    | docker exec -i "${DB_CONTAINER}" psql -U "${DB_USER}" -d "${DB_NAME}"
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

if [[ ! -f "${FILEDATA_ENV}" ]]; then
  error "Missing ${FILEDATA_ENV}; configure Filen and rclone crypt credentials first."
  exit 1
fi

info "Building and validating the Filen restore image..."
docker build --tag "${FILEDATA_IMAGE}" "${FILEDATA_DIR}"
if ! docker run --rm \
  --env-file "${FILEDATA_ENV}" \
  --entrypoint /bin/bash \
  "${FILEDATA_IMAGE}" -ec '
    /usr/local/bin/configure-rclone.sh
    remote="${ROMM_SYNC_CRYPT_REMOTE:?ROMM_SYNC_CRYPT_REMOTE is required}"
    rclone lsf "${remote%/}/current" >/dev/null
  '; then
  error "Cannot access the configured RomM Filen backup."
  exit 1
fi

if ! rclone lsd "${DROPBOX_REMOTE}:" >/dev/null 2>&1; then
  error "Cannot reach rclone remote '${DROPBOX_REMOTE}'."
  error "Run 'rclone config' and verify the remote before retrying."
  exit 1
fi

info "Preflight checks passed."

if [[ -z "${PASSPHRASE:-}" ]]; then
  read -r -s -p "Enter GPG passphrase: " PASSPHRASE
  echo
fi

if [[ -z "${PASSPHRASE:-}" ]]; then
  error "Passphrase cannot be empty."
  exit 1
fi

info "Looking for latest RomM PostgreSQL backup in ${DROPBOX_REMOTE}:${DROPBOX_PATH} ..."
POSTGRES_FILE="$(find_latest_backup)"

if [[ -z "${POSTGRES_FILE}" ]]; then
  error "No RomM PostgreSQL backups found at ${DROPBOX_REMOTE}:${DROPBOX_PATH}."
  exit 1
fi

info "Latest PostgreSQL backup: ${POSTGRES_FILE}"
POSTGRES_LOCAL_BACKUP="$(download_backup "${POSTGRES_FILE}")"

if docker volume inspect "${FILEDATA_VOLUME}" >/dev/null 2>&1; then
  warn "RomM filedata volume '${FILEDATA_VOLUME}' already exists."
  warn "Filen sync will replace its contents with the latest remote state."
  if ! confirm "Overwrite RomM filedata from Filen before continuing?"; then
    info "Aborted by operator."
    exit 0
  fi
fi

if docker volume inspect "${POSTGRES_VOLUME}" >/dev/null 2>&1; then
  warn "RomM PostgreSQL volume '${POSTGRES_VOLUME}' already exists."
  warn "This restore will remove and recreate ${POSTGRES_VOLUME}."
  if ! confirm "Remove and recreate RomM PostgreSQL data before continuing?"; then
    info "Aborted by operator."
    exit 0
  fi
fi

info "Stopping RomM stack before restore..."
docker compose -f "${COMPOSE_FILE}" down

if docker ps --filter "name=^${FILEDATA_CONTAINER}$" --format '{{.Names}}' \
  | grep -qx "${FILEDATA_CONTAINER}"; then
  info "Stopping ${FILEDATA_CONTAINER} before restoring its source volume..."
  docker stop "${FILEDATA_CONTAINER}" >/dev/null
fi

if ! docker volume inspect "${FILEDATA_VOLUME}" >/dev/null 2>&1; then
  docker volume create "${FILEDATA_VOLUME}" >/dev/null
fi

info "Restoring RomM filedata from Filen..."
if ! docker run --rm \
  --env-file "${FILEDATA_ENV}" \
  --mount "type=volume,source=${FILEDATA_VOLUME},target=/restore" \
  --entrypoint /bin/bash \
  "${FILEDATA_IMAGE}" -ec '
    /usr/local/bin/configure-rclone.sh
    remote="${ROMM_SYNC_CRYPT_REMOTE:?ROMM_SYNC_CRYPT_REMOTE is required}"
    rclone sync "${remote%/}/current/" /restore/ --create-empty-src-dirs --fast-list
  '; then
  error "Filen filedata restore failed."
  exit 1
fi

stop_volume_users "${POSTGRES_VOLUME}"

if docker volume inspect "${POSTGRES_VOLUME}" >/dev/null 2>&1; then
  info "Removing existing volume '${POSTGRES_VOLUME}'..."
  docker volume rm "${POSTGRES_VOLUME}" >/dev/null
fi

info "Creating RomM containers..."
docker compose -f "${COMPOSE_FILE}" create

info "Starting database container '${DB_CONTAINER}'..."
docker start "${DB_CONTAINER}" >/dev/null

info "Waiting for PostgreSQL readiness..."
if ! wait_for_pg_ready; then
  error "PostgreSQL did not become ready in container '${DB_CONTAINER}'."
  error "Check logs: docker logs ${DB_CONTAINER}"
  docker compose -f "${COMPOSE_FILE}" down
  exit 1
fi

if ! ensure_database_exists; then
  error "Could not prepare PostgreSQL database '${DB_NAME}' for restore."
  docker compose -f "${COMPOSE_FILE}" down
  exit 1
fi

if ! restore_postgres "${POSTGRES_LOCAL_BACKUP}"; then
  error "PostgreSQL restore failed."
  docker compose -f "${COMPOSE_FILE}" down
  exit 1
fi

info "Verifying PostgreSQL readiness after restore..."
if ! wait_for_pg_ready; then
  error "PostgreSQL readiness check failed after restore."
  error "Check logs: docker logs ${DB_CONTAINER}"
  docker compose -f "${COMPOSE_FILE}" down
  exit 1
fi

info "Starting full RomM stack..."
if ! docker compose -f "${COMPOSE_FILE}" up -d; then
  error "RomM stack failed to start."
  docker compose -f "${COMPOSE_FILE}" down
  exit 1
fi

info "Starting Local filedata backup service..."
if ! docker compose -f "${FILEDATA_COMPOSE}" up -d "${FILEDATA_CONTAINER}"; then
  error "RomM restored, but ${FILEDATA_CONTAINER} failed to start."
  exit 1
fi

echo
echo "=========================================="
echo " RomM filedata and PostgreSQL restore completed successfully."
echo " Restored database: ${POSTGRES_FILE}"
echo " Restored filedata volume: ${FILEDATA_VOLUME}"
echo "=========================================="
