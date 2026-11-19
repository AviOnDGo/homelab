#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="${SCRIPT_DIR}/docker-compose.yml"
VOLUME_NAME="radarr_filedata"
CONTAINER_NAME="radarr"
DROPBOX_REMOTE="${DROPBOX_REMOTE:-dropbox}"
DROPBOX_PATH="${DROPBOX_PATH:-/App_acc/radarr}"
TMP_DIR="$(mktemp -d "/tmp/radarr-restore.XXXXXX")"

cleanup() {
  rm -rf "${TMP_DIR}"
  unset PASSPHRASE
}
trap cleanup EXIT

info() { echo "[INFO]  $*"; }
error() { echo "[ERROR] $*" >&2; }

confirm() {
  local prompt="$1"
  local answer
  read -r -p "${prompt} [y/N] " answer
  [[ "${answer}" == "y" || "${answer}" == "Y" ]]
}

info "Running preflight checks..."
for command_name in docker rclone gpg zstd; do
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    error "Required tool not found: ${command_name}"
    exit 1
  fi
done

if ! docker info >/dev/null 2>&1; then
  error "Cannot connect to the Docker daemon."
  exit 1
fi

if ! docker network inspect media_network >/dev/null 2>&1; then
  error "Required Docker network media_network does not exist."
  exit 1
fi

if [[ ! -f "${COMPOSE_FILE}" ]]; then
  error "Compose file not found: ${COMPOSE_FILE}"
  exit 1
fi

if ! rclone lsd "${DROPBOX_REMOTE}:" >/dev/null 2>&1; then
  error "Cannot reach rclone remote '${DROPBOX_REMOTE}'."
  exit 1
fi

info "Preflight checks passed."

if [[ -z "${PASSPHRASE:-}" ]]; then
  read -r -s -p "Enter GPG passphrase: " PASSPHRASE
  echo
fi

if [[ -z "${PASSPHRASE}" ]]; then
  error "Passphrase cannot be empty."
  exit 1
fi

info "Searching ${DROPBOX_REMOTE}:${DROPBOX_PATH} for Radarr backups..."
LATEST_FILE="$(rclone lsf "${DROPBOX_REMOTE}:${DROPBOX_PATH}" --files-only 2>/dev/null \
  | grep -E '^radarr_[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}-[0-9]{2}-[0-9]{2}\.tar\.zst\.gpg$' \
  | sort \
  | tail -n 1 \
  || true)"

if [[ -z "${LATEST_FILE}" ]]; then
  error "No Radarr filedata backups found at ${DROPBOX_REMOTE}:${DROPBOX_PATH}."
  exit 1
fi

info "Downloading ${LATEST_FILE}..."
rclone copy "${DROPBOX_REMOTE}:${DROPBOX_PATH}/${LATEST_FILE}" "${TMP_DIR}" --progress
LOCAL_BACKUP="${TMP_DIR}/${LATEST_FILE}"

if [[ ! -s "${LOCAL_BACKUP}" ]]; then
  error "Downloaded backup is missing or empty: ${LOCAL_BACKUP}"
  exit 1
fi

if docker volume inspect "${VOLUME_NAME}" >/dev/null 2>&1; then
  if ! confirm "Stop Radarr and replace ${VOLUME_NAME} from ${LATEST_FILE}?"; then
    info "Restore cancelled."
    exit 0
  fi
else
  info "Volume ${VOLUME_NAME} does not exist; it will be created for restore."
fi

info "Stopping the Radarr stack..."
docker compose -f "${COMPOSE_FILE}" down

if docker volume inspect "${VOLUME_NAME}" >/dev/null 2>&1; then
  info "Removing existing volume ${VOLUME_NAME}..."
  docker volume rm "${VOLUME_NAME}" >/dev/null
fi

info "Creating volume ${VOLUME_NAME}..."
docker volume create "${VOLUME_NAME}" >/dev/null

info "Decrypting and restoring ${LATEST_FILE}..."
printf '%s\n' "${PASSPHRASE}" \
  | gpg --batch --yes --passphrase-fd 0 -d "${LOCAL_BACKUP}" \
  | zstd -d \
  | docker run --rm -i -v "${VOLUME_NAME}:/restore" alpine \
      sh -c 'cd /restore && tar -xf -'

info "Starting Radarr..."
docker compose -f "${COMPOSE_FILE}" up -d

info "Waiting for the Radarr container to run..."
for attempt in {1..30}; do
  if [[ "$(docker inspect --format '{{.State.Running}}' "${CONTAINER_NAME}" 2>/dev/null || true)" == "true" ]]; then
    echo "Radarr config restore completed successfully from ${LATEST_FILE}."
    exit 0
  fi
  sleep 2
done

error "Radarr did not reach the running state. Stopping the stack for inspection."
docker compose -f "${COMPOSE_FILE}" down || true
exit 1