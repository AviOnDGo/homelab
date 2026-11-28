# Immich Restore Guide

The primary recovery path is `./restore.sh`: it restores the three original-file
volumes from Mega crypt mirrors and the PostgreSQL dump from Dropbox. The lanes
are not an atomic snapshot and can represent different points in time.

## Prerequisites

- Docker with Compose, `gpg`, and `zstd` on the host; the `media_network`
  network and `immich_model_cache` volume must exist.
- The `homelab/db-backup:local` image, built from `backupServices/postgres/`,
  supplies a PostgreSQL 19 client compatible with the backup's dump format.
- A running `filedata-backup` container with working `dropbox`, `mega`, and
  `mega-crypt` remotes configured using the original backup credentials.
  The script uses container rclone, not the host configuration.
- The service environment configured with the same database user and database
  name as the backup, and an Immich version compatible with the backup.
- Enough free space for **two temporary copies** of the decrypted filedata:
  one in the backup container and one under the host's `/tmp`, plus the dump.
  These temporary files contain unencrypted personal data.

Default sources are `mega-crypt:/App_acc/immich-library/current/`,
`mega-crypt:/App_acc/immich-profile/current/`,
`mega-crypt:/App_acc/immich-upload/current/`, and
`dropbox:/App_acc/immich/immich_YYYY-MM-DD_HH-MM-SS.sql.zst.gpg`.
For production set `IMMICH_REMOTE_ROOT=/Apps` and `DROPBOX_PATH=/Apps/immich`.
Check the database destination in
[`path.local`](../../backupServices/postgres/path.local) or
[`path.prod`](../../backupServices/postgres/path.prod) and set `DROPBOX_PATH`
if it differs from the restore default.
`MEGA_CRYPT_REMOTE` and `DROPBOX_REMOTE` can select other existing container
remotes; the Mega backend must still be named `mega`.

**Important:** Do not start scheduled backups against new empty volumes if
recovering existing data: sync can replace the remote mirror with the empty
state. Disable the Immich jobs until the restored data is verified.

## Restore Steps

### 1. Enter the service directory and stop Immich

```bash
cd mediaServices/immich
docker compose down
```

### 2. Check the backup sources

```bash
./restore.sh --check-only
```

The check verifies access to all three remotes, inspects each mirror, and finds
the latest timestamped database dump without changing volumes. Some valid
Immich folders can be empty, especially on a fresh installation. An empty
mirror is indistinguishable from a missing path in some cloud backends. Only
after independently confirming that *each* reported empty path is genuinely
empty and the crypt credentials and paths are correct, set
`ALLOW_EMPTY_MIRRORS=true` for both the check and restore. Otherwise recovery
could erase a populated volume.

### 3. Set the GPG passphrase and run the restore

```bash
read -r -s -p 'GPG passphrase: ' PASSPHRASE; echo
export PASSPHRASE
./restore.sh
```

The script downloads all mirrors and the dump, verifies dump decryption and
compression, and asks for confirmation before replacing any existing volumes.
It then stops Immich and the running backup containers, refuses unrelated
volume consumers, replaces filedata, clears the database volume in place,
starts only `immich-db`, and restores the dump with SQL errors fatal using
a temporary PostgreSQL 19 client container on `media_network`. It
starts Immich and restarts only the backup containers it stopped. A failed
restore leaves them stopped to protect the remote mirror; investigate and
restart them manually after recovery is verified.

The data volume is preserved; missing `.immich` markers for regenerated
directories and the restored volumes are created after the mirrors are checked.
Generated thumbnails and transcoded videos are not included in the three
mirrors. Re-run the relevant Immich jobs after recovery if required.
External libraries, if configured, need their original paths mounted separately.

### 4. Clean up the calling shell

```bash
unset PASSPHRASE
```

## Verification

```bash
docker compose ps
docker logs immich-db --tail 100
docker logs immich --tail 100
```

Check the Immich UI for photos, videos, profile images, and integrity errors.
Check the backup containers are running only after validating the result.
Deleted assets may need recovery from the Mega `deleted-archive` buckets
if the database dump and latest file mirror differ.

## Troubleshooting

- **Mirror is empty or missing:** verify the configured crypt password, optional
  salt, remote root, and successful backup jobs before using the empty override.
- **Database decryption fails:** verify the GPG passphrase and dump integrity.
- **Database restore fails:** inspect `docker logs immich-db`; use a compatible
  Immich/PostgreSQL version and the same database identity as the backup.
- **`unrecognized configuration parameter "transaction_timeout"`:** the dump was
  created by a newer PostgreSQL backup client, but Immich runs PostgreSQL 14.
  `restore.sh` and the manual fallback remove only this header setting before
  the first `CREATE`/`COPY`; update an older copy of the script if you see it.
