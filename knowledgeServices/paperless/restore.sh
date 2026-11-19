#!/usr/bin/env bash

# restore.sh - Restore Paperless filedata from Google Drive and PostgreSQL from Dropbox
# Usage: [DROPBOX_PATH=/Apps/paperless] ./restore.sh [--check-only]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="${SCRIPT_DIR}/docker-compose.yml"
FILEDATA_VOLUME="paperless_filedata"
POSTGRES_VOLUME="paperless_postgresdata"
DB_CONTAINER="paperless-db"
DB_USER="${DB_USER:-paperless}"
DB_NAME="${DB_NAME:-paperless}"
DROPBOX_REMOTE="${DROPBOX_REMOTE:-dropbox}"
DROPBOX_PATH="${DROPBOX_PATH:-/App_acc/paperless}"
GDRIVE_REMOTE="${GDRIVE_REMOTE:-gdrive}"
GDRIVE_CRYPT_REMOTE="${GDRIVE_CRYPT_REMOTE:-gdrive-crypt}"
GDRIVE_CRYPT_PATH="${GDRIVE_CRYPT_PATH:-paperless}"
BACKUP_ENV_FILE="${BACKUP_ENV_FILE:-${SCRIPT_DIR}/../../backupServices/filedata/.env}"
RCLONE_SOURCE="${RCLONE_SOURCE:-container}"
CONTAINER_STAGE_DIR=""
TMP_DIR="$(mktemp -d /tmp/paperless-restore-XXXXXX)"
FILEDATA_LOCAL_DIR="${TMP_DIR}/filedata"
BACKUP_STOPPED=false
RESTORE_COMPLETE=false

cleanup() {
  local exit_status=$?
  local cleanup_status=0
  local backup_running
  if [[ -n "${CONTAINER_STAGE_DIR}" ]]; then
    if ! docker exec filedata-backup rm -rf -- "${CONTAINER_STAGE_DIR}"; then
      error "Could not remove temporary container download: ${CONTAINER_STAGE_DIR}"
      cleanup_status=1
    fi
  fi
  if [[ "${RESTORE_COMPLETE}" == true ]]; then
    if ! backup_running="$(docker inspect --format '{{.State.Running}}' filedata-backup)"; then
      error "Restore succeeded, but filedata-backup status could not be checked."
      cleanup_status=1
    elif [[ "${backup_running}" == false ]]; then
      info "Starting filedata-backup after successful restore..."
      if ! docker start filedata-backup >/dev/null; then
        error "Restore succeeded, but filedata-backup could not be started."
        cleanup_status=1
      elif [[ "$(docker inspect --format '{{.State.Running}}' filedata-backup)" != true ]]; then
        error "Restore succeeded, but filedata-backup is not running after startup."
        cleanup_status=1
      fi
    elif [[ "${backup_running}" != true ]]; then
      error "Restore succeeded, but filedata-backup returned an unexpected running state."
      cleanup_status=1
    fi
  elif [[ "${BACKUP_STOPPED}" == true ]]; then
    warn "filedata-backup remains stopped to avoid backing up an incomplete restore."
    warn "Restart it only after recovery is verified: docker start filedata-backup"
  fi
  rm -rf "${TMP_DIR}"
  unset PASSPHRASE
  if ((exit_status != 0)); then
    return "${exit_status}"
  fi
  return "${cleanup_status}"
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

  users="$(docker ps -a --filter "volume=${volume}" --format '{{.Names}}')"
  if [[ -z "${users}" ]]; then
    return 0
  fi

  local container
  while IFS= read -r container; do
    if [[ "${container}" != "filedata-backup" ]]; then
      error "Unexpected container '${container}' uses ${volume}; refusing to remove it."
      return 1
    fi
  done <<<"${users}"

  if [[ "$(docker inspect --format '{{.State.Running}}' filedata-backup)" == true ]]; then
    info "Stopping filedata-backup during restore, preserving its container..."
    docker stop filedata-backup >/dev/null
    BACKUP_STOPPED=true
  fi
}

