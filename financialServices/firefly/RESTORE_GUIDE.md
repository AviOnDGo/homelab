# Firefly III Database Restore Guide

## Prerequisites

- Docker and Docker Compose with `up --wait`, `rclone`, GPG, and `zstd`.
- Access to `finance_network`, a configured `dropbox` rclone remote, and a
  Firefly database backup in `/Apps/firefly`. Set `DROPBOX_REMOTE` or
  `DROPBOX_PATH` to use another remote or path.
- The original Firefly `APP_KEY`, database credentials, and a 32-character
  alphanumeric `STATIC_CRON_TOKEN` available to Compose. See
  [SERVICE_DOCUMENTATION.md](SERVICE_DOCUMENTATION.md).
- The GPG passphrase and sufficient private temporary disk space for both the
  encrypted backup and its uncompressed SQL dump.
- A separate, verified backup of the current database before replacing it.
  Schedule downtime and coordinate direct restores and backup jobs manually;
  the script does not lock against concurrent runs.

## Restore Steps

### 1. Navigate to Firefly

```bash
cd financialServices/firefly
```

### 2. Run the restore script

```bash
./restore.sh
```

The script prompts for the passphrase and, if Firefly data or containers
already exist, confirmation before replacement. Non-interactive alternatives:

- `./restore.sh --if-missing` skips an existing database volume and refuses to
  restore if Firefly containers exist without that volume.
- `./restore.sh --force` replaces existing data without confirmation.

The script selects the newest `firefly_YYYY-MM-DD_HH-MM-SS.sql.zst.gpg` dump
and validates its GPG, zstd, and PostgreSQL dump markers before stopping anything.
It stages the decrypted SQL in a private temporary directory and removes it on exit. It
stops `db-backup` if running, stops the Firefly Compose project, checks for
other running users of the volume, clears the volume in place, imports the dump,
and waits up to 600 seconds for the stack's health checks. The application
health check has a 240-second startup grace period. A health check failure
after startup still fails the restore. It uses the database container's
configured PostgreSQL user and database name. PostgreSQL readiness is checked
over TCP so the temporary initialization server is not mistaken for the final
server.

For GCP, the **Restore Firefly on GCP VM** GitHub Actions workflow runs the
same script. A manual run skips an existing database volume by default; enable
`force` to replace it. The GCP deployment workflow forces a restore after every
successful apply and NPM restore, even for a no-op apply. Before applying,
schedule downtime and verify a current backup. Configure the required
credentials and WIF trust as described in the
[GCP deployment guide](../../googleCloud/README.md).
Manual runs require `finance_network` to exist; the NPM deployment creates it.
Workflow concurrency does not prevent direct restore or backup operations.

### 3. Clear sensitive shell state

If you supplied the passphrase in your shell:

```bash
unset PASSPHRASE
```

## Verification

```bash
docker compose ps
docker exec firefly-db sh -c 'pg_isready -h 127.0.0.1 -U "$POSTGRES_USER" -d "$POSTGRES_DB"'
docker logs --tail 100 firefly
```

Sign in through the proxy and verify the expected accounts, transactions, and
other data. Database and application health do not prove the backup is current.

## Troubleshooting

- A failed download, decryption, or dump validation leaves existing data intact.
- If a failure occurs after volume clearing begins, the script leaves a
  previously running `db-backup` stopped to avoid backing up incomplete data.
  Recover the database, verify it, and restart `db-backup` manually. A later
  `--if-missing` run will skip the existing volume; use a deliberate `--force`
  retry after reviewing the failure.
- If a container from another Compose project still exists, or another running
  container uses the database volume, the script refuses to clear it. Resolve
  the conflict before retrying.
- If the app fails its health check, inspect `docker compose logs` and confirm
  the original `APP_KEY`, database credentials, and network are correct.
- If restarting `db-backup` fails after a successful restore, the script reports
  failure; start it manually after checking the restored service.

## Manual fallback

This replaces the database. Coordinate with other backup and restore operations,
and verify the backup before proceeding. The following assumes `db-backup` was
running; if it was already stopped or absent, omit both its stop and start.
Run in Bash from the Firefly service directory:

```bash
(
set -euo pipefail
umask 077
BACKUP=/path/to/firefly_backup.sql.zst.gpg
WORKDIR=$(mktemp -d)
trap 'rm -rf -- "$WORKDIR"; unset PASSPHRASE' EXIT
read -r -s -p "GPG passphrase: " PASSPHRASE
printf '\n'
gpg --batch --yes --pinentry-mode loopback --passphrase-fd 3 -d "$BACKUP" \
  3<<<"$PASSPHRASE" | zstd -d > "$WORKDIR/backup.sql"
grep -Fxq -- '-- PostgreSQL database dump' "$WORKDIR/backup.sql"
grep -Fxq -- '-- PostgreSQL database dump complete' "$WORKDIR/backup.sql"
docker stop db-backup
docker compose down
if [[ -n "$(docker ps -q --filter volume=firefly_postgresdata)" ]]; then
  echo "Another running container uses the database volume; aborting." >&2
  exit 1
fi
docker volume inspect firefly_postgresdata >/dev/null \
  || docker volume create firefly_postgresdata
docker run --rm -v firefly_postgresdata:/restore alpine \
  sh -c 'find /restore -mindepth 1 -maxdepth 1 -exec rm -rf {} +'
docker compose create
docker start firefly-db
ready=false
for ((i = 1; i <= 60; i++)); do
  if docker exec firefly-db sh -c 'pg_isready -h 127.0.0.1 -U "$POSTGRES_USER" -d "$POSTGRES_DB"'; then
    ready=true
    break
  fi
  sleep 1
done
[[ "$ready" == true ]] || { echo "PostgreSQL is not ready." >&2; exit 1; }
docker exec -i firefly-db sh -c \
  'exec psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB"' < "$WORKDIR/backup.sql"
docker exec firefly-db sh -c \
  'exec psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT 1 FROM public.transactions LIMIT 0"'
docker compose up -d --wait --wait-timeout 600
docker start db-backup
)
```

On failure after `db-backup` is stopped, it remains stopped. Recover and verify
Firefly before restarting it. The temporary plaintext dump is removed on exit.
