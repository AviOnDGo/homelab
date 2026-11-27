# Vaultwarden Restore Guide

## Prerequisites

- Docker, Docker Compose, `rclone`, GPG, `zstd`, and `tar`.
- The external `security_network`, a Dropbox rclone remote, and the backup's
  GPG passphrase.
- Enough private temporary disk space for the encrypted download and the
  decrypted staged archive. The script removes these temporary files on exit.
- Schedule downtime and coordinate direct restores with GCP workflows and other
  backups; the GitHub Actions concurrency group does not cover direct runs.

## Restore Steps

### 1. Navigate to Vaultwarden

```bash
cd securityServices/vaultwarden
```

### 2. Run the restore script

```bash
./restore.sh
```

The script prompts for the passphrase and confirmation before stopping the
service or clearing existing data. It downloads the latest matching archive
from `dropbox:/Apps/vaultwarden`, decrypts it into a private staging directory,
and verifies that `db.sqlite3` and `rsa_key.pem` are non-empty regular files
before modifying the volume. Override the remote or path with `DROPBOX_REMOTE`
or `DROPBOX_PATH`. Set `PASSPHRASE` to avoid the passphrase prompt.

For automated setup, `./restore.sh --if-missing` skips an existing volume;
`./restore.sh --force` skips confirmation and replaces existing data. The script
temporarily stops `filedata-backup` if running. It restarts that container after
a successful restore or a failure before changing the volume. After a failure
while changing or verifying the volume, it leaves backups stopped to avoid
uploading incomplete data. Recover and verify Vaultwarden before manually
restarting `filedata-backup`; a subsequent restore does not remember that it
was previously running.

### 3. Clear sensitive shell state

```bash
unset PASSPHRASE
```

## Verification

```bash
docker compose ps
docker exec vaultwarden ls -lh /data/db.sqlite3 /data/rsa_key.pem
```

Confirm that the expected vault data is accessible through Nginx Proxy Manager.

## Troubleshooting

- If archive validation fails, check the backup and passphrase. The existing
  volume is not cleared before validation succeeds.
- If restoration fails after volume changes begin, inspect the service and
  restore from a verified backup before restarting `filedata-backup`.
- If restarting the backup container fails, recover or verify Vaultwarden and
  restart it manually with `docker start filedata-backup`.

## Manual Fallback

Use the scripted workflow above whenever possible. For manual recovery, first
confirm the selected backup is valid and contains both required files; stop
`filedata-backup` if it is running. From `securityServices/vaultwarden`:

```bash
docker compose down
read -r -s -p "GPG passphrase: " PASSPHRASE; echo
rclone lsf dropbox:/Apps/vaultwarden --files-only | grep -E '\.tar\.zst\.gpg$' | sort | tail -n 1
rclone copy "dropbox:/Apps/vaultwarden/<filename>.tar.zst.gpg" .
docker volume inspect vaultwarden_filedata >/dev/null 2>&1 || docker volume create vaultwarden_filedata
docker run --rm -v vaultwarden_filedata:/restore alpine \
  sh -c 'find /restore -mindepth 1 -maxdepth 1 -exec rm -rf {} +'
set -o pipefail
if gpg --batch --yes --pinentry-mode loopback --passphrase-fd 3 \
  -d "<filename>.tar.zst.gpg" 3<<<"$PASSPHRASE" | zstd -d \
  | docker run --rm -i -v vaultwarden_filedata:/restore alpine sh -c 'cd /restore && tar -xf -'; then
  docker compose up -d
else
  echo "Restore failed; keep filedata-backup stopped and recover the volume." >&2
fi
unset PASSPHRASE
```

Verify the restored files and vault data, then restart `filedata-backup` if it
was running before recovery. If extraction fails, leave it stopped.

## GCP Workflow

The [GCP Vaultwarden restore workflow](../../.github/workflows/gcp-vaultwarden-restore.yml)
runs after successful Terraform Apply and NPM restore. It shares a concurrency
group with the NPM, FreshRSS, and Watchtower restore jobs. Every successful
Apply, including a no-op, **forcibly replaces Vaultwarden data** with the
latest backup. Back up current data and schedule downtime before applying.
Manual dispatch skips an existing volume unless `force` is enabled; it requires
an already bootstrapped VM and the workflow on the default branch. The `prod`
environment may require approval.

Configure `DROPBOX_AUTH_TOKEN`, `DROPBOX_REFRESH_TOKEN`, and `GPG_PASSPHRASE`
as `prod` environment or repository secrets. The workflow sends these secrets
over SSH stdin and removes its temporary files on exit. The GPG passphrase must
be a single line. Vaultwarden's service settings come from its Compose file.

Update the GCP workload identity provider to allow the Vaultwarden workflow as
described in the [GCP guide](../../googleCloud/README.md). Direct transport
helper, script, and manual fallback runs are not covered by the workflow
concurrency group; coordinate those manually.
