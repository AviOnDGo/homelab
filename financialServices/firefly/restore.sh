#!/usr/bin/env bash
# Restore Firefly PostgreSQL from the latest Dropbox backup.
# Usage: ./restore.sh [--if-missing|--force]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="${SCRIPT_DIR}/docker-compose.yml"
VOLUME_NAME="firefly_postgresdata"
DB_CONTAINER="firefly-db"
BACKUP_CONTAINER="db-backup"
DROPBOX_REMOTE="${DROPBOX_REMOTE:-dropbox}"
DROPBOX_PATH="${DROPBOX_PATH:-/Apps/firefly}"
MODE="${1:-}"
TMP_DIR=""
BACKUP_WAS_RUNNING=false
RESTORE_UNSAFE=false

# --------------------------------------------------------------------------- #
# Helpers
# --------------------------------------------------------------------------- #
info()  { echo "[INFO]  $*"; }
warn()  { echo "[WARN]  $*" >&2; }
error() { echo "[ERROR] $*" >&2; }

# --------------------------------------------------------------------------- #
# Cleanup trap - runs on any exit (success or failure)
# --------------------------------------------------------------------------- #
cleanup() {
  local status=$?
  trap - EXIT
  # Never resume scheduled backups against a partially restored database.
  if [[ "$BACKUP_WAS_RUNNING" == true ]]; then
    if [[ "$RESTORE_UNSAFE" == true ]]; then
      error "Restore is incomplete; ${BACKUP_CONTAINER} remains stopped."
      error "Recover Firefly before manually restarting ${BACKUP_CONTAINER}."
    elif ! docker start "$BACKUP_CONTAINER" >/dev/null; then
      error "Could not restart ${BACKUP_CONTAINER}; restart it manually."
      status=1
    fi
  fi
  if [[ -n "$TMP_DIR" ]]; then
    rm -rf -- "$TMP_DIR"
  fi
  unset PASSPHRASE
  exit "$status"
}
trap cleanup EXIT

