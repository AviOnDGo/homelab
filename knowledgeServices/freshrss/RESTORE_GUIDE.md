# FreshRSS Restore Guide

## Prerequisites

- Docker, Docker Compose with `up --wait --wait-timeout`, `rclone`, GPG,
  `zstd`, and `tar` on the host.
- `flock` is also needed for the manual fallback.
- The external `knowledge_network` network and access to a Dropbox rclone remote.
- The GPG passphrase used for the filedata backup.
- For GCP: SSH access through GCP, the workflow's GCP OIDC variables and the
  Actions secrets `DROPBOX_AUTH_TOKEN`,
  `DROPBOX_REFRESH_TOKEN`, and `GPG_PASSPHRASE`.
  The GCP OIDC trust policy must allow the FreshRSS restore workflow as
  described in the [GCP guide](../../googleCloud/README.md).

## Restore Steps

### 1. Navigate to FreshRSS

```bash
cd knowledgeServices/freshrss
```

### 2. Run the restore script

```bash
./restore.sh
```

The script prompts for the passphrase and confirmation before removing an
existing FreshRSS container or clearing its volume. Alternatively, supply
`PASSPHRASE` and `DROPBOX_PATH` as environment variables. For noninteractive
restores, use `--force` to replace existing data, or `--if-missing` to skip an
existing volume. `--if-missing` refuses to remove an existing FreshRSS container
if the volume is absent.

The script downloads and validates the latest matching `.tar.zst.gpg` archive
before stopping anything, stops `filedata-backup` only if it was running, clears
the existing volume in place, restores the archive, and waits up to 300 seconds
for Docker Compose to report FreshRSS healthy. On success or failure, it
attempts to restart `filedata-backup` if it was running. If restarting it fails,
restart it manually; the script does not retain its prior state for the next attempt.

The script does not lock against concurrent restores. Do not run it or the manual
fallback while another restore is in progress. If an older version left a
`freshrss-restore-backup-state` marker in `${TMPDIR:-/tmp}`, check and restore
the backup container's state manually, then remove the marker.

The [GCP restore workflow](../../.github/workflows/gcp-freshrss-restore.yml)
runs after successful Terraform Apply, including no-op applies, and **forcibly
replaces FreshRSS data** with the latest `/Apps/freshrss` backup. Back up
current data and schedule downtime before applying. It runs only after the NPM
restore succeeds; if NPM fails or is skipped, FreshRSS is skipped too.
Manual dispatch skips an existing volume unless `force` is enabled. GitHub
requires the workflow on the default branch for manual dispatch; the `prod`
environment and OIDC trust policy must allow the selected branch. The separate
restore job may require `prod` approval. Manual runs require a bootstrapped VM.

The workflow uses `GCP_VM_NAME` (default `gcp-debian-free-tier-vm`), transfers
the selected checkout's restore script and Compose file to a temporary VM
directory, and installs `rclone` and `zstd` if needed. Credentials travel over
SSH standard input; temporary files are removed on exit. The passphrase must be
a single line. Avoid shell tracing. The workflow no longer accepts `vm_name`
or `dropbox_path` inputs or sends Discord notifications. Use the script directly
for an alternative Dropbox path. GCP service restore jobs share a GitHub Actions
concurrency group, but direct transport helper, script, and manual fallback runs
are not covered. Coordinate those manually to prevent overlapping restores and
partial backups.

### 3. Clear sensitive shell state

```bash
unset PASSPHRASE
```

## Verification

```bash
docker compose ps
docker inspect -f '{{.State.Health.Status}}' freshrss
docker logs --tail 50 freshrss
```

Confirm that FreshRSS serves the expected data through Nginx Proxy Manager.

## Troubleshooting

- If listing or downloading fails, verify the Dropbox remote, credentials and path.
  No container is stopped before the download completes.
- If the restore fails after `filedata-backup` is stopped, the script attempts to
  return it to its prior running state. If that restart fails, inspect the logs,
  and start `filedata-backup` manually.
- If health checks fail, inspect `docker compose logs freshrss` and keep FreshRSS
  stopped until the restored data has been checked.

## Manual fallback

Run the following in Bash to validate the archive, stop FreshRSS and a running
`filedata-backup`, and restore the existing volume:

```bash
(
set -euo pipefail
BACKUP=/path/to/backup.tar.zst.gpg
read -r -s -p "GPG passphrase: " PASSPHRASE
printf '\n'
trap 'unset PASSPHRASE' EXIT
gpg --batch --yes --pinentry-mode loopback --passphrase-fd 3 -d "$BACKUP" 3<<<"$PASSPHRASE" \
  | zstd -d | tar -tf - >/dev/null
if [[ ! -e /tmp/freshrss-restore.lock ]]; then
  (umask 022; : >> /tmp/freshrss-restore.lock)
fi
exec 9</tmp/freshrss-restore.lock
if ! flock -n 9; then
  printf 'Another FreshRSS restore is already in progress.\n' >&2
  exit 1
fi
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
)
```

The archive is decrypted and checked before `docker compose down` or volume
cleanup. The lock prevents overlapping manual fallback runs but does not
coordinate with `restore.sh`. With `set -euo pipefail`, a failed command or
pipeline stops the sequence before FreshRSS is started. The subshell's EXIT trap
clears the passphrase and restores `filedata-backup` if it was running.
