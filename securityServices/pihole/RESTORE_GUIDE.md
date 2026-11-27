# Pi-hole Restore Guide

## Overview

Pi-hole stores persistent DNS state in the `pihole_filedata` volume. Use `restore.sh` as the primary recovery path.

Run the commands below from the repository root. Set `WEB_PASSWORD` in the Pi-hole
`.env` file or export it in the environment before restoring.

## Script-First Recovery

### 1. Run restore script

```bash
(cd securityServices/pihole && ./restore.sh)
```

What the script does:

- Validates required tools (`docker`, `rclone`, `gpg`, `zstd`, and `tar`)
- Prompts for GPG passphrase
- Selects latest `*.tar.zst.gpg` from `dropbox:/Apps/pihole` (or `DROPBOX_PATH` override)
- Extracts the archive to a private temporary directory and checks both SQLite databases
  before changing existing data; allow sufficient temporary space for the extracted backup
- Uses the Compose-configured Pi-hole image for database checks, downloading it if needed
- Prompts before deleting `pihole_filedata`
- Restores archive contents into `pihole_filedata`
- Starts Pi-hole and verifies the integrity of `gravity.db` and `pihole-FTL.db`

Safety behavior:

- If restore fails after service shutdown, recovery is not auto-resumed.

For GCP, the **Restore Pi-hole on GCP VM** workflow skips an existing volume by
default; enable `force` to replace it. The deployment workflow forces a restore
after every successful apply and NPM restore, including no-op applies. Schedule
DNS downtime and verify the backup before applying. Configure the required
secrets and WIF trust as described in the [GCP guide](../../googleCloud/README.md).
Before restoration, the workflow replaces `/etc/resolv.conf` with a copy of
its current contents, then stops and disables `systemd-resolved` to free
port 53. Ensure the current resolver configuration contains reachable upstream
servers, not only local systemd-resolved stub addresses. The copy is static;
DHCP or other host network managers can later replace it or change DNS settings.
The VM needs `security_network` and available TCP/UDP port 53. Restrict DNS
access to authorized clients; do not expose an open resolver. Workflow
concurrency does not protect direct restore or backup operations.

After the workflow is available on the default branch, start a non-forced run
with `gh workflow run gcp-pihole-restore.yml --ref main`.

If a restore fails after volume replacement starts, a previously running
`filedata-backup` remains stopped to protect the backup history. Recover and
verify Pi-hole data before manually restarting it with
`docker start filedata-backup`. A non-forced run skips an existing volume.
If the backup scheduler was created while `pihole_filedata` was missing, rerun
the GCP filedata backup workflow after Pi-hole is recovered so its generated
mounts and schedule include Pi-hole.

### 2. Verify recovery

```bash
(cd securityServices/pihole && docker compose ps)
docker exec pihole pihole-FTL /etc/pihole/gravity.db 'PRAGMA integrity_check;'
docker exec pihole pihole-FTL /etc/pihole/pihole-FTL.db 'PRAGMA integrity_check;'
nslookup google.com 127.0.0.1
```

## Manual Fallback Recovery

Use this when scripted recovery cannot be used.

### 1. Stop service

```bash
(cd securityServices/pihole && docker compose down)
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
(cd securityServices/pihole && docker compose up -d)
docker exec pihole pihole-FTL /etc/pihole/gravity.db 'PRAGMA integrity_check;'
docker exec pihole pihole-FTL /etc/pihole/pihole-FTL.db 'PRAGMA integrity_check;'
```

## Notes

- Persistent volume: `pihole_filedata`
- Backup format: `*.tar.zst.gpg`
- Web admin access path and DNS behavior are documented in `SERVICE_DOCUMENTATION.md`
