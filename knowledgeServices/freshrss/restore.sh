#!/usr/bin/env bash
# restore.sh — Restore FreshRSS from the latest Dropbox backup
# Usage: ./restore.sh [--if-missing|--force]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VOLUME_NAME="freshrss_filedata"
CONTAINER_NAME="freshrss"
DROPBOX_REMOTE="dropbox"
DROPBOX_PATH="${DROPBOX_PATH:-/Apps/freshrss}"
TMP_DIR="/tmp/freshrss-restore-$$"
MODE="${1:-}"
BACKUP_WAS_RUNNING=false

# --------------------------------------------------------------------------- #
# Cleanup trap — runs on any exit (success or failure)
# --------------------------------------------------------------------------- #
cleanup() {
  local status=$?
  if [[ "$BACKUP_WAS_RUNNING" == "true" ]] && ! docker start filedata-backup >/dev/null; then
    echo "[ERROR] Could not restart filedata-backup." >&2
    status=1
  fi
  rm -rf "$TMP_DIR"
  unset PASSPHRASE
  exit "$status"
}
trap cleanup EXIT

# --------------------------------------------------------------------------- #
# Helpers
# --------------------------------------------------------------------------- #
info()  { echo "[INFO]  $*"; }
warn()  { echo "[WARN]  $*"; }
error() { echo "[ERROR] $*" >&2; }

