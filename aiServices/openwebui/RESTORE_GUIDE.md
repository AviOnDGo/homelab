# Open WebUI Restore Guide

This guide covers restoring the Open WebUI data volume (`openwebui_filedata`) from a GPG-encrypted backup produced by the filedata backup service (`backupServices/filedata/`).

The `openwebui_filedata` volume stores all user data including accounts, conversations, model settings, and UI configuration.

Open WebUI recovery depends on scheduled filedata backups for this volume.

## Tier C Backup Scope

OpenWebUI backups follow a Tier C policy:

- Included: `webui.db`, `webui.db-wal`, `webui.db-shm`, `uploads/`
- Excluded (rebuildable): `cache/`, `vector_db/`

Core restore readiness is defined by service health plus recoverable account/chat/settings state. RAG/vector index warm-state is intentionally out-of-SLO and may require rebuild time after restore.

## Primary Restore Workflow (Script)

Use the service restore script as the default operator path:

```bash
cd aiServices/openwebui
./restore.sh
```

Optional non-destructive drill mode:

```bash
cd aiServices/openwebui
OPENWEBUI_TARGET_VOLUME=openwebui_restore_drill SKIP_SERVICE_OPS=1 ./restore.sh
```

The script prints per-phase timestamps and reports pass/fail for the core-service restore SLO (10 minutes).

## Prerequisites

- Docker installed
- `aiServices/openwebui/.env` created from `aiServices/openwebui/.env.example`
- Access to a backup file (`.tar.zst.gpg`) from Dropbox or local storage
- GPG passphrase used to encrypt the backup

## Script Restore Steps (What `restore.sh` Does)

1. Preflight checks for required tools (`docker`, `rclone`, `gpg`, `zstd`, `tar`).
2. Prompts for passphrase if `PASSPHRASE` is not already exported.
3. Finds latest backup in Dropbox path (`DROPBOX_PATH`, default `/Apps/openwebui`).
4. Downloads encrypted archive to a temporary directory.
5. Stops OpenWebUI when restoring to production volume (unless `SKIP_SERVICE_OPS=1`).
6. Recreates target volume and restores decrypted contents.
7. Starts OpenWebUI (production mode).
8. Verifies core SQLite files and reports SLO result.

## Restore Steps

### 1. Stop the Open WebUI Container

```bash
docker compose -f aiServices/openwebui/docker-compose.yml down
```

### 2. Set the GPG Passphrase

```bash
export PASSPHRASE=<your_gpg_passphrase_here>
```

### 3. Recreate the Target Volume

If the volume already exists and you want a clean restore, remove it first:

```bash
docker volume rm openwebui_filedata
docker volume create openwebui_filedata
```

If you want to preserve existing data and only restore on top, skip the `rm` step.

### 4. Decrypt and Extract the Backup

Run an alpine container that mounts the target volume and the directory containing the backup file:

```bash
docker run --rm \
  -v openwebui_filedata:/restore \
  -v /path/to/backup/dir:/backup:ro \
  alpine sh -c "
    apk add --no-cache gnupg zstd tar &&
    gpg --batch --yes --passphrase '${PASSPHRASE}' \
        -d /backup/openwebui_<timestamp>.tar.zst.gpg | \
        zstd -dc | tar -xf - -C /restore
  "
```

Replace `/path/to/backup/dir` with the directory containing the `.tar.zst.gpg` file, and `openwebui_<timestamp>` with the actual backup filename.

**Downloading the backup from Dropbox first (if needed):**

```bash
# Using rclone (already configured in the backup service)
docker run --rm \
  -v /path/to/local/dir:/download \
  rclone/rclone copy dropbox:/App_acc/openwebui/openwebui_<timestamp>.tar.zst.gpg /download/
```

### 5. Start Open WebUI

```bash
docker compose -f aiServices/openwebui/docker-compose.yml up -d
```

### 6. Verify

```bash
# Wait for healthy status (~30s)
docker ps --filter name=openwebui --format "{{.Names}}: {{.Status}}"

# Confirm data is present in the volume
docker run --rm -v openwebui_filedata:/data alpine ls /data
```

Access the Open WebUI interface via your NPM hostname and confirm your accounts and conversations are visible.

## Troubleshooting

| Symptom | Action |
|---|---|
| GPG decryption fails | Verify the passphrase (`echo $PASSPHRASE`) and that the backup file is not corrupted |
| Volume data missing after restore | Check the decompression step (`zstd -d | tar -xf`) completed without errors; re-run with `-v` flag for verbose output |
| Container fails to start after restore | Check `docker logs openwebui` for permission or path errors; ensure the volume was created correctly |
| Wrong backup file extracted | List all available backups: `rclone ls dropbox:/App_acc/openwebui/` |

## Rollback To Full-Volume Backup Behavior

If Tier C restore behavior is insufficient for operations, temporarily revert OpenWebUI to full-volume backup behavior:

1. Edit `backupServices/filedata/filedata-backup-script.sh` and remove the OpenWebUI excludes for `cache` and `vector_db`.
2. Run a manual backup:

  ```bash
  docker exec filedata-backup /bin/bash /usr/local/bin/backup-script.sh openwebui
  ```
3. Validate the new archive contains the previously excluded paths before promoting this as an emergency profile.

Keep pre-change backup artifacts until at least one successful Tier C restore drill has been completed and recorded.

## Backup Schedule Reference

Open WebUI data is backed up by the filedata backup service on the schedule defined by `OPENWEBUI_CRON_SCHEDULE` in `backupServices/filedata/.env`. Backups are retained for `OPENWEBUI_RETENTION_DAYS` days (default: 14).

To trigger a manual backup immediately:

```bash
docker exec filedata-backup /bin/bash /usr/local/bin/backup-script.sh openwebui
```
