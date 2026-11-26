# Vaultwarden Restore Guide

## Overview

Vaultwarden persists credentials and encryption keys in the `vaultwarden_filedata` volume. Use `restore.sh` as the primary recovery workflow.

## Script-First Recovery

### 1. Run restore script

```bash
cd securityServices/vaultwarden
./restore.sh
```

For automated setup, `./restore.sh --if-missing` restores only when
`vaultwarden_filedata` does not exist. It still prompts for the GPG passphrase
unless `PASSPHRASE` is already set. Use `./restore.sh --force` to skip
confirmation prompts when intentionally replacing existing data.

What the script does:

- Validates required tools (`docker`, `rclone`, `gpg`, `zstd`, `tar`)
- Prompts for a GPG passphrase, or uses `PASSPHRASE` if already set
- Selects the latest matching Vaultwarden archive from `dropbox:/Apps/vaultwarden`
  (or `DROPBOX_REMOTE` / `DROPBOX_PATH` overrides)
- Downloads and validates the archive before changing the service
- Prompts before deleting `vaultwarden_filedata`
- Stops and restarts `filedata-backup` if it was running during the restore
- Restores archive contents into `vaultwarden_filedata`
- Starts Vaultwarden and verifies `db.sqlite3` and `rsa_key.pem`

Safety behavior:

- If restore fails after shutdown, service is not auto-resumed.

### GCP workflow

The [GCP Vaultwarden restore workflow](../../.github/workflows/gcp-vaultwarden-restore.yml)
runs after successful Terraform Apply and NPM restore. It shares a concurrency
group with the NPM, FreshRSS, and Watchtower restore jobs. Every successful
Apply, including a no-op, **forcibly replaces
Vaultwarden data** with the latest backup. Back up current data and schedule
downtime before applying. Manual dispatch skips an existing volume unless
`force` is enabled; it requires an already bootstrapped VM and the workflow on
the default branch. The `prod` environment may require approval.

Configure `DROPBOX_AUTH_TOKEN`, `DROPBOX_REFRESH_TOKEN`, and `GPG_PASSPHRASE`
as `prod` environment or repository secrets. The workflow sends these secrets
over SSH stdin and removes its temporary files on exit. The GPG passphrase must
be a single line. Vaultwarden's service settings come from its Compose file.

Update the GCP workload identity provider to allow the Vaultwarden workflow as
described in the [GCP guide](../../googleCloud/README.md). Direct transport
helper, script, and manual fallback runs are not covered by the workflow
concurrency group; coordinate those manually.

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