confirm() {
  local prompt="$1"
  local answer
  if [[ "$MODE" == "--force" ]]; then
    return 0
  fi
  if [[ "$MODE" == "--if-missing" ]]; then
    error "FreshRSS is running; refusing to restore automatically."
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
  if ! command -v "$cmd" &>/dev/null; then
    error "Required tool not found: $cmd"
    error "Install $cmd and re-run this script."
    exit 1
  fi
done

if ! docker info &>/dev/null; then
  error "Cannot connect to Docker daemon."
  error "Ensure Docker is running and your user has access to the Docker socket."
  exit 1
fi

if [[ "$MODE" == "--if-missing" ]] && docker volume inspect "$VOLUME_NAME" &>/dev/null; then
  info "Volume '$VOLUME_NAME' already exists; skipping automatic restore."
  exit 0
fi

info "Checking rclone Dropbox connectivity..."
if ! rclone lsd "${DROPBOX_REMOTE}:" &>/dev/null; then
  error "Cannot reach the '${DROPBOX_REMOTE}' rclone remote."
  error "Configure it with: rclone config"
  error "If tokens have expired, reconnect with: rclone config reconnect ${DROPBOX_REMOTE}:"
  exit 1
fi

info "Preflight checks passed."

# --------------------------------------------------------------------------- #
# 2. Acquire GPG passphrase
# --------------------------------------------------------------------------- #
if [[ -z "${PASSPHRASE:-}" ]]; then
  read -r -s -p "Enter GPG passphrase: " PASSPHRASE
  echo
fi

if [[ -z "$PASSPHRASE" ]]; then
  error "Passphrase cannot be empty."
  exit 1
fi
export -n PASSPHRASE

# --------------------------------------------------------------------------- #
# 3. Find latest backup on Dropbox
# --------------------------------------------------------------------------- #
info "Listing backups at ${DROPBOX_REMOTE}:${DROPBOX_PATH} ..."

if ! BACKUP_LIST=$(rclone lsf "${DROPBOX_REMOTE}:${DROPBOX_PATH}" --files-only); then
  error "Unable to list backups at ${DROPBOX_REMOTE}:${DROPBOX_PATH}."
  exit 1
fi
LATEST_FILE=$(printf '%s\n' "$BACKUP_LIST" \
  | grep -E '^freshrss_[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}-[0-9]{2}-[0-9]{2}\.tar\.zst\.gpg$' \
  | LC_ALL=C sort | tail -n 1 || true)

if [[ -z "$LATEST_FILE" ]]; then
  error "No backup files found at ${DROPBOX_REMOTE}:${DROPBOX_PATH}"
  error "Verify the path is correct (override with DROPBOX_PATH env var) and backups exist."
  exit 1
fi

info "Latest backup: $LATEST_FILE"

# --------------------------------------------------------------------------- #
# 4. Download latest backup
# --------------------------------------------------------------------------- #
mkdir -p "$TMP_DIR"
info "Downloading $LATEST_FILE to $TMP_DIR ..."
rclone copy "${DROPBOX_REMOTE}:${DROPBOX_PATH}/${LATEST_FILE}" "$TMP_DIR" --progress
LOCAL_BACKUP="${TMP_DIR}/${LATEST_FILE}"

info "Validating backup before changing FreshRSS..."
gpg --batch --yes --pinentry-mode loopback --passphrase-fd 3 -d "$LOCAL_BACKUP" 3<<<"$PASSPHRASE" \
  | zstd -d | tar -tf - >/dev/null

# --------------------------------------------------------------------------- #
# 5. Stop the service if running
# --------------------------------------------------------------------------- #
if docker ps -a --filter "name=^${CONTAINER_NAME}$" --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
  warn "The '${CONTAINER_NAME}' container already exists."
  warn "This restore will stop the service and overwrite ALL existing data."
  if ! confirm "Stop FreshRSS and proceed with restore?"; then
    info "Aborted by operator."
    exit 0
  fi
fi

# --------------------------------------------------------------------------- #
# 6. Prepare volume
# --------------------------------------------------------------------------- #
if docker volume inspect "$VOLUME_NAME" &>/dev/null; then
  warn "Volume '$VOLUME_NAME' already exists and contains data."
  warn "Its contents will be permanently deleted."
  if ! confirm "Wipe volume '$VOLUME_NAME' and restore from backup?"; then
    info "Aborted by operator."
    exit 0
  fi
fi

if [[ "$(docker inspect -f '{{.State.Running}}' filedata-backup 2>/dev/null || true)" == "true" ]]; then
  BACKUP_WAS_RUNNING=true
  info "Stopping filedata-backup..."
  docker stop filedata-backup >/dev/null
fi

if docker ps -a --filter "name=^${CONTAINER_NAME}$" --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
  info "Removing FreshRSS container..."
  docker rm -f "$CONTAINER_NAME"
fi

if docker volume inspect "$VOLUME_NAME" &>/dev/null; then
  info "Clearing existing volume..."
  docker run --rm -v "${VOLUME_NAME}:/restore" alpine \
    sh -c 'find /restore -mindepth 1 -maxdepth 1 -exec rm -rf {} +'
fi

info "Creating volume '$VOLUME_NAME'..."
docker volume create "$VOLUME_NAME"

# --------------------------------------------------------------------------- #
# 7. Decrypt and restore
# --------------------------------------------------------------------------- #
info "Restoring backup into volume '$VOLUME_NAME' ..."
info "(This may take a minute depending on backup size)"

gpg --batch --yes --pinentry-mode loopback --passphrase-fd 3 -d "$LOCAL_BACKUP" 3<<<"$PASSPHRASE" \
  | zstd -d \
  | docker run --rm -i -v "${VOLUME_NAME}:/restore" alpine \
      sh -c "cd /restore && tar -xf -"

info "Restore complete."

# --------------------------------------------------------------------------- #
# 8. Bring up the service
# --------------------------------------------------------------------------- #
info "Starting FreshRSS and waiting up to 300 seconds for it to become healthy..."
if ! docker compose -f "${SCRIPT_DIR}/docker-compose.yml" up -d --wait --wait-timeout 300; then
  error "FreshRSS failed to start or become healthy."
  error "Check: docker compose -f ${SCRIPT_DIR}/docker-compose.yml logs"
  exit 1
fi

echo ""
echo "=========================================="
echo "  FreshRSS restore completed successfully!"
echo "  FreshRSS health check passed."
echo "  Access FreshRSS via your NPM proxy URL."
echo "=========================================="