wait_for_pg_ready() {
  local database="${1:-postgres}"
  local attempts=60
  local i

  for ((i = 1; i <= attempts; i++)); do
    # The initialization server accepts socket connections before database creation.
    if docker exec "${DB_CONTAINER}" pg_isready -h 127.0.0.1 \
      -U "${DB_USER}" -d "${database}" >/dev/null 2>&1 \
      && docker exec "${DB_CONTAINER}" psql -U "${DB_USER}" \
      -d "${database}" -v ON_ERROR_STOP=1 -Atqc 'SELECT 1' >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done

  return 1
}

ensure_restore_database() {
  local exists

  if ! exists="$(docker exec -i "${DB_CONTAINER}" psql \
    -U "${DB_USER}" -d postgres -v ON_ERROR_STOP=1 \
    --set="restore_db=${DB_NAME}" -Atq <<'SQL'
SELECT 1 FROM pg_database WHERE datname = :'restore_db';
SQL
  )"; then
    error "Failed to check whether restore database '${DB_NAME}' exists."
    return 1
  fi

  case "${exists}" in
    1) return 0 ;;
    "")
      info "Creating missing restore database '${DB_NAME}'..."
      if ! docker exec "${DB_CONTAINER}" createdb \
        -U "${DB_USER}" --owner="${DB_USER}" -- "${DB_NAME}"; then
        error "Failed to create restore database '${DB_NAME}'."
        return 1
      fi
      ;;
    *)
      error "Unexpected database existence check result."
      return 1
      ;;
  esac
}

find_latest_backup() {
  local pattern="$1"
  local files

  if ! files="$(rclone lsf "${DROPBOX_REMOTE}:${DROPBOX_PATH}" --files-only)"; then
    error "Failed to list PostgreSQL backups."
    return 1
  fi
  printf '%s\n' "${files}" | { grep -E "${pattern}" || [[ "$?" == 1 ]]; } | sort | tail -n 1
}

