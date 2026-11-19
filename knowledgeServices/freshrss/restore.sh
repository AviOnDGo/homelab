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

# --------------------------------------------------------------------------- #
# Cleanup trap — runs on any exit (success or failure)
# --------------------------------------------------------------------------- #
cleanup() {
  rm -rf "$TMP_DIR"
  unset PASSPHRASE
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
  read -r -p "$prompt [y/N] " answer
  [[ "$answer" == "y" || "$answer" == "Y" ]]
}

# --------------------------------------------------------------------------- #
# 1. Preflight checks
# --------------------------------------------------------------------------- #
info "Running preflight checks..."

for cmd in docker rclone gpg zstd; do
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

LATEST_FILE=$(rclone lsf "${DROPBOX_REMOTE}:${DROPBOX_PATH}" --files-only 2>/dev/null \
  | sort \
  | tail -n 1 \
  || true)

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
  info "Stopping FreshRSS service..."
  docker compose -f "${SCRIPT_DIR}/docker-compose.yml" down
else
  info "FreshRSS is not running — no shutdown needed."
fi

# --------------------------------------------------------------------------- #
# 6. Prepare volume
# --------------------------------------------------------------------------- #
if docker volume inspect "$VOLUME_NAME" &>/dev/null; then
  warn "Volume '$VOLUME_NAME' already exists and contains data."
  warn "It will be permanently destroyed and recreated."
  if ! confirm "Wipe volume '$VOLUME_NAME' and restore from backup?"; then
    info "Aborted by operator."
    exit 0
  fi
  info "Removing existing volume..."
  docker volume rm "$VOLUME_NAME"
fi

info "Creating volume '$VOLUME_NAME'..."
docker volume create "$VOLUME_NAME"

# --------------------------------------------------------------------------- #
# 7. Decrypt and restore
# --------------------------------------------------------------------------- #
info "Restoring backup into volume '$VOLUME_NAME' ..."
info "(This may take a minute depending on backup size)"

gpg --batch --yes --passphrase "$PASSPHRASE" -d "$LOCAL_BACKUP" \
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

echo ""
echo "=========================================="
echo "  FreshRSS restore completed successfully!"
echo "  check-install.php passed."
echo "  Access FreshRSS via your NPM proxy URL."
echo "=========================================="
