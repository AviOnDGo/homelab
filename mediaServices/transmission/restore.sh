#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="${SCRIPT_DIR}/docker-compose.yml"
VOLUME_NAME="transmission_filedata"
CONTAINER_NAME="transmission"
DROPBOX_REMOTE="${DROPBOX_REMOTE:-dropbox}"
DROPBOX_PATH="${DROPBOX_PATH:-/App_acc/transmission}"
TMP_DIR="$(mktemp -d "/tmp/transmission-restore.XXXXXX")"
BACKUP_CONTAINER_WAS_RUNNING=false

cleanup() {
  if [[ "${BACKUP_CONTAINER_WAS_RUNNING}" == "true" ]]; then
    docker start filedata-backup >/dev/null 2>&1 || true
  fi
  rm -rf "${TMP_DIR}"
  unset PASSPHRASE
}
trap cleanup EXIT

error() { printf '[ERROR] %s\n' "$*" >&2; }

if [[ ! -f "${SCRIPT_DIR}/.env" ]]; then
  error "Create ${SCRIPT_DIR}/.env from .env.example before restoring."
  exit 1
fi

for command_name in docker rclone gpg zstd; do
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    error "Required tool not found: ${command_name}"
    exit 1
  fi
done

for network_name in media_network security_network; do
  if ! docker network inspect "${network_name}" >/dev/null 2>&1; then
    error "Required Docker network ${network_name} does not exist."
    exit 1
  fi
done

if ! rclone lsd "${DROPBOX_REMOTE}:" >/dev/null 2>&1; then
  error "Cannot reach rclone remote '${DROPBOX_REMOTE}'."
  exit 1
fi

if [[ -z "${PASSPHRASE:-}" ]]; then
  read -r -s -p "Enter GPG passphrase: " PASSPHRASE
  printf '\n'
fi
if [[ -z "${PASSPHRASE}" ]]; then
  error "Passphrase cannot be empty."
  exit 1
fi

LATEST_FILE="$(rclone lsf "${DROPBOX_REMOTE}:${DROPBOX_PATH}" --files-only \
  | grep -E '^transmission_[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}-[0-9]{2}-[0-9]{2}\.tar\.zst\.gpg$' \
  | sort | tail -n 1 || true)"
if [[ -z "${LATEST_FILE}" ]]; then
  error "No Transmission backups found at ${DROPBOX_REMOTE}:${DROPBOX_PATH}."
  exit 1
fi

rclone copy "${DROPBOX_REMOTE}:${DROPBOX_PATH}/${LATEST_FILE}" "${TMP_DIR}"
LOCAL_BACKUP="${TMP_DIR}/${LATEST_FILE}"
if [[ ! -s "${LOCAL_BACKUP}" ]]; then
  error "Downloaded backup is missing or empty."
  exit 1
fi

if docker volume inspect "${VOLUME_NAME}" >/dev/null 2>&1; then
  read -r -p "Replace ${VOLUME_NAME} from ${LATEST_FILE}? [y/N] " answer
  if [[ "${answer}" != "y" && "${answer}" != "Y" ]]; then
    printf 'Restore cancelled.\n'
    exit 0
  fi
fi

if [[ "$(docker inspect --format '{{.State.Running}}' filedata-backup 2>/dev/null || true)" == "true" ]]; then
  docker stop filedata-backup >/dev/null
  BACKUP_CONTAINER_WAS_RUNNING=true
fi

docker compose -f "${COMPOSE_FILE}" down
if docker volume inspect "${VOLUME_NAME}" >/dev/null 2>&1; then
  docker volume rm "${VOLUME_NAME}" >/dev/null
fi
docker volume create "${VOLUME_NAME}" >/dev/null

printf '%s\n' "${PASSPHRASE}" \
  | gpg --batch --yes --passphrase-fd 0 -d "${LOCAL_BACKUP}" \
  | zstd -d \
  | docker run --rm -i -v "${VOLUME_NAME}:/restore" alpine \
      sh -c 'cd /restore && tar -xf -'

docker compose -f "${COMPOSE_FILE}" up -d
for attempt in {1..30}; do
  if [[ "$(docker inspect --format '{{.State.Running}}' "${CONTAINER_NAME}" 2>/dev/null || true)" == "true" ]]; then
    printf 'Transmission restore completed from %s.\n' "${LATEST_FILE}"
    exit 0
  fi
  sleep 2
done

error "Transmission did not start; stopping the stack for inspection."
docker compose -f "${COMPOSE_FILE}" down || true
exit 1