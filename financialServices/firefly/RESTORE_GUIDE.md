# Firefly III Database Restore Guide

This guide covers automated Firefly PostgreSQL restore using `restore.sh`.

## Prerequisites

- Docker and Docker Compose installed
- Rclone configured with a reachable `dropbox` remote
- GPG passphrase used to encrypt backup files
- Firefly backups present in Dropbox path `/Apps/firefly` (or custom `DROPBOX_PATH`)

## Restore Steps (Script-First)

### 1. Run the restore script

```bash
cd financialServices/firefly
bash restore.sh
```

The script performs:
- Preflight checks (`docker`, `rclone`, `gpg`, `zstd`, Docker daemon)
- Latest backup discovery from Dropbox
- Download + decrypt + import workflow

### 2. Existing volume behavior

If `firefly_postgresdata` already exists, the script prompts:

`Remove and recreate volume? [Y/n]`

- `Y` (default): remove/recreate volume, then restore database
- `n`: keep existing volume and **skip-restore** (starts full stack only)

Important: Option 2 does not import backup data. It only starts the containers.

### 3. Restore target details

- Canonical database container name: `firefly-db`
- Database readiness verification command: `pg_isready -U firefly`
- On success, the script starts full stack with `docker compose up -d`

## Verification

After script completion:

1. Check stack status:
   ```bash
   docker compose ps
   ```
2. Check database readiness:
   ```bash
   docker exec firefly-db pg_isready -U firefly
   ```
3. Review logs if needed:
   ```bash
   docker compose logs -f
   ```

## Failure Behavior

- If Dropbox contains no matching backup files, the script fails immediately.
- If PostgreSQL readiness fails, the script exits non-zero with actionable log hints.
- If skip-restore is selected, the script exits successfully after starting the stack.

## Rollback to Manual Restore

If the script is unavailable or unsuitable:

1. Stop stack:
   ```bash
   docker compose down
   ```
2. Recreate volume and containers as required.
3. Start only DB container:
   ```bash
   docker compose create
   docker start firefly-db
   ```
4. Restore manually:
   ```bash
   gpg --batch --yes --passphrase "$PASSPHRASE" -d /path/to/backup.sql.zst.gpg \
     | zstd -d \
     | docker exec -i firefly-db psql -U firefly -d firefly
   ```
5. Start full stack:
   ```bash
   docker compose up -d
   ```

## Security Note

Unset the passphrase after restore:

```bash
unset PASSPHRASE
```
