#!/bin/sh

# db-backup-script.sh
# Generic PostgreSQL backup script for multiple databases
# Performs backup, encryption, upload, cleanup, and Discord notification
# Usage: ./db-backup-script.sh {database_name}

set -eo pipefail

# Get database name from argument
DB_NAME=${1:-invidious}
DB_NAME_LOWER=$(echo "$DB_NAME" | tr '[:upper:]' '[:lower:]')

# Preserve generated policy before loading environment settings.
case "$DB_NAME_LOWER" in
  invidious) REGISTRY_RETENTION="${DB_BACKUP_INVIDIOUS_RETENTION_DAYS:-}" ;;
  immich) REGISTRY_RETENTION="${DB_BACKUP_IMMICH_RETENTION_DAYS:-}" ;;
  firefly) REGISTRY_RETENTION="${DB_BACKUP_FIREFLY_RETENTION_DAYS:-}" ;;
  paperless) REGISTRY_RETENTION="${DB_BACKUP_PAPERLESS_RETENTION_DAYS:-}" ;;
  firefoxsync) REGISTRY_RETENTION="${DB_BACKUP_FIREFOXSYNC_RETENTION_DAYS:-}" ;;
  romm) REGISTRY_RETENTION="${DB_BACKUP_ROMM_RETENTION_DAYS:-}" ;;
esac

# Source environment variables
[ -f /etc/environment ] && source /etc/environment

# Determine configuration based on database name
case "$DB_NAME_LOWER" in
  invidious)
    DB_HOST="${INVIDIOUS_DB_HOST}"
    DB_USER="${INVIDIOUS_DB_USER}"
    DB_PASSWORD="${INVIDIOUS_DB_PASSWORD}"
    DB_DATABASE="${INVIDIOUS_DB_NAME}"
    BACKUP_NAME="${INVIDIOUS_BACKUP_NAME}"
    DROPBOX_PATH="${INVIDIOUS_DROPBOX_BACKUP_PATH}"
    BACKUP_DIR="/backups/invidious"
    ;;
  immich)
    DB_HOST="${IMMICH_DB_HOST}"
    DB_USER="${IMMICH_DB_USER}"
    DB_PASSWORD="${IMMICH_DB_PASSWORD}"
    DB_DATABASE="${IMMICH_DB_NAME}"
    BACKUP_NAME="${IMMICH_BACKUP_NAME}"
    DROPBOX_PATH="${IMMICH_DROPBOX_BACKUP_PATH}"
    BACKUP_DIR="/backups/immich"
    ;;
  firefly)
    DB_HOST="${FIREFLY_DB_HOST}"
    DB_USER="${FIREFLY_DB_USER}"
    DB_PASSWORD="${FIREFLY_DB_PASSWORD}"
    DB_DATABASE="${FIREFLY_DB_NAME}"
    BACKUP_NAME="${FIREFLY_BACKUP_NAME}"
    DROPBOX_PATH="${FIREFLY_DROPBOX_BACKUP_PATH}"
    BACKUP_DIR="/backups/firefly"
    ;;
  paperless)
    DB_HOST="${PAPERLESS_DB_HOST}"
    DB_USER="${PAPERLESS_DB_USER}"
    DB_PASSWORD="${PAPERLESS_DB_PASSWORD}"
    DB_DATABASE="${PAPERLESS_DB_NAME}"
    BACKUP_NAME="${PAPERLESS_BACKUP_NAME}"
    DROPBOX_PATH="${PAPERLESS_DROPBOX_BACKUP_PATH}"
    BACKUP_DIR="/backups/paperless"
    ;;
  firefoxsync)
    DB_HOST="${FIREFOXSYNC_DB_HOST}"
    DB_USER="${FIREFOXSYNC_DB_USER}"
    DB_PASSWORD="${FIREFOXSYNC_DB_PASSWORD}"
    DB_DATABASE="${FIREFOXSYNC_DB_NAME}"
    BACKUP_NAME="${FIREFOXSYNC_BACKUP_NAME}"
    DROPBOX_PATH="${FIREFOXSYNC_DROPBOX_BACKUP_PATH}"
    BACKUP_DIR="/backups/firefoxsync"
    ;;
  romm)
    DB_HOST="${ROMM_DB_HOST}"
    DB_USER="${ROMM_DB_USER}"
    DB_PASSWORD="${ROMM_DB_PASSWORD}"
    DB_DATABASE="${ROMM_DB_NAME}"
    BACKUP_NAME="${ROMM_BACKUP_NAME}"
    DROPBOX_PATH="${ROMM_DROPBOX_BACKUP_PATH}"
    BACKUP_DIR="/backups/romm"
    ;;
  *)
    echo "❌ Unknown database: $DB_NAME"
    exit 1
    ;;
