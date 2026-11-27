#!/usr/bin/env bash
# restore.sh — Restore Hermes data from the latest Dropbox backup
# Usage: ./restore.sh [--if-missing|--force]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="${SCRIPT_DIR}/docker-compose.yml"
VOLUME_NAME="hermes_filedata"
CONTAINER_NAME="hermes"
BACKUP_CONTAINER_NAME="filedata-backup"
DROPBOX_REMOTE="${DROPBOX_REMOTE:-dropbox}"
DROPBOX_PATH="${DROPBOX_PATH:-/App_acc/hermes}"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/hermes-restore.XXXXXX")"
MODE="${1:-}"
BACKUP_WAS_RUNNING=false

# --------------------------------------------------------------------------- #
# Helpers
# --------------------------------------------------------------------------- #
info()  { echo "[INFO]  $*"; }
warn()  { echo "[WARN]  $*"; }
error() { echo "[ERROR] $*" >&2; }

# --------------------------------------------------------------------------- #
# Cleanup trap — runs on any exit (success or failure)
# --------------------------------------------------------------------------- #
cleanup() {
  local status=$?
  rm -rf -- "$TMP_DIR"
  if [[ "$BACKUP_WAS_RUNNING" == "true" ]] \
    && ! docker start "$BACKUP_CONTAINER_NAME" >/dev/null; then
    error "Could not restart ${BACKUP_CONTAINER_NAME}."
    status=1
  fi
  unset PASSPHRASE
  exit "$status"
}
trap cleanup EXIT

