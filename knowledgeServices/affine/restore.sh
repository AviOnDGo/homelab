#!/usr/bin/env bash

# restore.sh - Restore AFFiNE from the latest Dropbox backups
# Usage: [PASSPHRASE=<gpg-passphrase>] [DROPBOX_REMOTE=dropbox] [DROPBOX_PATH=/App_acc/affine] ./restore.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="${SCRIPT_DIR}/docker-compose.yml"
FILEDATA_VOLUME="affine_filedata"
POSTGRES_VOLUME="affine_postgresdata"
DB_CONTAINER="affine-db"
DB_USER="${DB_USER:-affine}"
DB_NAME="${DB_NAME:-affine}"
DROPBOX_REMOTE="${DROPBOX_REMOTE:-dropbox}"
DROPBOX_PATH="${DROPBOX_PATH:-/App_acc/affine}"
TMP_DIR="$(mktemp -d /tmp/affine-restore-XXXXXX)"

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
    if docker exec "${DB_CONTAINER}" pg_isready -U "${DB_USER}" -d "${DB_NAME}" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done

  return 1
}

find_latest_backup() {
  local pattern="$1"

  rclone lsf "${DROPBOX_REMOTE}:${DROPBOX_PATH}" --files-only 2>/dev/null \
    | grep -E "${pattern}" \
    | sort \
    | tail -n 1 \
    || true
}

extract_timestamp() {
  local filename="$1"

  sed -n 's/^affine_\([0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}_[0-9]\{2\}-[0-9]\{2\}-[0-9]\{2\}\)\..*/\1/p' <<<"${filename}"
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

restore_filedata() {
  local local_backup="$1"

  info "Restoring filedata archive into ${FILEDATA_VOLUME} ..."
  gpg --batch --yes --passphrase "${PASSPHRASE}" -d "${local_backup}" \
    | zstd -d \
    | docker run --rm -i -v "${FILEDATA_VOLUME}:/restore" alpine \
        sh -c "cd /restore && tar -xf - --strip-components=1"
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

info "Looking for latest AFFiNE backups in ${DROPBOX_REMOTE}:${DROPBOX_PATH} ..."
FILEDATA_FILE="$(find_latest_backup '^affine_.*\.tar\.zst\.gpg$')"
POSTGRES_FILE="$(find_latest_backup '^affine_.*\.sql\.zst\.gpg$')"

if [[ -z "${FILEDATA_FILE}" ]]; then
  error "No AFFiNE filedata archives found at ${DROPBOX_REMOTE}:${DROPBOX_PATH}."
  exit 1
fi

if [[ -z "${POSTGRES_FILE}" ]]; then
  error "No AFFiNE PostgreSQL backups found at ${DROPBOX_REMOTE}:${DROPBOX_PATH}."
  exit 1
fi

FILEDATA_TIMESTAMP="$(extract_timestamp "${FILEDATA_FILE}")"
POSTGRES_TIMESTAMP="$(extract_timestamp "${POSTGRES_FILE}")"

info "Latest filedata backup: ${FILEDATA_FILE}"
info "Latest PostgreSQL backup: ${POSTGRES_FILE}"

if [[ -n "${FILEDATA_TIMESTAMP}" && -n "${POSTGRES_TIMESTAMP}" && "${FILEDATA_TIMESTAMP}" != "${POSTGRES_TIMESTAMP}" ]]; then
  warn "Selected backups have different timestamps: ${FILEDATA_TIMESTAMP} vs ${POSTGRES_TIMESTAMP}"
fi

FILEDATA_LOCAL_BACKUP="$(download_backup "${FILEDATA_FILE}")"
POSTGRES_LOCAL_BACKUP="$(download_backup "${POSTGRES_FILE}")"

if docker volume inspect "${FILEDATA_VOLUME}" >/dev/null 2>&1 || docker volume inspect "${POSTGRES_VOLUME}" >/dev/null 2>&1; then
  warn "AFFiNE restore volumes already exist."
  warn "This restore will remove and recreate ${FILEDATA_VOLUME} and ${POSTGRES_VOLUME}."
  if ! confirm "Remove and recreate AFFiNE restore volumes before continuing?"; then
    info "Aborted by operator."
    exit 0
  fi
fi

info "Stopping AFFiNE stack before restore..."
docker compose -f "${COMPOSE_FILE}" down

stop_volume_users "${FILEDATA_VOLUME}"
stop_volume_users "${POSTGRES_VOLUME}"

for volume in "${FILEDATA_VOLUME}" "${POSTGRES_VOLUME}"; do
  if docker volume inspect "${volume}" >/dev/null 2>&1; then
    info "Removing existing volume '${volume}'..."
    docker volume rm "${volume}" >/dev/null
  fi
done

info "Creating volume '${FILEDATA_VOLUME}'..."
docker volume create "${FILEDATA_VOLUME}" >/dev/null

info "Creating volume '${POSTGRES_VOLUME}'..."
docker volume create "${POSTGRES_VOLUME}" >/dev/null

if ! restore_filedata "${FILEDATA_LOCAL_BACKUP}"; then
  error "Filedata restore failed."
  docker compose -f "${COMPOSE_FILE}" down
  exit 1
fi

info "Creating AFFiNE containers..."
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

info "Starting full AFFiNE stack..."
if ! docker compose -f "${COMPOSE_FILE}" up -d; then
  error "AFFiNE stack failed to start."
  docker compose -f "${COMPOSE_FILE}" down
  exit 1
fi

echo
echo "=========================================="
echo " AFFiNE restore completed successfully."
echo " Restored filedata: ${FILEDATA_FILE}"
echo " Restored database: ${POSTGRES_FILE}"
echo "=========================================="