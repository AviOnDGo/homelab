#!/usr/bin/env bash
# Restore Pi-hole from the latest Dropbox backup.
# Usage: ./restore.sh [--if-missing|--force]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
COMPOSE_FILE="${SCRIPT_DIR}/docker-compose.yml"
VOLUME_NAME="pihole_filedata"
CONTAINER_NAME="pihole"
DROPBOX_REMOTE="${DROPBOX_REMOTE:-dropbox}"
DROPBOX_PATH="${DROPBOX_PATH:-/Apps/pihole}"
MODE="${1:-}"
TMP_DIR=""
BACKUP_WAS_RUNNING=false

# --------------------------------------------------------------------------- #
# Cleanup trap - runs on any exit (success or failure)
# --------------------------------------------------------------------------- #
cleanup() {
  local status=$?
  if [[ "$BACKUP_WAS_RUNNING" == "true" ]] && ! docker start filedata-backup >/dev/null; then
    echo "[ERROR] Could not restart filedata-backup." >&2
    status=1
  fi
  if [[ -n "$TMP_DIR" ]]; then
    rm -rf "$TMP_DIR"
  fi
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
    error "Pi-hole already exists; refusing to restore automatically."
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

if [[ "$MODE" == "--if-missing" ]] && docker volume inspect "$VOLUME_NAME" >/dev/null 2>&1; then
  info "Volume '$VOLUME_NAME' already exists; skipping automatic restore."
  exit 0
fi

docker compose -f "$COMPOSE_FILE" config --quiet
PIHOLE_IMAGE=$(docker compose -f "$COMPOSE_FILE" config --images pihole)
if [[ -z "$PIHOLE_IMAGE" || "$PIHOLE_IMAGE" == *$'\n'* ]]; then
  error "Could not determine the Pi-hole image from Compose."
  exit 1
fi

if ! rclone lsd "${DROPBOX_REMOTE}:" >/dev/null 2>&1; then
  error "Cannot reach rclone remote '${DROPBOX_REMOTE}'."
  exit 1
fi

# --------------------------------------------------------------------------- #
# 2. Acquire GPG passphrase
# --------------------------------------------------------------------------- #
if [[ -z "${PASSPHRASE:-}" ]]; then
  if ! read -r -s -p "Enter GPG passphrase: " PASSPHRASE; then
    error "Passphrase input unavailable; restore aborted."
    exit 1
  fi
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
  | grep -E '^pihole_[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}-[0-9]{2}-[0-9]{2}\.tar\.zst\.gpg$' \
  | LC_ALL=C sort | tail -n 1 || true)

if [[ -z "$LATEST_FILE" ]]; then
  error "No backup files found at ${DROPBOX_REMOTE}:${DROPBOX_PATH}."
  exit 1
fi

# --------------------------------------------------------------------------- #
# 4. Download and validate latest backup
# --------------------------------------------------------------------------- #
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/pihole-restore.XXXXXXXX")
TMP_DIR="$(cd "$TMP_DIR" && pwd -P)"
info "Downloading latest backup: $LATEST_FILE"
rclone copy "${DROPBOX_REMOTE}:${DROPBOX_PATH}/${LATEST_FILE}" "$TMP_DIR" --progress
LOCAL_BACKUP="${TMP_DIR}/${LATEST_FILE}"

info "Validating backup before changing Pi-hole..."
mkdir "$TMP_DIR/staged"
gpg --batch --yes --pinentry-mode loopback --passphrase-fd 3 -d "$LOCAL_BACKUP" 3<<<"$PASSPHRASE" \
  | zstd -d | tar --no-same-owner --no-same-permissions -xf - -C "$TMP_DIR/staged"
for database in gravity.db pihole-FTL.db; do
  path="$TMP_DIR/staged/$database"
  if [[ -L "$path" || ! -f "$path" || ! -s "$path" ]]; then
    error "Invalid backup database $database: missing, empty, or not a regular file."
    exit 1
  fi
  for suffix in -wal -shm; do
    sidecar="${path}${suffix}"
    if [[ -L "$sidecar" || ( -e "$sidecar" && ! -f "$sidecar" ) ]]; then
      error "Invalid SQLite sidecar: ${database}${suffix}."
      exit 1
    fi
  done
  # SQLite may need to create or update sidecars to read a WAL-backed database.
  if ! result=$(docker run --rm --network none --read-only --entrypoint pihole-FTL \
    -v "$TMP_DIR/staged:/check" "$PIHOLE_IMAGE" "/check/$database" 'PRAGMA integrity_check;'); then
    error "Invalid backup database $database: integrity check could not run."
    exit 1
  fi
  if [[ "$result" != "ok" ]]; then
    error "Invalid backup database $database: integrity check failed: $result"
    exit 1
  fi
done

# --------------------------------------------------------------------------- #
# 5. Stop the service if running
# --------------------------------------------------------------------------- #
CONTAINERS=$(docker ps -a --filter "name=^${CONTAINER_NAME}$" --format '{{.Names}}')
if printf '%s\n' "$CONTAINERS" | grep -qx "$CONTAINER_NAME"; then
  warn "The '$CONTAINER_NAME' container already exists."
  warn "This restore will stop the service and overwrite ALL existing data."
  if ! confirm "Stop Pi-hole and proceed with restore?"; then
    info "Aborted by operator."
    exit 0
  fi
fi

# --------------------------------------------------------------------------- #
# 6. Prepare volume
# --------------------------------------------------------------------------- #
if docker volume inspect "$VOLUME_NAME" >/dev/null 2>&1; then
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

if printf '%s\n' "$CONTAINERS" | grep -qx "$CONTAINER_NAME"; then
  info "Removing Pi-hole container..."
  docker rm -f "$CONTAINER_NAME"
fi

if docker volume inspect "$VOLUME_NAME" >/dev/null 2>&1; then
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
gpg --batch --yes --pinentry-mode loopback --passphrase-fd 3 -d "$LOCAL_BACKUP" 3<<<"$PASSPHRASE" \
  | zstd -d \
  | docker run --rm -i -v "${VOLUME_NAME}:/restore" alpine \
      sh -c "cd /restore && tar -xf -"

# --------------------------------------------------------------------------- #
# 8. Bring up the service
# --------------------------------------------------------------------------- #
info "Starting Pi-hole service..."
docker compose -f "$COMPOSE_FILE" up -d

# --------------------------------------------------------------------------- #
# 9. Verify
# --------------------------------------------------------------------------- #
info "Waiting for container to become ready..."
sleep 3

for database in gravity.db pihole-FTL.db; do
  path="/etc/pihole/$database"
  if ! docker exec "$CONTAINER_NAME" sh -c \
    'test -f "$1" && test ! -L "$1" && test -s "$1"' sh "$path"; then
    error "$database is missing, empty, or not a regular file."
    exit 1
  fi
  if ! result=$(docker exec "$CONTAINER_NAME" pihole-FTL "$path" 'PRAGMA integrity_check;'); then
    error "Could not check the integrity of $database."
    exit 1
  fi
  if [[ "$result" != "ok" ]]; then
    error "Integrity check failed for $database: $result"
    exit 1
  fi
done

echo
echo "=============================================="
echo " Pi-hole restore completed successfully"
echo " Restored file: $LATEST_FILE"
echo "=============================================="