- **Backup container remains stopped:** the restore failed after stopping it;
  fix the cause and verify the restored data before starting it manually.
- **Missing photos:** a database dump can be newer than one of the separate
  file mirrors, or assets may live in an external library.

## Optional: Read-only host access to Immich uploads

The restore script restores `immich_upload` but does not create a host mount.
To browse the volume on the Docker host at `/mnt/immich_upload`, create a
read-only bind mount. This is separate from the Immich container mount, which
remains writable.

Run this on the Docker host to print the fstab entry using the volume's actual
mountpoint:

```bash
printf '%s /mnt/immich_upload none bind,ro 0 0\n' \
  "$(docker volume inspect -f '{{.Mountpoint}}' immich_upload)"
```

Create the target directory, add the printed line to `/etc/fstab`, then mount
and verify it:

```bash
sudo mkdir -p /mnt/immich_upload
sudoedit /etc/fstab
sudo mount -a
findmnt -no TARGET,OPTIONS /mnt/immich_upload
```

Confirm the mount options include `ro`. If it was already mounted manually,
run `sudo umount /mnt/immich_upload` before `sudo mount -a` so fstab applies
the read-only option. After a restore, the mount continues to show the restored
files; no extra restore-script step is needed. The host user still needs read
and directory-traversal permission on the files. A user with root or
Docker-daemon access can bypass this read-only view.

## Manual fallback

Use only after investigating why the script failed. Download each decrypted
`current/` tree to a secure staging directory with `docker exec filedata-backup
rclone copy` and `docker cp`. Verify every download and the dump, then stop
both backup containers to prevent an incomplete restore being mirrored, and
ensure no other container uses the target volumes. The following commands
replace the contents of all four volumes:

```bash
docker compose down
set -o pipefail
read -r -s -p 'GPG passphrase: ' PASSPHRASE; echo
export PASSPHRASE
# Set these paths to the independently verified staged directories and dump.
STAGING=/path/to/staged-filedata
DUMP=/path/to/immich_YYYY-MM-DD_HH-MM-SS.sql.zst.gpg
for volume in immich_library immich_profile immich_upload; do
  docker volume inspect "$volume" >/dev/null 2>&1 || docker volume create "$volume"
  docker run --rm -v "$volume:/restore" -v "$STAGING/$volume:/source:ro" alpine \
    sh -ec 'find /restore -mindepth 1 -delete; cp -a /source/. /restore/'
done
docker volume inspect immich_postgresdata >/dev/null 2>&1 || docker volume create immich_postgresdata
docker run --rm -v immich_postgresdata:/restore alpine sh -ec 'find /restore -mindepth 1 -delete'
docker compose create
docker run --rm -v immich_data:/data -v immich_library:/data/library \
  -v immich_profile:/data/profile -v immich_upload:/data/upload alpine sh -ec '
  mkdir -p /data/library /data/profile /data/upload /data/thumbs /data/encoded-video /data/backups
  for dir in library profile upload thumbs encoded-video backups; do
    [ -e "/data/$dir/.immich" ] || touch "/data/$dir/.immich"
  done'
docker start immich-db
# Wait for initialization; substitute your configured database user/name if different.
until docker exec immich-db pg_isready -h 127.0.0.1 -U postgres -d immich; do sleep 1; done
# Create a private pgpass file for the temporary PostgreSQL client.
umask 077
read -r -s -p 'Immich database password: ' DB_PASSWORD; echo
DB_PASSWORD="${DB_PASSWORD//\\/\\\\}"
DB_PASSWORD="${DB_PASSWORD//:/\\:}"
PGPASS_FILE="$(mktemp)"
printf '*:*:*:*:%s\n' "$DB_PASSWORD" > "$PGPASS_FILE"
unset DB_PASSWORD
gpg --batch --yes --pinentry-mode loopback --passphrase "$PASSPHRASE" -d "$DUMP" | zstd -d \
  | sed '1,/^\(CREATE\|COPY\) /{/^SET transaction_timeout = 0;$/d}' \
  | sed "s/SELECT pg_catalog.set_config('search_path', '', false);/SELECT pg_catalog.set_config('search_path', 'public, pg_catalog', true);/g" \
  | docker run --rm -i --network media_network -v "$PGPASS_FILE:/run/pgpass:ro" \
      -e PGPASSFILE=/run/pgpass --entrypoint psql homelab/db-backup:local \
      -h immich-db -U postgres -d immich --single-transaction -v ON_ERROR_STOP=1
rm -f "$PGPASS_FILE"
docker compose up -d
unset PASSPHRASE PGPASS_FILE
```

Stop if any command fails. Verify the restored stack before restarting the
backup containers. If the pipeline fails, remove the private `$PGPASS_FILE`
before leaving the shell.