if (($# > 1)) || [[ -n "$MODE" && "$MODE" != "--if-missing" && "$MODE" != "--force" ]]; then
  error "Usage: $0 [--if-missing|--force]"
  exit 2
fi

confirm() {
  local prompt="$1"
  local answer

  if [[ "$MODE" == "--force" ]]; then
    return 0
  fi
  if [[ "$MODE" == "--if-missing" ]]; then
    error "Hermes already has data; refusing to restore automatically."
    exit 1
  fi
  if ! read -r -p "$prompt [y/N] " answer; then
    error "Confirmation input unavailable; restore aborted."
    exit 1
  fi
  [[ "$answer" == "y" || "$answer" == "Y" ]]
}

# --------------------------------------------------------------------------- #
# 1. Preflight checks
# --------------------------------------------------------------------------- #
info "Running preflight checks..."
for cmd in docker rclone gpg zstd tar; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    error "Required tool not found: $cmd"
    exit 1
  fi
done

if ! docker info >/dev/null 2>&1; then
  error "Cannot connect to Docker daemon."
  exit 1
fi

if [[ "$MODE" == "--if-missing" ]] \
  && docker volume inspect "$VOLUME_NAME" >/dev/null 2>&1; then
  info "Volume '${VOLUME_NAME}' already exists; skipping automatic restore."
  exit 0
fi

if ! rclone lsd "${DROPBOX_REMOTE}:" >/dev/null 2>&1; then
  error "Cannot reach the '${DROPBOX_REMOTE}' rclone remote."
  error "Configure it with: rclone config"
  exit 1
fi

# --------------------------------------------------------------------------- #
# 2. Acquire GPG passphrase
# --------------------------------------------------------------------------- #
if [[ -z "${PASSPHRASE:-}" ]]; then
  if ! read -r -s -p "Enter GPG passphrase: " PASSPHRASE; then
    echo
    error "Could not read the GPG passphrase."
    exit 1
  fi
  echo
fi

if [[ -z "${PASSPHRASE:-}" ]]; then
  error "Passphrase cannot be empty."
  exit 1
fi
export -n PASSPHRASE

# --------------------------------------------------------------------------- #
# 3. Find latest backup on Dropbox
# --------------------------------------------------------------------------- #
info "Looking for the latest Hermes backup in ${DROPBOX_REMOTE}:${DROPBOX_PATH} ..."
if ! BACKUP_LIST=$(rclone lsf "${DROPBOX_REMOTE}:${DROPBOX_PATH}" --files-only); then
  error "Unable to list backups at ${DROPBOX_REMOTE}:${DROPBOX_PATH}."
  exit 1
fi

LATEST_FILE="$(
  printf '%s\n' "$BACKUP_LIST" \
    | grep -E '^hermes_[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}-[0-9]{2}-[0-9]{2}\.tar\.zst\.gpg$' \
    | LC_ALL=C sort \
    | tail -n 1 || true
)"
if [[ -z "$LATEST_FILE" ]]; then
  error "No Hermes backup files found at ${DROPBOX_REMOTE}:${DROPBOX_PATH}."
  error "Set DROPBOX_PATH if your backups use a different Dropbox directory."
  exit 1
fi
info "Latest backup: ${LATEST_FILE}"

# --------------------------------------------------------------------------- #
# 4. Download and validate latest backup
# --------------------------------------------------------------------------- #
info "Downloading backup to ${TMP_DIR} ..."
rclone copy "${DROPBOX_REMOTE}:${DROPBOX_PATH}/${LATEST_FILE}" "$TMP_DIR" --progress
LOCAL_BACKUP="${TMP_DIR}/${LATEST_FILE}"
if [[ ! -s "$LOCAL_BACKUP" ]]; then
  error "Downloaded backup is missing or empty: ${LOCAL_BACKUP}"
  exit 1
fi

info "Validating backup before changing Hermes..."
gpg --batch --yes --pinentry-mode loopback --passphrase-fd 3 -d "$LOCAL_BACKUP" \
  3<<<"$PASSPHRASE" | zstd -d | tar -tf - >/dev/null

# --------------------------------------------------------------------------- #
# 5. Stop Hermes and pause filedata-backup if running
# --------------------------------------------------------------------------- #
if docker ps -a --filter "name=^${CONTAINER_NAME}$" --format '{{.Names}}' \
  | grep -Fxq "$CONTAINER_NAME"; then
  warn "The '${CONTAINER_NAME}' container exists."
  warn "This restore will stop Hermes and replace all data in '${VOLUME_NAME}'."
  if ! confirm "Stop Hermes and proceed with restore?"; then
    info "Aborted by operator."
    exit 0
  fi
  docker compose -f "$COMPOSE_FILE" down
fi

if docker volume inspect "$VOLUME_NAME" >/dev/null 2>&1; then
  warn "Volume '${VOLUME_NAME}' exists and its contents will be replaced."
  if ! confirm "Wipe volume '${VOLUME_NAME}' and restore from backup?"; then
    info "Aborted by operator."
    exit 0
  fi
fi

# --------------------------------------------------------------------------- #
# 6. Prepare volume
# --------------------------------------------------------------------------- #
if [[ "$(docker inspect -f '{{.State.Running}}' "$BACKUP_CONTAINER_NAME" 2>/dev/null || true)" == "true" ]]; then
  BACKUP_WAS_RUNNING=true
  info "Stopping ${BACKUP_CONTAINER_NAME} while restoring..."
  docker stop "$BACKUP_CONTAINER_NAME" >/dev/null
fi

if docker volume inspect "$VOLUME_NAME" >/dev/null 2>&1; then
  info "Clearing existing volume..."
  docker run --rm -v "${VOLUME_NAME}:/restore" alpine \
    sh -c 'find /restore -mindepth 1 -maxdepth 1 -exec rm -rf {} +'
fi

info "Creating volume '${VOLUME_NAME}'..."
docker volume create "$VOLUME_NAME" >/dev/null

# --------------------------------------------------------------------------- #
# 7. Decrypt and restore
# --------------------------------------------------------------------------- #
info "Restoring backup into '${VOLUME_NAME}'..."
gpg --batch --yes --pinentry-mode loopback --passphrase-fd 3 -d "$LOCAL_BACKUP" \
  3<<<"$PASSPHRASE" \
  | zstd -d \
  | docker run --rm -i -v "${VOLUME_NAME}:/restore" alpine \
      sh -c 'cd /restore && tar -xf -'

# --------------------------------------------------------------------------- #
# 8. Bring up the service
# --------------------------------------------------------------------------- #
info "Starting Hermes..."
docker compose -f "$COMPOSE_FILE" up -d

# --------------------------------------------------------------------------- #
# 9. Verify
# --------------------------------------------------------------------------- #
info "Verifying restored data and container..."
if ! docker run --rm -v "${VOLUME_NAME}:/restore:ro" alpine \
  sh -c 'test -n "$(find /restore -mindepth 1 -maxdepth 1 -print -quit)"'; then
  error "Verification failed: '${VOLUME_NAME}' is empty."
  exit 1
fi

if ! docker ps --filter "name=^${CONTAINER_NAME}$" --format '{{.Names}}' \
  | grep -Fxq "$CONTAINER_NAME"; then
  error "Verification failed: Hermes is not running."
  error "Check logs with: docker logs ${CONTAINER_NAME}"
  exit 1
fi

echo
echo "=========================================="
echo "Hermes restore completed successfully"
echo "Restored backup: ${LATEST_FILE}"
echo "Volume: ${VOLUME_NAME}"
echo "=========================================="
