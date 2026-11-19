# Pi-hole Restore Guide

## Overview

Pi-hole stores persistent DNS state in the `pihole_filedata` volume. Use `restore.sh` as the primary recovery path.

## Script-First Recovery

### 1. Run restore script

```bash
cd securityServices/pihole
./restore.sh
```

What the script does:

- Validates required tools (`docker`, `rclone`, `gpg`, `zstd`)
- Prompts for GPG passphrase
- Selects latest `*.tar.zst.gpg` from `dropbox:/Apps/pihole` (or `DROPBOX_PATH` override)
- Prompts before deleting `pihole_filedata`
- Restores archive contents into `pihole_filedata`
- Starts Pi-hole and verifies `gravity.db` and `pihole-FTL.db`

Safety behavior:

- If restore fails after service shutdown, recovery is not auto-resumed.

### 2. Verify recovery

```bash
docker compose -f securityServices/pihole/docker-compose.yml ps
docker exec pihole ls -lh /etc/pihole/gravity.db
docker exec pihole ls -lh /etc/pihole/pihole-FTL.db
nslookup google.com 127.0.0.1
```

## Manual Fallback Recovery

Use this when scripted recovery cannot be used.

### 1. Stop service

```bash
docker compose -f securityServices/pihole/docker-compose.yml down
```

### 2. Download and restore latest backup

```bash
rclone lsf dropbox:/Apps/pihole --files-only | grep -E '\.tar\.zst\.gpg$' | sort | tail -n 1
rclone copy "dropbox:/Apps/pihole/<filename>.tar.zst.gpg" .
docker volume rm pihole_filedata
docker volume create pihole_filedata
gpg --batch --yes --passphrase "$PASSPHRASE" -d <filename>.tar.zst.gpg | zstd -d \
  | docker run --rm -i -v pihole_filedata:/restore alpine sh -c "cd /restore && tar -xf -"
```

### 3. Start and verify

```bash
docker compose -f securityServices/pihole/docker-compose.yml up -d
docker exec pihole ls -lh /etc/pihole/gravity.db
docker exec pihole ls -lh /etc/pihole/pihole-FTL.db
```

## Notes

- Persistent volume: `pihole_filedata`
- Backup format: `*.tar.zst.gpg`
- Web admin access path and DNS behavior are documented in `SERVICE_DOCUMENTATION.md`
