#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="${SCRIPT_DIR}/docker-compose.yml"
DROPBOX_REMOTE="${DROPBOX_REMOTE:-dropbox}"
DROPBOX_PATH="${DROPBOX_PATH:-/App_acc/immich}"
MEGA_CRYPT_REMOTE="${MEGA_CRYPT_REMOTE:-mega-crypt}"
IMMICH_REMOTE_ROOT="${IMMICH_REMOTE_ROOT:-/App_acc}"
ALLOW_EMPTY_MIRRORS="${ALLOW_EMPTY_MIRRORS:-false}"
DB_CONTAINER="immich-db"
DB_VOLUME="immich_postgresdata"
FILE_VOLUMES=(immich_library immich_profile immich_upload)
FILE_SUFFIXES=(immich-library immich-profile immich-upload)
TMP_DIR="$(mktemp -d /tmp/immich-restore-XXXXXX)"
CONTAINER_STAGE_DIR=""
STOPPED_BACKUPS=()
RESTORE_COMPLETE=false

info() { echo "[INFO]  $*"; }
warn() { echo "[WARN]  $*"; }
error() { echo "[ERROR] $*" >&2; }

cleanup() {
  local status=$? cleanup_status=0 container
  if [[ -n "${CONTAINER_STAGE_DIR}" ]]; then
    if ! docker exec filedata-backup rm -rf -- "${CONTAINER_STAGE_DIR}"; then
      error "Could not remove container staging directory: ${CONTAINER_STAGE_DIR}"
      cleanup_status=1
    fi
  fi
  if [[ "${RESTORE_COMPLETE}" == true ]]; then
    for container in "${STOPPED_BACKUPS[@]}"; do
      if ! docker start "${container}" >/dev/null; then
        error "Restore succeeded, but ${container} could not be restarted."
        cleanup_status=1
      fi
    done
  elif ((${#STOPPED_BACKUPS[@]})); then
    warn "Backup containers remain stopped; restart them only after recovery is verified: ${STOPPED_BACKUPS[*]}"
  fi
  rm -rf -- "${TMP_DIR}"
  unset PASSPHRASE
  ((status == 0)) || return "${status}"
  return "${cleanup_status}"
}
trap cleanup EXIT

rclone() { docker exec filedata-backup rclone "$@"; }

wait_for_pg_ready() {
  local database="$1" i
  for ((i = 1; i <= 60; i++)); do
    if docker exec "${DB_CONTAINER}" pg_isready -h 127.0.0.1 \
      -U "${DB_USER}" -d "${database}" >/dev/null 2>&1 &&
      docker exec "${DB_CONTAINER}" psql -U "${DB_USER}" -d "${database}" \
        -v ON_ERROR_STOP=1 -Atqc 'SELECT 1' >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  return 1
}

if [[ $# -gt 1 || ( $# -eq 1 && "$1" != --check-only ) ]]; then
  error "Usage: ./restore.sh [--check-only]"
  exit 1
fi
CHECK_ONLY=false
[[ "${1:-}" != --check-only ]] || CHECK_ONLY=true
if [[ "${ALLOW_EMPTY_MIRRORS}" != true && "${ALLOW_EMPTY_MIRRORS}" != false ]]; then
  error "ALLOW_EMPTY_MIRRORS must be true or false."
  exit 1
fi
required_commands=(docker)
if [[ "${CHECK_ONLY}" == false ]]; then
  required_commands+=(gpg zstd)
fi
for cmd in "${required_commands[@]}"; do
  command -v "${cmd}" >/dev/null || { error "Required tool not found: ${cmd}"; exit 1; }
done
docker info >/dev/null 2>&1 || { error "Cannot connect to Docker daemon."; exit 1; }
if [[ "${CHECK_ONLY}" == false ]] && ! docker image inspect homelab/db-backup:local >/dev/null 2>&1; then
  error "Build homelab/db-backup:local before restoring; its PostgreSQL client reads the dump format."
  exit 1
fi
if [[ "$(docker inspect --format '{{.State.Running}}' filedata-backup)" != true ]]; then
  error "filedata-backup must be running with Dropbox and Mega remotes configured."
  exit 1
fi
for remote in "${DROPBOX_REMOTE}" mega "${MEGA_CRYPT_REMOTE}"; do
  if ! rclone lsd "${remote}:" >/dev/null; then
    error "Cannot reach rclone remote '${remote}'."
    exit 1
  fi
done

MIRROR_COUNTS=()
for suffix in "${FILE_SUFFIXES[@]}"; do
  target="${MEGA_CRYPT_REMOTE}:${IMMICH_REMOTE_ROOT%/}/${suffix}/current/"
  if ! size_json="$(rclone size --json "${target}")"; then
    error "Cannot inspect filedata mirror: ${target}"
    exit 1
  fi
  count="$(sed -n 's/.*"count"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' <<<"${size_json}")"
  if [[ -z "${count}" ]]; then
    error "Could not determine mirror object count: ${target}"
    exit 1
  fi
  if [[ "${count}" -eq 0 ]]; then
    if [[ "${ALLOW_EMPTY_MIRRORS}" != true ]]; then
      error "Mirror is empty or missing: ${target}. See the restore guide before overriding."
      exit 1
    fi
    warn "Accepting an empty or missing mirror: ${target}"
  fi
  MIRROR_COUNTS+=("${count}")
  info "Mirror: ${target} (${count} objects)"
done

if ! db_files="$(rclone lsf "${DROPBOX_REMOTE}:${DROPBOX_PATH}" --files-only)"; then
  error "Could not list database backups at ${DROPBOX_REMOTE}:${DROPBOX_PATH}."
  exit 1
fi
LATEST_DB_FILE="$(printf '%s\n' "${db_files}" | \
  { grep -E '^immich_[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}-[0-9]{2}-[0-9]{2}\.sql\.zst\.gpg$' || [[ $? == 1 ]]; } | sort | tail -n 1)"
if [[ -z "${LATEST_DB_FILE}" ]]; then
  error "No timestamped encrypted Immich database dump found at ${DROPBOX_REMOTE}:${DROPBOX_PATH}."
  exit 1
fi
info "Latest database backup: ${LATEST_DB_FILE}"
if [[ "${CHECK_ONLY}" == true ]]; then
  info "Read-only preflight completed; no downloads or volume changes were performed."
  exit 0
fi

if [[ -z "${PASSPHRASE:-}" ]]; then
  read -r -s -p "Enter GPG passphrase: " PASSPHRASE
  echo
fi
[[ -n "${PASSPHRASE}" ]] || { error "Passphrase cannot be empty."; exit 1; }

CONTAINER_STAGE_DIR="$(docker exec filedata-backup mktemp -d /tmp/immich-restore-XXXXXX)"
for i in "${!FILE_VOLUMES[@]}"; do
  target="${MEGA_CRYPT_REMOTE}:${IMMICH_REMOTE_ROOT%/}/${FILE_SUFFIXES[$i]}/current/"
  info "Downloading ${target}..."
  mkdir -p "${TMP_DIR}/${FILE_VOLUMES[$i]}"
  if [[ "${MIRROR_COUNTS[$i]}" -eq 0 ]]; then
    continue
  fi
  docker exec filedata-backup mkdir -p "${CONTAINER_STAGE_DIR}/${FILE_VOLUMES[$i]}"
  rclone copy "${target}" "${CONTAINER_STAGE_DIR}/${FILE_VOLUMES[$i]}/"
  docker cp "filedata-backup:${CONTAINER_STAGE_DIR}/${FILE_VOLUMES[$i]}/." "${TMP_DIR}/${FILE_VOLUMES[$i]}/"
  if [[ "${ALLOW_EMPTY_MIRRORS}" != true ]] && \
    [[ -z "$(find "${TMP_DIR}/${FILE_VOLUMES[$i]}" -type f -print -quit)" ]]; then
    error "Downloaded mirror is empty: ${target}"
    exit 1
  fi
done
docker exec filedata-backup rm -rf -- "${CONTAINER_STAGE_DIR}"
CONTAINER_STAGE_DIR=""
if ! rclone cat "${DROPBOX_REMOTE}:${DROPBOX_PATH}/${LATEST_DB_FILE}" >"${TMP_DIR}/${LATEST_DB_FILE}"; then
  error "Database backup download failed."
  exit 1
fi
[[ -s "${TMP_DIR}/${LATEST_DB_FILE}" ]] || { error "Downloaded database backup is empty."; exit 1; }
if ! gpg --batch --yes --pinentry-mode loopback --passphrase "${PASSPHRASE}" -d "${TMP_DIR}/${LATEST_DB_FILE}" | zstd -t >/dev/null; then
  error "Database backup decryption or integrity check failed."
  exit 1
fi

for volume in "${FILE_VOLUMES[@]}" "${DB_VOLUME}"; do
  if docker volume inspect "${volume}" >/dev/null 2>&1; then
    warn "Restore will replace the contents of the Immich file and database volumes."
    read -r -p "Continue? [y/N] " answer
    if [[ "${answer}" != y && "${answer}" != Y ]]; then
      info "Aborted by operator."
      exit 0
    fi
    break
  fi
done

docker compose -f "${COMPOSE_FILE}" down
for volume in "${FILE_VOLUMES[@]}" "${DB_VOLUME}"; do
  users="$(docker ps -a --filter "volume=${volume}" --format '{{.Names}}')"
  while IFS= read -r user; do
    [[ -z "${user}" || "${user}" == filedata-backup || "${user}" == db-backup ]] || {
      error "Unexpected container '${user}' uses ${volume}; refusing to change it."
      exit 1
    }
  done <<<"${users}"
done
for container in filedata-backup db-backup; do
  if docker inspect "${container}" >/dev/null 2>&1; then
    running="$(docker inspect --format '{{.State.Running}}' "${container}")"
    if [[ "${running}" == true ]]; then
      docker stop "${container}" >/dev/null
      STOPPED_BACKUPS+=("${container}")
    elif [[ "${running}" != false ]]; then
      error "Unexpected running state for ${container}: ${running}"
      exit 1
    fi
  elif [[ "${container}" == filedata-backup ]]; then
    error "filedata-backup disappeared during restore."
    exit 1
  fi
done

for volume in "${FILE_VOLUMES[@]}" "${DB_VOLUME}"; do
  docker volume create "${volume}" >/dev/null
done
for volume in "${FILE_VOLUMES[@]}"; do
  info "Restoring ${volume}..."
  docker run --rm -v "${volume}:/restore" -v "${TMP_DIR}/${volume}:/source:ro" \
    alpine sh -ec 'find /restore -mindepth 1 -delete; cp -a /source/. /restore/'
done
info "Clearing ${DB_VOLUME} while preserving backup container mounts..."
docker run --rm -v "${DB_VOLUME}:/restore" alpine sh -ec 'find /restore -mindepth 1 -delete'
docker compose -f "${COMPOSE_FILE}" create
docker run --rm -v immich_data:/data \
  -v immich_library:/data/library -v immich_profile:/data/profile \
  -v immich_upload:/data/upload alpine sh -ec '
    mkdir -p /data/library /data/profile /data/upload /data/thumbs /data/encoded-video /data/backups
    for dir in library profile upload thumbs encoded-video backups; do
      [ -e "/data/$dir/.immich" ] || touch "/data/$dir/.immich"
    done'
docker start "${DB_CONTAINER}" >/dev/null
DB_USER="$(docker exec "${DB_CONTAINER}" sh -c 'printf "%s" "$POSTGRES_USER"')"
DB_NAME="$(docker exec "${DB_CONTAINER}" sh -c 'printf "%s" "$POSTGRES_DB"')"
[[ -n "${DB_USER}" && -n "${DB_NAME}" ]] || { error "Database runtime user or name is empty."; exit 1; }
if ! wait_for_pg_ready postgres; then
  error "PostgreSQL did not become ready; inspect docker logs ${DB_CONTAINER}."
  exit 1
fi
exists="$(docker exec -i "${DB_CONTAINER}" psql -U "${DB_USER}" -d postgres \
  -v ON_ERROR_STOP=1 --set="restore_db=${DB_NAME}" -Atq <<'SQL'
SELECT 1 FROM pg_database WHERE datname = :'restore_db';
SQL
)"
case "${exists}" in
  1) ;;
  "") docker exec "${DB_CONTAINER}" createdb -U "${DB_USER}" --owner="${DB_USER}" -- "${DB_NAME}" ;;
  *) error "Unexpected database existence check result."; exit 1 ;;
esac
info "Restoring database ${LATEST_DB_FILE}..."
DB_PASSWORD="$(docker exec "${DB_CONTAINER}" sh -c 'printf "%s" "$POSTGRES_PASSWORD"')"
[[ -n "${DB_PASSWORD}" ]] || { error "Database runtime password is empty."; exit 1; }
DB_PASSWORD="${DB_PASSWORD//\\/\\\\}"
DB_PASSWORD="${DB_PASSWORD//:/\\:}"
printf '*:*:*:*:%s\n' "${DB_PASSWORD}" >"${TMP_DIR}/pgpass"
chmod 600 "${TMP_DIR}/pgpass"
unset DB_PASSWORD
gpg --batch --yes --pinentry-mode loopback --passphrase "${PASSPHRASE}" -d "${TMP_DIR}/${LATEST_DB_FILE}" \
  | zstd -d \
  | sed '1,/^\(CREATE\|COPY\) /{/^SET transaction_timeout = 0;$/d}' \
  | sed "s/SELECT pg_catalog.set_config('search_path', '', false);/SELECT pg_catalog.set_config('search_path', 'public, pg_catalog', true);/g" \
  | docker run --rm -i --network media_network \
      -v "${TMP_DIR}/pgpass:/run/pgpass:ro" -e PGPASSFILE=/run/pgpass \
      --entrypoint psql homelab/db-backup:local -h "${DB_CONTAINER}" \
      -U "${DB_USER}" -d "${DB_NAME}" --single-transaction -v ON_ERROR_STOP=1
wait_for_pg_ready "${DB_NAME}" || { error "Restored database is not ready."; exit 1; }
docker compose -f "${COMPOSE_FILE}" up -d
docker compose -f "${COMPOSE_FILE}" ps
RESTORE_COMPLETE=true
info "Immich restore completed from ${LATEST_DB_FILE}."