ensure_rclone_remotes() {
  case "${RCLONE_SOURCE}" in
    container)
      if [[ "$(docker inspect --format '{{.State.Running}}' filedata-backup)" != true ]]; then
        error "filedata-backup must be running to download restore data."
        return 1
      fi
      info "Using rclone inside filedata-backup; host configuration and credential files are not read."
      return 0
      ;;
    env) ;;
    *)
      error "RCLONE_SOURCE must be container or env."
      return 1
      ;;
  esac
  local name line value remote
  local assignment='^[[:space:]]*(export[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*=(.*)$'
  local single_quoted="^'([^']*)'[[:space:]]*(#.*)?$"
  local double_quoted='^"([^"]*)"[[:space:]]*(#.*)?$'
  local credentials=(
    DROPBOX_AUTH_TOKEN DROPBOX_REFRESH_TOKEN
    GOOGLE_DRIVE_ACCESS_TOKEN GOOGLE_DRIVE_REFRESH_TOKEN
    GOOGLE_DRIVE_CLIENT_ID GOOGLE_DRIVE_CLIENT_SECRET
    RCLONE_CRYPT_PASSWORD RCLONE_CRYPT_PASSWORD2
  )

  if [[ ! -r "${BACKUP_ENV_FILE}" ]]; then
    error "Backup credential file is not readable: ${BACKUP_ENV_FILE}"
    return 1
  fi

  # Ignore inherited backend overrides as well as the host config.
  for name in "${!RCLONE_CONFIG_@}"; do
    unset "${name}"
  done
  for name in "${credentials[@]}"; do
    unset "${name}"
  done

  # Parse only credential assignments; never execute dotenv contents.
  while IFS= read -r line || [[ -n "${line}" ]]; do
    line="${line%$'\r'}"
    [[ "${line}" =~ ${assignment} ]] || continue
    name="${BASH_REMATCH[2]}"
    value="${BASH_REMATCH[3]}"
    case "${name}" in
      DROPBOX_AUTH_TOKEN|DROPBOX_REFRESH_TOKEN|GOOGLE_DRIVE_ACCESS_TOKEN|\
      GOOGLE_DRIVE_REFRESH_TOKEN|GOOGLE_DRIVE_CLIENT_ID|GOOGLE_DRIVE_CLIENT_SECRET|\
      RCLONE_CRYPT_PASSWORD|RCLONE_CRYPT_PASSWORD2) ;;
      *) continue ;;
    esac
    value="${value#"${value%%[![:space:]]*}"}"
    if [[ "${value}" =~ ${single_quoted} || "${value}" =~ ${double_quoted} ]]; then
      value="${BASH_REMATCH[1]}"
    elif [[ "${value}" == \"* || "${value}" == \'* ]]; then
      error "Invalid quoting for ${name} in backup credential file."
      return 1
    else
      value="${value%%[[:space:]]#*}"
      value="${value%"${value##*[![:space:]]}"}"
    fi
    export "${name}=${value}"
  done <"${BACKUP_ENV_FILE}"

  for name in DROPBOX_AUTH_TOKEN DROPBOX_REFRESH_TOKEN GOOGLE_DRIVE_ACCESS_TOKEN \
    GOOGLE_DRIVE_REFRESH_TOKEN RCLONE_CRYPT_PASSWORD; do
    if [[ -z "${!name:-}" ]]; then
      error "Required backup credential is missing: ${name}"
      return 1
    fi
  done
  for remote in "${DROPBOX_REMOTE}" "${GDRIVE_REMOTE}" "${GDRIVE_CRYPT_REMOTE}"; do
    if [[ ! "${remote}" =~ ^[A-Za-z0-9_-]+$ ]]; then
      error "Restore remote names can contain only letters, digits, underscores and hyphens."
      return 1
    fi
  done
  if [[ "${DROPBOX_REMOTE}" == "${GDRIVE_REMOTE}" || \
        "${DROPBOX_REMOTE}" == "${GDRIVE_CRYPT_REMOTE}" || \
        "${GDRIVE_REMOTE}" == "${GDRIVE_CRYPT_REMOTE}" ]]; then
    error "Restore remote names must be distinct."
    return 1
  fi

  export RCLONE_CONFIG="${TMP_DIR}/rclone.conf"
  export DROPBOX_REMOTE GDRIVE_REMOTE GDRIVE_CRYPT_REMOTE
  info "Creating isolated temporary rclone configuration..."
  MEGA_USER= MEGA_PASS= bash "${SCRIPT_DIR}/../../backupServices/filedata/configure-rclone.sh"

  for name in "${credentials[@]}"; do
    unset "${name}"
  done
}

rclone() {
  if [[ "${RCLONE_SOURCE}" == container ]]; then
    docker exec filedata-backup rclone "$@"
  else
    command rclone --config "${TMP_DIR}/rclone.conf" "$@"
  fi
}

extract_timestamp() {
  local filename="$1"

  sed -n 's/^paperless_\([0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}_[0-9]\{2\}-[0-9]\{2\}-[0-9]\{2\}\)\..*/\1/p' <<<"${filename}"
}

download_backup() {
  local filename="$1"

  echo "[INFO]  Downloading ${filename} to ${TMP_DIR} ..." >&2
  local local_path="${TMP_DIR}/${filename}"
  if ! rclone cat "${DROPBOX_REMOTE}:${DROPBOX_PATH}/${filename}" >"${local_path}"; then
    error "Failed to download PostgreSQL backup: ${filename}"
    return 1
  fi

  if [[ ! -s "${local_path}" ]]; then
    error "Downloaded backup is missing or empty: ${local_path}"
    exit 1
  fi

  printf '%s' "${local_path}"
}

verify_filedata_mirror() {
  local target="${GDRIVE_CRYPT_REMOTE}:${GDRIVE_CRYPT_PATH}/current/"
  local size_json

  if ! size_json="$(rclone size --json "${target}")"; then
    error "Google Drive crypt path is unreachable or unresolvable: ${target}"
    error "This can mean the path does not exist yet, or that the configured crypt"
    error "remote cannot decrypt it (wrong password, or remote misconfigured as a plain"
    error "'drive' remote instead of 'crypt'). Verify the backup credentials and crypt path."
    exit 1
  fi

  local object_count
  object_count="$(sed -n 's/.*"count"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' <<<"${size_json}")"
  if [[ -z "${object_count}" || "${object_count}" -eq 0 ]]; then
    error "Google Drive crypt path resolved but contains no files: ${target}"
    error "Refusing to proceed -- restoring now would recreate an empty paperless_filedata."
    exit 1
  fi

  info "Filedata mirror verified: ${object_count} object(s) at ${target}"
}

sync_filedata_mirror() {
  info "Syncing filedata mirror from ${GDRIVE_CRYPT_REMOTE}:${GDRIVE_CRYPT_PATH}/current/ ..."
  mkdir -p "${FILEDATA_LOCAL_DIR}"
  if [[ "${RCLONE_SOURCE}" == container ]]; then
    CONTAINER_STAGE_DIR="$(docker exec filedata-backup mktemp -d /tmp/paperless-restore-XXXXXX)" || return 1
    if ! rclone copy "${GDRIVE_CRYPT_REMOTE}:${GDRIVE_CRYPT_PATH}/current/" "${CONTAINER_STAGE_DIR}"; then
      error "Failed to download the complete filedata mirror."
      return 1
    fi
    if ! docker cp "filedata-backup:${CONTAINER_STAGE_DIR}/." "${FILEDATA_LOCAL_DIR}/"; then
      error "Failed to copy staged filedata from the backup container."
      return 1
    fi
    docker exec filedata-backup rm -rf -- "${CONTAINER_STAGE_DIR}" || return 1
    CONTAINER_STAGE_DIR=""
  else
    if ! rclone sync "${GDRIVE_CRYPT_REMOTE}:${GDRIVE_CRYPT_PATH}/current/" "${FILEDATA_LOCAL_DIR}"; then
      error "Failed to download the complete filedata mirror."
      return 1
    fi
  fi

  if [[ -z "$(find "${FILEDATA_LOCAL_DIR}" -type f -print -quit)" ]]; then
    error "Synced filedata mirror is empty: ${FILEDATA_LOCAL_DIR}"
    return 1
  fi
}

restore_filedata() {
  docker run --rm \
    -v "${FILEDATA_VOLUME}:/restore" \
    -v "${FILEDATA_LOCAL_DIR}:/source:ro" \
    alpine sh -ec 'find /restore -mindepth 1 -delete; cp -a /source/. /restore/'
}

restore_postgres() {
  local local_backup="$1"

  info "Restoring PostgreSQL dump into ${DB_CONTAINER} ..."
  gpg --batch --yes --passphrase "${PASSPHRASE}" -d "${local_backup}" \
    | zstd -d \
    | docker exec -i "${DB_CONTAINER}" psql \
      -U "${DB_USER}" -d "${DB_NAME}" -v ON_ERROR_STOP=1
}

info "Running preflight checks..."
if [[ $# -gt 1 || ( $# -eq 1 && "$1" != --check-only ) ]]; then
  error "Usage: ./restore.sh [--check-only]"
  exit 1
fi
CHECK_ONLY=false
[[ "${1:-}" != --check-only ]] || CHECK_ONLY=true
REQUIRED_COMMANDS=(docker)
if [[ "${RCLONE_SOURCE}" == env ]]; then
  REQUIRED_COMMANDS+=(rclone)
fi
if [[ "${CHECK_ONLY}" == false ]]; then
  REQUIRED_COMMANDS+=(gpg zstd)
fi
for cmd in "${REQUIRED_COMMANDS[@]}"; do
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    error "Required tool not found: ${cmd}"
    exit 1
  fi
done

if ! docker info >/dev/null 2>&1; then
  error "Cannot connect to Docker daemon."
  exit 1
fi

ensure_rclone_remotes

for remote in "${DROPBOX_REMOTE}" "${GDRIVE_REMOTE}" "${GDRIVE_CRYPT_REMOTE}"; do
  if ! rclone lsd "${remote}:" >/dev/null; then
    error "Cannot reach rclone remote '${remote}'. Verify its configuration and access."
    exit 1
  fi
done

verify_filedata_mirror

info "Preflight checks passed."

if [[ "${CHECK_ONLY}" == true ]]; then
  info "Read-only preflight completed; no downloads or volume changes were performed."
  exit 0
fi

if [[ -z "${PASSPHRASE:-}" ]]; then
  read -r -s -p "Enter GPG passphrase: " PASSPHRASE
  echo
fi

if [[ -z "${PASSPHRASE:-}" ]]; then
  error "Passphrase cannot be empty."
  exit 1
fi

info "Syncing Paperless filedata before volume changes..."
if ! sync_filedata_mirror; then
  error "Filedata mirror sync failed."
  exit 1
fi

info "Looking for the latest Paperless PostgreSQL backup in ${DROPBOX_REMOTE}:${DROPBOX_PATH} ..."
POSTGRES_FILE="$(find_latest_backup '^paperless_.*\.sql\.zst\.gpg$')"

if [[ -z "${POSTGRES_FILE}" ]]; then
  error "No Paperless PostgreSQL backups found at ${DROPBOX_REMOTE}:${DROPBOX_PATH}."
  exit 1
fi

POSTGRES_TIMESTAMP="$(extract_timestamp "${POSTGRES_FILE}")"

info "Latest filedata mirror: ${GDRIVE_CRYPT_REMOTE}:${GDRIVE_CRYPT_PATH}/current/"
info "Latest PostgreSQL backup: ${POSTGRES_FILE}"

POSTGRES_LOCAL_BACKUP="$(download_backup "${POSTGRES_FILE}")"

if docker volume inspect "${FILEDATA_VOLUME}" >/dev/null 2>&1 || docker volume inspect "${POSTGRES_VOLUME}" >/dev/null 2>&1; then
  warn "Paperless restore volumes already exist."
  warn "This restore will replace all files in ${FILEDATA_VOLUME} and recreate ${POSTGRES_VOLUME}."
  warn "filedata-backup will be stopped during recovery, not removed."
  if ! confirm "Replace Paperless filedata and recreate its database volume?"; then
    info "Aborted by operator."
    exit 0
  fi
fi

info "Stopping Paperless stack before restore..."
docker compose -f "${COMPOSE_FILE}" down

stop_volume_users "${FILEDATA_VOLUME}"
stop_volume_users "${POSTGRES_VOLUME}"

for volume in "${POSTGRES_VOLUME}"; do
  if docker volume inspect "${volume}" >/dev/null 2>&1; then
    info "Removing existing volume '${volume}'..."
    docker volume rm "${volume}" >/dev/null
  fi
done

info "Creating volume '${FILEDATA_VOLUME}'..."
docker volume create "${FILEDATA_VOLUME}" >/dev/null

info "Creating volume '${POSTGRES_VOLUME}'..."
docker volume create "${POSTGRES_VOLUME}" >/dev/null

if ! restore_filedata; then
  error "Filedata restore failed."
  docker compose -f "${COMPOSE_FILE}" down
  exit 1
fi

info "Creating Paperless containers..."
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

if ! ensure_restore_database; then
  error "PostgreSQL restore database preparation failed."
  docker compose -f "${COMPOSE_FILE}" down
  exit 1
fi

if ! restore_postgres "${POSTGRES_LOCAL_BACKUP}"; then
  error "PostgreSQL restore failed."
  docker compose -f "${COMPOSE_FILE}" down
  exit 1
fi

info "Verifying PostgreSQL readiness after restore..."
if ! wait_for_pg_ready "${DB_NAME}"; then
  error "PostgreSQL readiness check failed after restore."
  error "Check logs: docker logs ${DB_CONTAINER}"
  docker compose -f "${COMPOSE_FILE}" down
  exit 1
fi

info "Starting full Paperless stack..."
if ! docker compose -f "${COMPOSE_FILE}" up -d; then
  error "Paperless stack failed to start."
  docker compose -f "${COMPOSE_FILE}" down
  exit 1
fi
RESTORE_COMPLETE=true

echo
echo "=========================================="
echo " Paperless restore completed successfully."
echo " Restored filedata mirror: ${GDRIVE_CRYPT_REMOTE}:${GDRIVE_CRYPT_PATH}/current/"
echo " Restored database: ${POSTGRES_FILE}"
echo "=========================================="