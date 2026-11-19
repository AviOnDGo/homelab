# Vaultwarden Restore Guide

## Overview

Vaultwarden persists credentials and encryption keys in the `vaultwarden_filedata` volume. Use `restore.sh` as the primary recovery workflow.

## Script-First Recovery

### 1. Run restore script

```bash
cd securityServices/vaultwarden
./restore.sh
```

What the script does:

- Validates required tools (`docker`, `rclone`, `gpg`, `zstd`)
- Prompts for GPG passphrase
- Selects latest `*.tar.zst.gpg` from `dropbox:/Apps/vaultwarden` (or `DROPBOX_PATH` override)
- Prompts before deleting `vaultwarden_filedata`
- Restores archive contents into `vaultwarden_filedata`
- Starts Vaultwarden and verifies `db.sqlite3` and `rsa_key.pem`

Safety behavior:

- If restore fails after shutdown, service is not auto-resumed.

### 2. Verify recovery

```bash
docker compose -f securityServices/vaultwarden/docker-compose.yml ps
docker exec vaultwarden ls -lh /data/db.sqlite3
docker exec vaultwarden ls -lh /data/rsa_key.pem
```

## Manual Fallback Recovery

Use this when scripted recovery cannot be used.

### 1. Stop service

```bash
docker compose -f securityServices/vaultwarden/docker-compose.yml down
```

### 2. Download and restore latest backup

```bash
rclone lsf dropbox:/Apps/vaultwarden --files-only | grep -E '\.tar\.zst\.gpg$' | sort | tail -n 1
rclone copy "dropbox:/Apps/vaultwarden/<filename>.tar.zst.gpg" .
docker volume rm vaultwarden_filedata
docker volume create vaultwarden_filedata
gpg --batch --yes --passphrase "$PASSPHRASE" -d <filename>.tar.zst.gpg | zstd -d \
  | docker run --rm -i -v vaultwarden_filedata:/restore alpine sh -c "cd /restore && tar -xf -"
```

### 3. Start and verify

```bash
docker compose -f securityServices/vaultwarden/docker-compose.yml up -d
docker exec vaultwarden ls -lh /data/db.sqlite3
docker exec vaultwarden ls -lh /data/rsa_key.pem
```

## Notes

- Persistent volume: `vaultwarden_filedata`
- Backup format: `*.tar.zst.gpg`
- Follow service documentation for access path and post-restore login checks
