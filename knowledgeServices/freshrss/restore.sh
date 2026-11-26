#!/usr/bin/env bash
# restore.sh — Restore FreshRSS from the latest Dropbox backup
# Usage: [PASSPHRASE=<gpg-passphrase>] [DROPBOX_PATH=/Apps/freshrss] ./restore.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VOLUME_NAME="freshrss_filedata"
CONTAINER_NAME="freshrss"
DROPBOX_REMOTE="dropbox"
DROPBOX_PATH="${DROPBOX_PATH:-/Apps/freshrss}"
TMP_DIR="/tmp/freshrss-restore-$$"
BACKUP_STATE_FILE="${TMPDIR:-/tmp}/freshrss-restore-backup-state"
BACKUP_WAS_RUNNING=false

# --------------------------------------------------------------------------- #
# Cleanup trap — runs on any exit (success or failure)
# --------------------------------------------------------------------------- #
restore_backup_state() {
  [[ -f "$BACKUP_STATE_FILE" ]] || return 0

  local backup_running
  backup_running=$(docker inspect -f '{{.State.Running}}' filedata-backup 2>/dev/null || true)
  if [[ "$backup_running" != "true" ]]; then
    if ! docker start filedata-backup >/dev/null; then
      error "Could not restart filedata-backup; saved state retained for the next run."
      return 1
    fi
    info "Restarted filedata-backup to restore its prior running state."
  fi

  rm -f -- "$BACKUP_STATE_FILE"
}

cleanup() {
  local exit_status=$?
  trap - EXIT

  if ! rm -rf "$TMP_DIR"; then
    error "Could not remove temporary restore files: $TMP_DIR"
    exit_status=1
  fi
  if [[ -f "$BACKUP_STATE_FILE" ]] && ! restore_backup_state; then
    exit_status=1
  fi
  unset PASSPHRASE
  exit "$exit_status"
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

for cmd in docker rclone gpg zstd tar flock; do
  if ! command -v "$cmd" &>/dev/null; then
    error "Required tool not found: $cmd"
    error "Install $cmd and re-run this script."
    exit 1
  fi
done

if [[ ! -e /tmp/freshrss-restore.lock ]]; then
  (umask 022; : >> /tmp/freshrss-restore.lock)
fi
exec 9</tmp/freshrss-restore.lock
if ! flock -n 9; then
  error "Another FreshRSS restore is already in progress."
  exit 1
fi

if ! docker info &>/dev/null; then
  error "Cannot connect to Docker daemon."
  error "Ensure Docker is running and your user has access to the Docker socket."
  exit 1
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
if [[ ! -s "$LOCAL_BACKUP" ]]; then
  error "Downloaded backup is missing or empty: $LOCAL_BACKUP"
  exit 1
fi

# Validate decryption, compression, and archive structure before touching services
# or existing volume data.
info "Validating backup archive..."
gpg --batch --yes --pinentry-mode loopback --passphrase-fd 3 -d "$LOCAL_BACKUP" 3<<<"$PASSPHRASE" \
  | zstd -d \
  | tar -tf - >/dev/null

# --------------------------------------------------------------------------- #
# 5. Stop the service if running
# --------------------------------------------------------------------------- #
if docker ps --filter "name=^${CONTAINER_NAME}$" --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
  warn "The '${CONTAINER_NAME}' container is currently running."
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

if [[ -e "$BACKUP_STATE_FILE" || -L "$BACKUP_STATE_FILE" ]]; then
  if [[ -L "$BACKUP_STATE_FILE" || ! -f "$BACKUP_STATE_FILE" ]]; then
    error "Invalid backup-state marker: $BACKUP_STATE_FILE"
    exit 1
  fi
  if ! IFS= read -r saved_backup_state <"$BACKUP_STATE_FILE" \
    || [[ "$saved_backup_state" != "running" ]]; then
    error "Invalid backup-state marker: $BACKUP_STATE_FILE"
    exit 1
  fi
  BACKUP_WAS_RUNNING=true
elif [[ "$(docker inspect -f '{{.State.Running}}' filedata-backup 2>/dev/null || true)" == "true" ]]; then
  BACKUP_WAS_RUNNING=true
  if ! (umask 077; set -o noclobber; printf 'running\n' >"$BACKUP_STATE_FILE"); then
    error "Cannot save filedata-backup state; refusing to stop the container."
    exit 1
  fi
fi

if [[ "$BACKUP_WAS_RUNNING" == "true" ]]; then
  info "Stopping filedata-backup..."
  docker stop filedata-backup >/dev/null
fi

if docker ps --filter "name=^${CONTAINER_NAME}$" --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
  info "Stopping FreshRSS service..."
  docker compose -f "${SCRIPT_DIR}/docker-compose.yml" down
  if docker ps --filter "name=^${CONTAINER_NAME}$" --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    error "FreshRSS is still running; refusing to clear its volume."
    exit 1
  fi
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
info "Starting FreshRSS service..."
docker compose -f "${SCRIPT_DIR}/docker-compose.yml" up -d

# --------------------------------------------------------------------------- #
# 9. Verify — retry loop up to 300 seconds
# --------------------------------------------------------------------------- #
info "Waiting for FreshRSS to become healthy (up to 300s)..."

MAX_WAIT=300
INTERVAL=5
ELAPSED=0

until docker exec "$CONTAINER_NAME" php /var/www/FreshRSS/cli/health.php &>/dev/null; do
  if (( ELAPSED >= MAX_WAIT )); then
    error "FreshRSS did not become healthy within ${MAX_WAIT}s."
    error "Check logs with: docker compose -f ${SCRIPT_DIR}/docker-compose.yml logs -f freshrss"
    exit 1
  fi
  sleep "$INTERVAL"
  ELAPSED=$(( ELAPSED + INTERVAL ))
done

if [[ "$BACKUP_WAS_RUNNING" == "true" ]]; then
  info "Restarting filedata-backup..."
  restore_backup_state
fi

echo ""
echo "=========================================="
echo "  FreshRSS restore completed successfully!"
echo "  FreshRSS health check passed."
if [[ "$(docker inspect -f '{{.State.Running}}' filedata-backup 2>/dev/null || true)" == "true" ]]; then
  echo "  filedata-backup is running."
else
  echo "  filedata-backup is not running."
fi
echo "  Access FreshRSS via your NPM proxy URL."
echo "=========================================="
