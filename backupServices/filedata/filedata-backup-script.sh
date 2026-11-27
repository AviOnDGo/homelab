#!/bin/bash

set -e

# Filesystem Backup Script
# Dual-mode backup for Docker volumes:
# - archive: tar + zstd + GPG + Dropbox upload (existing behavior)
# - sync-crypt: rclone sync to crypt remote with deleted-file retention
# Usage: ./filedata-backup-script.sh <volume_name>

VOLUME_NAME=$1

if [ -z "$VOLUME_NAME" ]; then
    echo "ERROR: Volume name required"
    echo "Usage: $0 <volume_name>"
    exit 1
fi

# Configuration from environment variables
SOURCE_DIR="/backup-sources/${VOLUME_NAME}"
BACKUP_DIR="/backups/${VOLUME_NAME}"
TIMESTAMP=$(date +%F_%H-%M-%S)
HOST=$(hostname)
BACKUP_FILE="${BACKUP_DIR}/${VOLUME_NAME}_${TIMESTAMP}.tar.zst"
BACKUP_FILE_GPG="${BACKUP_FILE}.gpg"
DATE_STAMP=$(date +%F)

# Normalize volume key for env-var lookup (e.g. immich-library -> IMMICH_LIBRARY)
VOLUME_ENV_KEY="${VOLUME_NAME//-/_}"
VOLUME_ENV_KEY="${VOLUME_ENV_KEY^^}"

# Per-service mode and retention
BACKUP_MODE_VAR="${VOLUME_ENV_KEY}_BACKUP_MODE"
RETENTION_DAYS_VAR="${VOLUME_ENV_KEY}_RETENTION_DAYS"
BACKUP_MODE="${!BACKUP_MODE_VAR:-archive}"
RETENTION_DAYS="${!RETENTION_DAYS_VAR:-7}"

# Load GPG passphrase from secrets if it exists
if [ -f /run/secrets/gpg-passphrase ]; then
  GPG_PASSPHRASE=$(cat /run/secrets/gpg-passphrase)
else
  GPG_PASSPHRASE="${GPG_PASSPHRASE:-}"
fi

# Function to send Discord failure notification
send_discord_failure() {
  local phase="$1"
  local detail="$2"

  [ -z "$DISCORD_WEBHOOK_URL" ] && return 0

  curl -s -X POST "$DISCORD_WEBHOOK_URL" \
    -H "Content-Type: application/json" \
    -d "{
      \"embeds\": [{
        \"title\": \"❌ Filesystem Backup Failed\",
        \"color\": 16711680,
        \"fields\": [
          {\"name\": \"Volume\", \"value\": \"${VOLUME_NAME}\", \"inline\": true},
          {\"name\": \"Phase\", \"value\": \"${phase}\", \"inline\": true},
          {\"name\": \"Detail\", \"value\": \"${detail}\", \"inline\": false},
          {\"name\": \"Timestamp\", \"value\": \"${TIMESTAMP}\", \"inline\": true},
          {\"name\": \"Host\", \"value\": \"${HOST}\", \"inline\": true}
        ],
        \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%S.000Z)\"
      }]
    }" > /dev/null 2>&1 || echo "Discord notification failed"
}

require_env_var() {
  local name="$1"
  local value="$2"
  if [ -z "$value" ]; then
    echo "ERROR: Required environment variable missing: ${name}"
    send_discord_failure "Configuration" "Required environment variable missing: ${name}"
    exit 1
  fi
}

require_rclone_remote() {
  local remote_path="$1"
  local remote_name="${remote_path%%:*}"

  if ! rclone listremotes | grep -Fqx "${remote_name}:"; then
    echo "ERROR: rclone remote is not configured: ${remote_name}"
    send_discord_failure "Configuration" "Missing rclone remote: ${remote_name}"
    exit 1
  fi
}

TAR_EXCLUDES=()
RCLONE_EXCLUDES=()

configure_volume_excludes() {
  case "$VOLUME_NAME" in
    paperless)
      TAR_EXCLUDES+=(--exclude="./documents/thumbnails")
      TAR_EXCLUDES+=(--exclude="./media.lock")
      RCLONE_EXCLUDES+=(--exclude="/documents/thumbnails/**")
      RCLONE_EXCLUDES+=(--exclude="/media.lock")
      echo "Filter: excluding documents/thumbnails and media.lock"
      ;;
    openwebui)
      TAR_EXCLUDES+=(--exclude="./cache")
      TAR_EXCLUDES+=(--exclude="./vector_db")
      RCLONE_EXCLUDES+=(--exclude="/cache/**")
      RCLONE_EXCLUDES+=(--exclude="/vector_db/**")
      echo "Filter: excluding cache and vector_db"
      ;;
  esac
}