esac

BACKUP_RETENTION_DAYS="${REGISTRY_RETENTION:-}"
if [ -z "$BACKUP_RETENTION_DAYS" ]; then
  echo "ERROR: No registry retention policy for ${DB_NAME_LOWER} in this profile" >&2
  exit 1
fi

# Load GPG passphrase from secrets if it exists
if [ -f /run/secrets/gpg-passphrase ]; then
  GPG_PASSPHRASE=$(cat /run/secrets/gpg-passphrase)
else
  GPG_PASSPHRASE="${GPG_PASSPHRASE:-}"
fi
if [ -z "$GPG_PASSPHRASE" ]; then
  echo "ERROR: Database backups require a GPG passphrase" >&2
  exit 1
fi

# Variables
TIMESTAMP=$(date +%F_%H-%M-%S)
BACKUP_FILE="${BACKUP_DIR}/${BACKUP_NAME}_${TIMESTAMP}.sql.zst"
BACKUP_FILE_GPG="${BACKUP_FILE}.gpg"
DISCORD_WEBHOOK="${DISCORD_WEBHOOK_URL}"
DROPBOX_AUTH_TOKEN="${DROPBOX_AUTH_TOKEN}"
DROPBOX_REFRESH_TOKEN="${DROPBOX_REFRESH_TOKEN}"
HOST=$(hostname)

# Function to send Discord notification
send_discord_notification() {
  local status=$1
  local message=$2
  local color=$3
  
  if [ -z "$DISCORD_WEBHOOK" ]; then
    return 0
  fi
  
  local payload=$(cat <<EOF
{
  "embeds": [{
    "title": "Database Backup - ${BACKUP_NAME}",
    "description": "${message}",
    "color": ${color},
    "fields": [
      {"name": "Database", "value": "${BACKUP_NAME}", "inline": true},
      {"name": "Status", "value": "${status}", "inline": true},
      {"name": "Timestamp", "value": "${TIMESTAMP}", "inline": true},
      {"name": "Dropbox Path", "value": "${DROPBOX_PATH}", "inline": false},
      {"name": "Host", "value": "${HOST}", "inline": true}
    ],
    "footer": {"text": "Backup System"}
  }]
}
EOF
)
  
  curl -X POST "$DISCORD_WEBHOOK" \
    -H 'Content-Type: application/json' \
    -d "$payload" 2>/dev/null || echo "❌ Discord notification failed"
}

# Function to cleanup old backups
cleanup_old_backups() {
  local backup_path=$1
  local retention_days=$2
  
  # Clean local backups
  echo "🧹 Cleaning local backups older than ${retention_days} days..."
  # Newer backups use zstd-compressed SQL files before encryption -> .sql.zst.gpg
  find "$backup_path" -name "${BACKUP_NAME}_*.sql.zst.gpg" -type f -mtime +${retention_days} -delete 2>/dev/null || true
  
  # Configure rclone if not already done
  if ! rclone config show dropbox >/dev/null 2>&1; then
    mkdir -p /root/.config/rclone
    cat > /root/.config/rclone/rclone.conf <<EOF_RCLONE
[dropbox]
type = dropbox
token = {"access_token":"${DROPBOX_AUTH_TOKEN}","token_type":"bearer","refresh_token":"${DROPBOX_REFRESH_TOKEN}","expiry":"2025-12-12T07:00:17.800842741Z","expires_in":14400}
EOF_RCLONE
  fi
  
  # Clean remote Dropbox backups
  echo "🧹 Cleaning Dropbox backups older than ${retention_days} days..."
  if rclone ls dropbox:${DROPBOX_PATH} >/dev/null 2>&1; then
    rclone ls dropbox:${DROPBOX_PATH} | awk '{print $2}' | while read file; do
      file_date=$(echo "$file" | sed -n 's/^[a-zA-Z0-9_]*_\([0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}\).*/\1/p')
      if [ -n "$file_date" ]; then
        file_epoch=$(date -d "$file_date" +%s 2>/dev/null || echo 0)
        cutoff_epoch=$(($(date +%s) - retention_days * 86400))
        if [ "$file_epoch" -lt "$cutoff_epoch" ]; then
          echo "Deleting: $file"
          rclone delete "dropbox:${DROPBOX_PATH}/${file}" 2>/dev/null || true
        fi
      fi
    done
  fi
}

