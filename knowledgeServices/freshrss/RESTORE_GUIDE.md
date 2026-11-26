# FreshRSS Restore Guide

## Prerequisites

- Docker, Docker Compose, `rclone`, GPG, `zstd`, and `flock` on the host.
- The external `knowledge_network` network and access to a Dropbox rclone remote.
- The GPG passphrase used for the filedata backup.
- For GCP: an existing checkout at `/tmp/homelab`, SSH access through GCP, the
  workflow's GCP OIDC variables and the Actions secrets `DROPBOX_AUTH_TOKEN`,
  `DROPBOX_REFRESH_TOKEN`, and `GPG_PASSPHRASE`.

The GCP bootstrap clone is optional and is not automatically refreshed. Install
`rclone` and `zstd` on the VM if needed, and update the checkout separately before
running the workflow. Its `restore.sh` must match the workflow's checkout; the
workflow checks the script hash and fails before restoring if it differs.

## Restore Steps

### 1. Navigate to FreshRSS

```bash
cd knowledgeServices/freshrss
```

### 2. Run the restore script

```bash
./restore.sh
```

The script prompts for the passphrase and confirmation before stopping FreshRSS
or clearing its volume. Alternatively, supply `PASSPHRASE` and `DROPBOX_PATH` as
environment variables. It downloads and validates the latest matching `.tar.zst.gpg` archive before
stopping anything, stops `filedata-backup` only if it was running, clears the
existing volume in place, restores the archive, starts FreshRSS and checks its
health. On success or failure, it attempts to restore `filedata-backup` to its
prior state. If restarting it fails, the saved state is retained for the next
restore attempt.

For GCP, dispatch `.github/workflows/gcp-freshrss-restore.yml` and approve the
pending deployment in GitHub Actions. The `prod` environment must have required
reviewers configured; its approval rule also applies to GCP deployment jobs.
The optional `vm_name` overrides
`GCP_VM_NAME` (default `gcp-debian-free-tier-vm`); `dropbox_path` defaults to
`/Apps/freshrss`. The workflow connects to the live VM and invokes its script
non-interactively with the Actions secrets, supplies confirmation to the script
after GitHub approval, and uses a temporary, private rclone
configuration that is removed on exit. It does not update the VM checkout. An optional
`DISCORD_WEBHOOK_URL` secret enables best-effort outcome notifications.

### 3. Clear sensitive shell state

```bash
unset PASSPHRASE
```

## Verification

```bash
docker compose ps
docker exec freshrss php /var/www/FreshRSS/cli/health.php
docker logs --tail 50 freshrss
```

Confirm that FreshRSS serves the expected data through Nginx Proxy Manager.

## Troubleshooting

- If listing or downloading fails, verify the Dropbox remote, credentials and path.
  No container is stopped before the download completes.
- If the restore fails after `filedata-backup` is stopped, the script attempts to
  return it to its prior running state. If that restart fails, inspect the logs,
  rerun the restore to retry the restart, or start `filedata-backup` manually.
- If health checks fail, inspect `docker compose logs freshrss` and keep FreshRSS
  stopped until the restored data has been checked.

## Manual fallback

Stop FreshRSS and any backup container using its volume, then restore a verified
archive into the existing volume:

```bash
set -euo pipefail
BACKUP=/path/to/backup.tar.zst.gpg
read -r -s -p "GPG passphrase: " PASSPHRASE
printf '\n'
trap 'unset PASSPHRASE' EXIT
gpg --batch --yes --pinentry-mode loopback --passphrase-fd 3 -d "$BACKUP" 3<<<"$PASSPHRASE" \
  | zstd -d | tar -tf - >/dev/null
BACKUP_WAS_RUNNING=false
restore_backup_state() {
  local exit_status=$?
  trap - EXIT
  if [[ "$BACKUP_WAS_RUNNING" == "true" ]] \
    && [[ "$(docker inspect -f '{{.State.Running}}' filedata-backup 2>/dev/null || true)" != "true" ]] \
    && ! docker start filedata-backup >/dev/null; then
    printf 'Could not restart filedata-backup.\n' >&2
    exit_status=1
  fi
  unset PASSPHRASE
  exit "$exit_status"
}
trap restore_backup_state EXIT
if [[ "$(docker inspect -f '{{.State.Running}}' filedata-backup 2>/dev/null || true)" == "true" ]]; then
  BACKUP_WAS_RUNNING=true
  docker stop filedata-backup >/dev/null
fi
docker compose down
docker volume inspect freshrss_filedata >/dev/null || docker volume create freshrss_filedata
docker run --rm -v freshrss_filedata:/restore alpine \
  sh -c 'find /restore -mindepth 1 -maxdepth 1 -exec rm -rf {} +'
gpg --batch --yes --pinentry-mode loopback --passphrase-fd 3 -d "$BACKUP" 3<<<"$PASSPHRASE" \
  | zstd -d | docker run --rm -i -v freshrss_filedata:/restore alpine \
    sh -c 'cd /restore && tar -xf -'
docker compose up -d
```

The archive is decrypted and checked before `docker compose down` or volume
cleanup. With `set -euo pipefail`, a failed command or pipeline stops the
sequence before FreshRSS is started. The EXIT trap clears the passphrase from
the shell on success or failure and restores `filedata-backup` if it was running.