validate_romm_sync_source() {
  [[ "$VOLUME_NAME" == "romm" && "$BACKUP_MODE" == "sync-crypt" ]] || return 0

  local required_dir
  local required_path
  local first_file

  for required_dir in library assets; do
    required_path="${SOURCE_DIR}/${required_dir}"
    if [[ ! -d "$required_path" ]]; then
      echo "ERROR: RomM filedata directory is missing: ${required_path}"
      send_discord_failure "Source validation" \
        "RomM filedata directory is missing: ${required_dir}/"
      exit 1
    fi

    if ! first_file=$(find "$required_path" -type f -print -quit); then
      echo "ERROR: Failed to inspect RomM filedata directory: ${required_path}"
      send_discord_failure "Source validation" \
        "Failed to inspect RomM filedata directory: ${required_dir}/"
      exit 1
    fi

    if [[ -z "$first_file" ]]; then
      echo "ERROR: RomM filedata directory contains no files: ${required_path}"
      send_discord_failure "Source validation" \
        "RomM filedata directory contains no files: ${required_dir}/"
      exit 1
    fi
  done
}

cleanup_old_dropbox_backups() {
  local dropbox_path="$1"

  # Local cleanup
  local local_deleted
  local_deleted=$(find "$BACKUP_DIR" -name "${VOLUME_NAME}_*.tar.zst.gpg" -type f -mtime +"${RETENTION_DAYS}" -delete -print | wc -l)
  echo "Deleted ${local_deleted} local backup(s) older than ${RETENTION_DAYS} days"

  # Remote cleanup
  echo "Cleaning Dropbox backups older than ${RETENTION_DAYS} days..."
  if rclone ls "dropbox:${dropbox_path}" >/dev/null 2>&1; then
    rclone ls "dropbox:${dropbox_path}" | awk '{print $2}' | while read -r file; do
      file_date=$(echo "$file" | sed -n 's/^[a-zA-Z0-9_]*_\([0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}\).*/\1/p')
      if [ -n "$file_date" ]; then
        file_epoch=$(date -d "$file_date" +%s 2>/dev/null || echo 0)
        cutoff_epoch=$(($(date +%s) - RETENTION_DAYS * 86400))
        if [ "$file_epoch" -lt "$cutoff_epoch" ]; then
          echo "Deleting remote backup: $file"
          rclone delete "dropbox:${dropbox_path}/${file}" 2>/dev/null || true
        fi
      fi
    done
  fi
}

cleanup_old_sync_crypt_backups() {
  local sync_remote="$1"
  local deleted_base="${sync_remote%/}/deleted-archive"
  local cutoff_epoch
  cutoff_epoch=$(($(date +%s) - RETENTION_DAYS * 86400))

  echo "Pruning sync-crypt deleted archive older than ${RETENTION_DAYS} days..."
  if ! rclone lsf "${deleted_base}/" --dirs-only >/dev/null 2>&1; then
    echo "No deleted-archive path found yet, skipping prune"
    return 0
  fi

  rclone lsf "${deleted_base}/" --dirs-only | while read -r day_dir; do
    day_dir="${day_dir%/}"
    day_epoch=$(date -d "${day_dir}" +%s 2>/dev/null || echo 0)
    if [ "$day_epoch" -gt 0 ] && [ "$day_epoch" -lt "$cutoff_epoch" ]; then
      echo "Removing old deleted-archive path: ${day_dir}"
      rclone purge "${deleted_base}/${day_dir}" 2>/dev/null || {
        rclone delete "${deleted_base}/${day_dir}" 2>/dev/null || true
        rclone rmdirs "${deleted_base}/${day_dir}" 2>/dev/null || true
      }
    fi
  done
}

run_archive_backup() {
  local dropbox_path_var="${VOLUME_ENV_KEY}_DROPBOX_PATH"
  local dropbox_path="${!dropbox_path_var:-}"

  require_env_var "${dropbox_path_var}" "${dropbox_path}"

  echo "Target Dropbox Path: ${dropbox_path}"

  # Create backup directory if it doesn't exist
  mkdir -p "$BACKUP_DIR"

  # Phase 1: Create tar archive
  echo "[1/5] Creating tar archive..."
  tar -cf - -C "$SOURCE_DIR" "${TAR_EXCLUDES[@]}" . \
    | zstd -6 -T1 -o "$BACKUP_FILE"

  if [ ! -f "$BACKUP_FILE" ]; then
    echo "ERROR: Failed to create backup archive"
    send_discord_failure "Tar archive" "Failed to create backup archive for $VOLUME_NAME"
    exit 1
  fi

  BACKUP_SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
  echo "Archive created: $BACKUP_SIZE"

  # Phase 2: GPG Encryption
  echo "[2/5] Encrypting with GPG (AES256)..."
  printf '%s\n' "$GPG_PASSPHRASE" | gpg --symmetric --cipher-algo AES256 \
      --batch --yes --passphrase-fd 0 \
      -o "$BACKUP_FILE_GPG" "$BACKUP_FILE"

  if [ ! -f "$BACKUP_FILE_GPG" ]; then
    echo "ERROR: Failed to encrypt backup"
    send_discord_failure "GPG encryption" "Failed to encrypt backup for $VOLUME_NAME"
    rm -f "$BACKUP_FILE"
    exit 1
  fi

  # Remove unencrypted backup
  rm -f "$BACKUP_FILE"

  ENCRYPTED_SIZE=$(du -h "$BACKUP_FILE_GPG" | cut -f1)
  echo "Encrypted: $ENCRYPTED_SIZE"

  # Phase 3: Validate the startup-generated Dropbox remote
  echo "[3/5] Validating rclone Dropbox remote..."
  require_rclone_remote "dropbox:${dropbox_path}"

  # Phase 4: Upload to Dropbox
  echo "[4/5] Uploading to Dropbox..."
  if rclone copy "$BACKUP_FILE_GPG" "dropbox:${dropbox_path}/" --progress 2>&1; then
    echo "Upload successful"
  else
    echo "ERROR: Failed to upload to Dropbox"
    send_discord_failure "Dropbox upload" "Failed to upload $VOLUME_NAME backup to Dropbox:${dropbox_path}"
    exit 1
  fi

  # Phase 5: Cleanup old backups (local and remote)
  echo "[5/5] Cleaning up old backups..."
  cleanup_old_dropbox_backups "$dropbox_path"

  echo "=================================================="
  echo "Backup completed successfully!"
  echo "File: $(basename "$BACKUP_FILE_GPG")"
  echo "Size: $ENCRYPTED_SIZE"
  echo "=================================================="
}