# Main backup process
main() {
  echo "================================"
  echo "🔄 Starting backup for: $BACKUP_NAME"
  echo "Database: $DB_DATABASE@$DB_HOST"
  echo "Timestamp: $TIMESTAMP"
  echo "================================"
  
  # Check if backup directory exists
  mkdir -p "$BACKUP_DIR"
  
  # Step 1: Dump database
  echo "📦 Dumping database..."
  if ! PGPASSWORD="$DB_PASSWORD" pg_dump \
    -h "$DB_HOST" \
    -U "$DB_USER" \
    -d "$DB_DATABASE" | zstd -6 -T1 -o "$BACKUP_FILE"; then
    send_discord_notification "❌ FAILED" "Database dump failed for ${BACKUP_NAME}" 16711680
    echo "❌ Database dump failed"
    return 1
  fi
  
  # Wait for dump file to be generated and verify it has content
  echo "⏳ Verifying dump file..."
  max_wait=30
  wait_count=0
  while [ ! -f "$BACKUP_FILE" ] || [ ! -s "$BACKUP_FILE" ]; do
    if [ $wait_count -ge $max_wait ]; then
      send_discord_notification "❌ FAILED" "Dump file verification timeout for ${BACKUP_NAME}" 16711680
      echo "❌ Dump file verification failed - file not created or empty"
      return 1
    fi
    wait_count=$((wait_count + 1))
    sleep 1
  done
  
  BACKUP_SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
  echo "✅ Database dumped successfully (${BACKUP_SIZE}) on ${BACKUP_FILE}"
  
  # Step 2: Encrypt with GPG
  echo "🔐 Encrypting backup with GPG..."
  if [ -n "$GPG_PASSPHRASE" ]; then
    if ! echo "$GPG_PASSPHRASE" | gpg --symmetric --cipher-algo AES256 \
      --batch --yes --passphrase-fd 0 \
      -o "$BACKUP_FILE_GPG" "$BACKUP_FILE" 2>/dev/null; then
      send_discord_notification "❌ FAILED" "GPG encryption failed for ${BACKUP_NAME}" 16711680
      echo "❌ GPG encryption failed"
      rm -f "$BACKUP_FILE"
      return 1
    fi
    rm -f "$BACKUP_FILE"
    echo "✅ Backup encrypted successfully"
  else
    BACKUP_FILE_GPG="$BACKUP_FILE"
    echo "⚠️  No GPG passphrase provided, backup stored unencrypted"
  fi
  
  # Step 3: Upload to Dropbox
  echo "☁️  Uploading to Dropbox..."
  
  # Configure rclone
  mkdir -p /root/.config/rclone
  cat > /root/.config/rclone/rclone.conf <<EOF_RCLONE
[dropbox]
type = dropbox
token = {"access_token":"${DROPBOX_AUTH_TOKEN}","token_type":"bearer","refresh_token":"${DROPBOX_REFRESH_TOKEN}","expiry":"2025-12-12T07:00:17.800842741Z","expires_in":14400}
EOF_RCLONE
  
  if rclone copy "$BACKUP_FILE_GPG" "dropbox:${DROPBOX_PATH}/" --progress; then
    echo "✅ Uploaded to Dropbox successfully"
  else
    send_discord_notification "❌ FAILED" "Dropbox upload failed for ${BACKUP_NAME}, backup stored locally" 16711680
    echo "❌ Dropbox upload failed, backup stored locally" >&2
    return 1
  fi
  
  # Step 4: Cleanup old backups
  cleanup_old_backups "$BACKUP_DIR" "$BACKUP_RETENTION_DAYS"
  
  echo "================================"
  echo "✅ Backup completed successfully!"
  echo "================================"
}

# Run main function
main
