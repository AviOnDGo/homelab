# RomM Restore Guide

This guide restores RomM's `romm_filedata` volume from Filen and the
`romm_postgresdata` volume from the Local PostgreSQL backup in Dropbox.

## Prerequisites

- Docker and Docker Compose installed and connected to the expected daemon
- `rclone`, `gpg`, and `zstd` available on the host
- Host rclone configured with a reachable `dropbox` remote
- `backupServices/filedata/.env` configured with `FILEN_EMAIL`,
  `FILEN_PASSWORD`, `FILEN_API_KEY`, `RCLONE_CRYPT_PASSWORD`, and
  `ROMM_SYNC_CRYPT_REMOTE`
- Filen filedata present at `filen-crypt:/Romm/current`
- RomM PostgreSQL backups present at `dropbox:/App_acc/romm` (or custom
  `DROPBOX_PATH`), produced by the Local `db-backup` deployment
- The GPG passphrase used to encrypt the PostgreSQL backup

## Restore Steps

### 1. Navigate to the service directory and stop the stack

```bash
cd gamingServices/romm
docker compose down
```

### 2. Set the GPG passphrase

```bash
read -r -s -p "Enter GPG passphrase: " PASSPHRASE
export PASSPHRASE
```

### 3. Restore filedata and PostgreSQL

```bash
./restore.sh
```

The script prompts before replacing existing RomM data. It creates
`romm_filedata` if needed, synchronizes Filen's `current/` tree into that volume,
creates the containers without starting them, starts only `romm-db`, restores the
latest encrypted PostgreSQL dump, then starts RomM and the Local filedata backup
service. Before importing the dump, it waits up to 60 readiness attempts for
PostgreSQL's final TCP listener at `127.0.0.1`, not its temporary socket-only
initialization server. It then connects to the `postgres` maintenance database
as `DB_USER`, checks for `DB_NAME`, and creates the target database if absent.
Lookup or creation errors stop recovery before SQL import.

### 4. Start all services

The restore script starts the RomM stack and filedata backup service. If either
was stopped after the script completed, start it with:

```bash
docker compose up -d
cd ../../backupServices/filedata
docker compose -f docker-compose.local.yml up -d filedata-backup
```

### 5. Cleanup sensitive shell state

```bash
unset PASSPHRASE
```

## Verification

1. Check stack status and database health:
   ```bash
   cd gamingServices/romm
   docker compose ps
   docker inspect --format='{{.State.Health.Status}}' romm-db
   ```
2. Confirm the named volume contains both expected directories:
   ```bash
   docker run --rm --mount type=volume,source=romm_filedata,target=/restore,readonly \
     alpine:3.24.3 sh -ec 'test -d /restore/library && test -d /restore/assets'
   ```
3. Open RomM via its NPM proxy URL and confirm the restored metadata, users,
   library entries, assets, saves, and states are visible. Review logs if needed:
   ```bash
   docker compose logs -f romm
   ```

## Troubleshooting

- **No PostgreSQL backup found**: verify `dropbox:/App_acc/romm` contains a
  `romm_*.sql.zst.gpg` file and check with `rclone lsf`.
- **Filen authentication fails**: verify the three Filen credentials in the
  filedata `.env`; after a Filen password change, export a fresh API key.
- **Filen sync fails**: verify `ROMM_SYNC_CRYPT_REMOTE` and
  `RCLONE_CRYPT_PASSWORD`; inspect the restore command's Docker output.
- **GPG decryption fails**: verify the passphrase and backup file integrity.
- **`romm-db` never becomes healthy**: inspect `docker logs romm-db`; verify
  `DB_NAME`, `DB_USER`, and `DB_PASSWD` are present in RomM's `.env`.
- **Database check reports `the database system is shutting down`**: use the
  updated restore script, which waits for PostgreSQL's final TCP listener rather
  than the temporary socket-only server used during initialization.
- **PostgreSQL reports `database "romm" does not exist`**: the restore script
  checks for the configured database and creates it before importing the dump.
  If this persists, verify `DB_NAME` and `DB_USER` match the RomM `.env`.
- **Database check reports `syntax error at or near ":"`**: use the updated
  restore script, which sends the lookup SQL through stdin so psql expands
  the database-name variable. Database creation explicitly connects to `postgres`.
- **Library appears stale**: confirm the `romm_filedata` volume contains
  `library/` and `assets/`, then trigger a manual library rescan in RomM.

## Optional: Manual Restore Fallback

Stop RomM and the filedata backup container first. From the repository root,
build the helper image and sync the Filen backup into the named volume:

```bash
docker build -t homelab/filedata-backup:local backupServices/filedata
docker run --rm --env-file backupServices/filedata/.env \
  --mount type=volume,source=romm_filedata,target=/restore \
  --entrypoint /bin/bash homelab/filedata-backup:local -ec '
    /usr/local/bin/configure-rclone.sh
    remote="${ROMM_SYNC_CRYPT_REMOTE:?ROMM_SYNC_CRYPT_REMOTE is required}"
    rclone sync "${remote%/}/current/" /restore/ --create-empty-src-dirs --fast-list
  '
```

For the database steps, return to `gamingServices/romm` from the repository root.
Enter the configured database user and name (normally both `romm`); do not source
the service environment file into the shell. Keep `PASSPHRASE` set as in step 2.

```bash
cd gamingServices/romm
read -r -p "Configured DB_USER: " DB_USER
read -r -p "Configured DB_NAME: " DB_NAME
: "${DB_USER:?Database user is required}" "${DB_NAME:?Database name is required}"
rclone lsf dropbox:/App_acc/romm --files-only | grep -E '^romm_.*\.sql\.zst\.gpg$' | sort | tail -n 1
rclone copy "dropbox:/App_acc/romm/<filename>.sql.zst.gpg" .
docker compose create
docker start romm-db

ready=false
for ((i = 1; i <= 60; i++)); do
  if docker exec romm-db pg_isready -h 127.0.0.1 -U "$DB_USER" -d postgres; then
    ready=true
    break
  fi
  sleep 1
done
if [[ "$ready" != true ]]; then
  echo "PostgreSQL did not become ready; inspect docker logs romm-db." >&2
  exit 1
fi

database_exists="$(docker exec -i romm-db psql -X -U "$DB_USER" -d postgres \
  --set=ON_ERROR_STOP=1 --set="db_name=$DB_NAME" --tuples-only --no-align <<'SQL'
SELECT 1 FROM pg_database WHERE datname = :'db_name';
SQL
)" || exit 1
if [[ "$database_exists" != "1" ]]; then
  docker exec romm-db createdb -U "$DB_USER" --maintenance-db=postgres "$DB_NAME" \
    || exit 1
fi

set -o pipefail
gpg --batch --yes --passphrase "$PASSPHRASE" -d <filename>.sql.zst.gpg \
  | zstd -d \
  | docker exec -i romm-db psql -U "$DB_USER" -d "$DB_NAME" \
  || exit 1
docker compose up -d
unset PASSPHRASE
```