run_sync_crypt_backup() {
  local sync_remote_var="${VOLUME_ENV_KEY}_SYNC_CRYPT_REMOTE"
  local sync_remote="${!sync_remote_var:-}"
  local current_path
  local deleted_archive_path

  require_env_var "${sync_remote_var}" "${sync_remote}"
  require_rclone_remote "${sync_remote}"

  current_path="${sync_remote%/}/current"
  deleted_archive_path="${sync_remote%/}/deleted-archive/${DATE_STAMP}"

  echo "Sync-crypt remote: ${sync_remote}"
  echo "Sync current path: ${current_path}"
  echo "Deleted-item archive path: ${deleted_archive_path}"

  if [[ "${RETENTION_DAYS}" -eq 0 ]]; then
    echo "[1/1] Running rclone sync into current/ as a pure mirror..."
    if ! rclone sync "${SOURCE_DIR}/" "${current_path}/" \
      "${RCLONE_EXCLUDES[@]}" \
      --create-empty-src-dirs \
      --fast-list; then
      echo "ERROR: sync-crypt backup failed"
      send_discord_failure "Sync-crypt" "rclone sync failed for ${VOLUME_NAME}"
      exit 1
    fi
  else
    echo "[1/2] Running rclone sync into current/ with backup-dir..."
    if ! rclone sync "${SOURCE_DIR}/" "${current_path}/" \
      "${RCLONE_EXCLUDES[@]}" \
      --backup-dir "${deleted_archive_path}/" \
      --create-empty-src-dirs \
      --fast-list; then
      echo "ERROR: sync-crypt backup failed"
      send_discord_failure "Sync-crypt" "rclone sync failed for ${VOLUME_NAME}"
      exit 1
    fi

    echo "[2/2] Pruning expired deleted-archive paths..."
    cleanup_old_sync_crypt_backups "${sync_remote}"
  fi

  if [[ "${RETENTION_DAYS}" -eq 0 ]]; then
    echo "=================================================="
    echo "Pure sync-crypt mirror completed successfully!"
    echo "Current: ${current_path}"
    echo "=================================================="
    return 0
  fi

  echo "=================================================="
  echo "Sync-crypt backup completed successfully!"
  echo "Current: ${current_path}"
  echo "Deleted archive date bucket: ${deleted_archive_path}"
  echo "=================================================="
}

echo "=================================================="
echo "Starting Filesystem Backup"
echo "=================================================="
echo "Volume: $VOLUME_NAME"
echo "Source: $SOURCE_DIR"
echo "Mode: $BACKUP_MODE"
echo "Timestamp: $TIMESTAMP"
echo "Retention: $RETENTION_DAYS days"
echo "=================================================="

# Validate source directory exists
if [ ! -d "$SOURCE_DIR" ]; then
    echo "ERROR: Source directory not found: $SOURCE_DIR"
    send_discord_failure "Source validation" "Source directory not found: $SOURCE_DIR"
    exit 1
fi

# A directory alone can be an empty container path rather than the intended volume.
if ! awk -v source="$SOURCE_DIR" \
    '$5 == source { found = 1 } END { exit !found }' /proc/self/mountinfo; then
    echo "ERROR: Source directory is not a mount point: $SOURCE_DIR"
    send_discord_failure "Source validation" "Source directory is not a mount point: $SOURCE_DIR"
    exit 1
fi

configure_volume_excludes
validate_romm_sync_source

case "$BACKUP_MODE" in
  archive)
    run_archive_backup
    ;;
  sync-crypt)
    run_sync_crypt_backup
    ;;
  *)
    echo "ERROR: Unsupported backup mode '${BACKUP_MODE}' for volume ${VOLUME_NAME}"
    send_discord_failure "Configuration" "Unsupported backup mode '${BACKUP_MODE}' for ${VOLUME_NAME}"
    exit 1
    ;;
esac