# --------------------------------------------------------------------------- #
# 1. Preflight checks
# --------------------------------------------------------------------------- #
if [[ $# -gt 1 ]] || [[ -n "$MODE" && "$MODE" != "--if-missing" && "$MODE" != "--force" ]]; then
  error "Usage: $0 [--if-missing|--force]"
  exit 1
fi

info "Running preflight checks..."
for cmd in docker rclone gpg zstd; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    error "Required tool not found: $cmd"
    exit 1
  fi
done
if ! docker info >/dev/null 2>&1; then
  error "Cannot connect to Docker daemon."
  exit 1
fi

if ! VOLUMES=$(docker volume ls --filter "name=^${VOLUME_NAME}$" --format '{{.Name}}'); then
  error "Could not list Docker volumes."
  exit 1
fi
if grep -Fxq -- "$VOLUME_NAME" <<< "$VOLUMES"; then
  VOLUME_EXISTS=true
else
  VOLUME_EXISTS=false
fi
if [[ "$MODE" == "--if-missing" && "$VOLUME_EXISTS" == true ]]; then
  info "Volume '$VOLUME_NAME' already exists; skipping automatic restore."
  exit 0
fi

# Never replace containers from another Compose project implicitly.
if ! FIREFLY_CONTAINERS=$(docker ps -a --filter 'name=^/firefly$' \
  --filter 'name=^/firefly-db$' --filter 'name=^/firefly-cron$' --format '{{.Names}}'); then
  error "Could not inspect existing Firefly containers."
  exit 1
fi
if [[ "$MODE" == "--if-missing" && -n "$FIREFLY_CONTAINERS" ]]; then
  error "Firefly containers exist without the database volume; refusing automatic restore."
  exit 1
fi

if ! rclone lsd "${DROPBOX_REMOTE}:" >/dev/null; then
  error "Cannot reach rclone remote '${DROPBOX_REMOTE}'."
  exit 1
fi

# --------------------------------------------------------------------------- #
# 2. Acquire GPG passphrase
# --------------------------------------------------------------------------- #
if [[ -z "${PASSPHRASE:-}" ]]; then
  if ! read -r -s -p "Enter GPG passphrase: " PASSPHRASE; then
    error "Passphrase input unavailable."
    exit 1
  fi
  echo
fi
if [[ -z "$PASSPHRASE" || "$PASSPHRASE" == *$'\n'* ]]; then
  error "Passphrase must be nonempty and single-line."
  exit 1
fi
export -n PASSPHRASE

# --------------------------------------------------------------------------- #
# 3. Find latest backup on Dropbox
# --------------------------------------------------------------------------- #
info "Listing Firefly backups at ${DROPBOX_REMOTE}:${DROPBOX_PATH}..."
if ! BACKUP_LIST=$(rclone lsf "${DROPBOX_REMOTE}:${DROPBOX_PATH}" --files-only); then
  error "Could not list Firefly backups."
  exit 1
fi

LATEST_FILE=$(printf '%s\n' "$BACKUP_LIST" \
  | grep -E '^firefly_[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}-[0-9]{2}-[0-9]{2}\.sql\.zst\.gpg$' \
  | LC_ALL=C sort | tail -n 1 || true)
if [[ -z "$LATEST_FILE" ]]; then
  error "No Firefly SQL backups found at ${DROPBOX_REMOTE}:${DROPBOX_PATH}."
  error "Expected firefly_YYYY-MM-DD_HH-MM-SS.sql.zst.gpg."
  exit 1
fi

# --------------------------------------------------------------------------- #
# 4. Download and validate backup
# --------------------------------------------------------------------------- #
# Stage the decrypted dump privately and validate it before stopping services.
umask 077
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/firefly-restore.XXXXXXXX")
info "Downloading and validating $LATEST_FILE..."
rclone copy "${DROPBOX_REMOTE}:${DROPBOX_PATH}/${LATEST_FILE}" "$TMP_DIR" --progress
if ! gpg --batch --yes --pinentry-mode loopback --passphrase-fd 3 \
  -d "$TMP_DIR/$LATEST_FILE" 3<<<"$PASSPHRASE" | zstd -d > "$TMP_DIR/backup.sql"; then
  error "Backup decryption or decompression failed; existing data was not changed."
  exit 1
fi
if [[ ! -s "$TMP_DIR/backup.sql" ]] \
  || ! grep -Fxq -- '-- PostgreSQL database dump' "$TMP_DIR/backup.sql" \
  || ! grep -Fxq -- '-- PostgreSQL database dump complete' "$TMP_DIR/backup.sql"; then
  error "Backup is empty or is not a complete PostgreSQL plain-text dump."
  exit 1
fi

# --------------------------------------------------------------------------- #
# 5. Confirm before stopping the service
# --------------------------------------------------------------------------- #
if [[ "$MODE" != "--force" && ( "$VOLUME_EXISTS" == true || -n "$FIREFLY_CONTAINERS" ) ]]; then
  warn "Restore will replace the existing Firefly database and stop the stack."
  if ! read -r -p "Proceed with restore? [y/N] " choice; then
    error "Confirmation input unavailable; restore aborted."
    exit 1
  fi
  if [[ "$choice" != y && "$choice" != Y ]]; then
    info "Restore cancelled; no data was changed."
    exit 0
  fi
fi

# --------------------------------------------------------------------------- #
# 6. Stop services and prepare the database volume
# --------------------------------------------------------------------------- #
if ! BACKUP_STATE=$(docker ps -a --filter "name=^/${BACKUP_CONTAINER}$" \
  --format '{{.Names}} {{.State}}'); then
  error "Could not inspect ${BACKUP_CONTAINER}."
  exit 1
fi
if [[ "$BACKUP_STATE" == "$BACKUP_CONTAINER running" ]]; then
  info "Stopping ${BACKUP_CONTAINER}..."
  BACKUP_WAS_RUNNING=true
  docker stop "$BACKUP_CONTAINER" >/dev/null
fi

info "Stopping the Firefly stack..."
docker compose -f "$COMPOSE_FILE" down
if ! FIREFLY_CONTAINERS=$(docker ps -a --filter 'name=^/firefly$' \
  --filter 'name=^/firefly-db$' --filter 'name=^/firefly-cron$' --format '{{.Names}}'); then
  error "Could not inspect Firefly containers after stopping the stack."
  exit 1
fi
if [[ -n "$FIREFLY_CONTAINERS" ]]; then
  error "Firefly containers remain; check the Compose project before retrying."
  exit 1
fi
if ! VOLUME_USERS=$(docker ps -q --filter "volume=$VOLUME_NAME"); then
  error "Could not inspect running containers using ${VOLUME_NAME}."
  exit 1
fi
if [[ -n "$VOLUME_USERS" ]]; then
  error "Another running container uses ${VOLUME_NAME}; stop it before restoring."
  exit 1
fi

# Clear in place because a stopped backup container can still hold the volume.
RESTORE_UNSAFE=true
if [[ "$VOLUME_EXISTS" == true ]]; then
  info "Clearing existing database volume..."
  docker run --rm -v "${VOLUME_NAME}:/restore" alpine \
    sh -c 'find /restore -mindepth 1 -maxdepth 1 -exec rm -rf {} +'
else
  docker volume create "$VOLUME_NAME" >/dev/null
fi
docker compose -f "$COMPOSE_FILE" create
docker start "$DB_CONTAINER" >/dev/null

# --------------------------------------------------------------------------- #
# 7. Wait for PostgreSQL and import the backup
# --------------------------------------------------------------------------- #
info "Waiting for PostgreSQL..."
ready=false
for ((i = 1; i <= 60; i++)); do
  if docker exec "$DB_CONTAINER" sh -c 'pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB"' >/dev/null 2>&1; then
    ready=true
    break
  fi
  sleep 1
done
if [[ "$ready" != true ]]; then
  error "PostgreSQL did not become ready; inspect docker logs ${DB_CONTAINER}."
  exit 1
fi

info "Importing database..."
# A successful psql exit requires every SQL statement to succeed.
if ! docker exec -i "$DB_CONTAINER" sh -c \
  'exec psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB"' < "$TMP_DIR/backup.sql"; then
  error "Database import failed; Firefly was not started."
  exit 1
fi

# --------------------------------------------------------------------------- #
# 8. Verify the restored database
# --------------------------------------------------------------------------- #
if ! docker exec "$DB_CONTAINER" sh -c \
  'exec psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT 1 FROM public.transactions LIMIT 0"' >/dev/null; then
  error "Restored database is missing the Firefly transactions table."
  exit 1
fi

# --------------------------------------------------------------------------- #
# 9. Start Firefly and verify health
# --------------------------------------------------------------------------- #
info "Starting Firefly and waiting for health checks..."
if ! docker compose -f "$COMPOSE_FILE" up -d --wait --wait-timeout 300; then
  error "Firefly did not become healthy; inspect docker compose logs."
  exit 1
fi
RESTORE_UNSAFE=false
info "Firefly restore completed from $LATEST_FILE."
