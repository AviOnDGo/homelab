#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VOLUME_NAME="omniroute_filedata"
CONTAINER_NAME="omniroute"
BACKUP_CONTAINER_NAME="filedata-backup"
BACKUP_CONTAINER_WAS_RUNNING=0
DROPBOX_REMOTE="dropbox"
DROPBOX_PATH="${DROPBOX_PATH:-/App_acc/omniroute}"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/omniroute-restore.XXXXXX")"

error() {
  echo "[ERROR] $*" >&2
}

cleanup() {
  rm -rf "$TMP_DIR"
  if [[ "$BACKUP_CONTAINER_WAS_RUNNING" == "1" ]]; then
    error "Restore did not complete; ${BACKUP_CONTAINER_NAME} remains stopped. Start it manually after checking the data."
  fi
  unset PASSPHRASE
}
trap cleanup EXIT

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
  error "Cannot reach the rclone remote '${DROPBOX_REMOTE}'"
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

BACKUP_FILES="$(rclone lsf "${DROPBOX_REMOTE}:${DROPBOX_PATH}" --files-only)" || {
  error "Cannot list backups at ${DROPBOX_REMOTE}:${DROPBOX_PATH}"
  exit 1
}
LATEST_FILE="$(
  printf '%s\n' "$BACKUP_FILES" \
    | grep -E '^omniroute_.*\.tar\.zst\.gpg$' \
    | sort \
    | tail -n 1 || true
)"
if [[ -z "$LATEST_FILE" ]]; then
  error "No OmniRoute backup found at ${DROPBOX_REMOTE}:${DROPBOX_PATH}"
  exit 1
fi

echo "Latest backup: ${LATEST_FILE}"
read -r -p "Stop OmniRoute, pause filedata-backup if running, and replace ${VOLUME_NAME}? [y/N] " answer
if [[ "$answer" != "y" && "$answer" != "Y" ]]; then
  echo "Restore cancelled"
  exit 0
fi

if ! docker image inspect alpine >/dev/null 2>&1; then
  docker pull alpine
fi

rclone copy "${DROPBOX_REMOTE}:${DROPBOX_PATH}/${LATEST_FILE}" "$TMP_DIR"
LOCAL_BACKUP="${TMP_DIR}/${LATEST_FILE}"

if docker ps --format '{{.Names}}' | grep -Fxq "$BACKUP_CONTAINER_NAME"; then
  docker stop "$BACKUP_CONTAINER_NAME" >/dev/null
  BACKUP_CONTAINER_WAS_RUNNING=1
fi

docker compose -f "${SCRIPT_DIR}/docker-compose.yml" down

if ! docker volume inspect "$VOLUME_NAME" >/dev/null 2>&1; then
  docker volume create "$VOLUME_NAME" >/dev/null
fi

gpg --batch --yes --passphrase "$PASSPHRASE" -d "$LOCAL_BACKUP" \
  | zstd -d \
  | docker run --rm -i -v "${VOLUME_NAME}:/restore" alpine \
      sh -c 'find /restore -mindepth 1 -maxdepth 1 -exec rm -rf {} \; && cd /restore && tar -xf -'

docker compose -f "${SCRIPT_DIR}/docker-compose.yml" up -d

for attempt in {1..30}; do
  HEALTH_STATUS="$(
    docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' \
      "$CONTAINER_NAME" 2>/dev/null || true
  )"
  if [[ "$HEALTH_STATUS" == "healthy" ]]; then
    if [[ "$BACKUP_CONTAINER_WAS_RUNNING" == "1" ]]; then
      docker start "$BACKUP_CONTAINER_NAME" >/dev/null
      BACKUP_CONTAINER_WAS_RUNNING=0
    fi
    echo "OmniRoute restore completed; container is healthy"
    exit 0
  fi
  if [[ "$HEALTH_STATUS" == "unhealthy" || "$HEALTH_STATUS" == "exited" ]]; then
    error "OmniRoute did not start cleanly (status: ${HEALTH_STATUS})"
    docker logs --tail=100 "$CONTAINER_NAME" >&2 || true
    exit 1
  fi
  sleep 2
done

error "Timed out waiting for OmniRoute healthcheck"
docker logs --tail=100 "$CONTAINER_NAME" >&2 || true
exit 1
