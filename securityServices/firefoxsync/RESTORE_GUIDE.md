# Firefox Sync Restore Guide

## Overview

Firefox Sync uses PostgreSQL state stored in the `firefoxsync_postgresdata` volume. The primary recovery path is the scripted workflow in `restore.sh`, which restores the latest Dropbox backup.

## Script-First Recovery

### 1. Run restore script

```bash
cd securityServices/firefoxsync
./restore.sh
```

What the script does:

- Validates required tools (`docker`, `rclone`, `gpg`, `zstd`)
- Prompts for GPG passphrase
- Selects latest `*.sql.zst.gpg` from `dropbox:/Apps/firefoxsync` (or `DROPBOX_PATH` override)
- Prompts before deleting `firefoxsync_postgresdata`
- Restores into database `syncserver` on `firefoxsync-db`
- Verifies PostgreSQL readiness, then starts full stack

Safety behavior:

- If restore fails after shutdown, containers are left down intentionally.

### 2. Verify recovery

```bash
docker compose -f securityServices/firefoxsync/docker-compose.yml ps
docker exec firefoxsync-db pg_isready -U sync -d syncserver
curl -f https://sync.yourdomain.com/__heartbeat__
```

## Manual Fallback Recovery

Use this only if scripted recovery cannot be used.

### 1. Stop stack

```bash
docker compose -f securityServices/firefoxsync/docker-compose.yml down
```

### 2. Download and decrypt latest backup

```bash
rclone lsf dropbox:/Apps/firefoxsync --files-only | grep -E '\.sql\.zst\.gpg$' | sort | tail -n 1
rclone copy "dropbox:/Apps/firefoxsync/<filename>.sql.zst.gpg" .
gpg --batch --yes --passphrase "$PASSPHRASE" -d <filename>.sql.zst.gpg | zstd -d > firefoxsync.sql
```

### 3. Recreate volume and restore DB

```bash
docker volume rm firefoxsync_postgresdata
docker volume create firefoxsync_postgresdata
docker compose -f securityServices/firefoxsync/docker-compose.yml create
docker start firefoxsync-db
docker exec -i firefoxsync-db psql -U sync -d syncserver < firefoxsync.sql
```

### 4. Start stack and verify

```bash
docker compose -f securityServices/firefoxsync/docker-compose.yml up -d
docker exec firefoxsync-db pg_isready -U sync -d syncserver
```

## Notes

- Persistent volume: `firefoxsync_postgresdata`
- Backup format: `*.sql.zst.gpg`
- Recovery access path is via NPM endpoint, not direct host port mapping
