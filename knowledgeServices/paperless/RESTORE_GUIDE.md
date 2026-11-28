# Paperless-ngx Restore Guide

This guide restores the Paperless document tree from the Google Drive crypt mirror and restores
the PostgreSQL metadata from the latest encrypted Dropbox dump. The two lanes can represent
different recovery points: filedata is as of the latest successful sync, while PostgreSQL is a
dated snapshot.

## Prerequisites

- Docker Engine with the Compose plugin, plus `gpg` and `zstd` on the host.
- Existing external `knowledge_network` and `ai_network` Docker networks.
- For the default restore mode, a running `filedata-backup` container with working `dropbox`,
  `gdrive`, and `gdrive-crypt` remotes. Configure the credentials in
  `backupServices/filedata/.env` and set
  `PAPERLESS_SYNC_CRYPT_REMOTE=gdrive-crypt:paperless` in
  `backupServices/filedata/path.local`. Paperless mode is set to `sync-crypt`
  in `backupServices/filedata/backup-volumes.conf`. Recreate the backup container after
  changing its configuration. Google OAuth client ID and secret are only needed when the tokens
  were issued for your own OAuth client.
- If restoring from a PostgreSQL dump in production, set `DROPBOX_PATH=/Apps/paperless`; the
  default path is `/App_acc/paperless`.
- Verify the database destination in
  [`path.local`](../../backupServices/postgres/path.local) or
  [`path.prod`](../../backupServices/postgres/path.prod), and set `DROPBOX_PATH`
  if it differs from the restore default.

For standalone recovery without the `filedata-backup` container, install host `rclone` and use
`RCLONE_SOURCE=env`. The script reads credentials from `backupServices/filedata/.env` by default;
that file must contain the Dropbox and Google Drive tokens and the rclone crypt password. You do
not need to create the Paperless Docker volumes manually; the restore script creates them.

## Restore Steps

### 1. Enter the service directory

```bash
cd knowledgeServices/paperless
```

### 2. Verify rclone remotes and restore paths

The restore script defaults to running rclone inside the existing `filedata-backup` container.
It does not read or modify the host's rclone configuration or load credential files in this mode.
It uses the container's working Drive, crypt, and Dropbox settings without exporting them.
The container must already be running; the script never starts it automatically.

Run a read-only connectivity and mirror-content check before recovery:

```bash
./restore.sh --check-only
```

This checks all three remotes and verifies the mirror contains files, without downloading
documents, requesting a passphrase, stopping services, or modifying volumes.

For standalone recovery without the backup container, explicitly set `RCLONE_SOURCE=env`.
That mode requires host `rclone`, loads credentials from
`../../backupServices/filedata/.env`, and uses the shared backup configuration helper to
create a temporary rclone configuration, accessible only to the current user. This configuration,
including any refreshed OAuth tokens, is deleted when the script exits.

Required variables are `DROPBOX_AUTH_TOKEN`, `DROPBOX_REFRESH_TOKEN`,
`GOOGLE_DRIVE_ACCESS_TOKEN`, `GOOGLE_DRIVE_REFRESH_TOKEN`, and `RCLONE_CRYPT_PASSWORD`.
Set `RCLONE_CRYPT_PASSWORD2` to the same optional salt used during backup. Crypt passwords
are plaintext inputs, not values already obscured by rclone. When using your own Google OAuth
client, set both `GOOGLE_DRIVE_CLIENT_ID` and `GOOGLE_DRIVE_CLIENT_SECRET`.

The loader accepts single-line unquoted or quoted values and optional `export` prefixes.
It preserves literal dollar signs rather than performing shell expansion, ignores unrelated
settings such as cron schedules, and never executes the credential file as shell code.
Quoted values cannot contain their own quote delimiter.

The default remote names and relationship are:

| Remote | Type and purpose | Paperless location |
| --- | --- | --- |
| `dropbox` | Dropbox remote for PostgreSQL dumps | `/App_acc/paperless/` by default |
| `gdrive` | Google Drive backend remote | Root of the crypt remote |
| `gdrive-crypt` | Crypt remote with `remote = gdrive:` | Paperless filedata is under `paperless/current/` |

The filedata-backup configuration uses `PAPERLESS_SYNC_CRYPT_REMOTE=gdrive-crypt:paperless`. Its
sync job appends `/current`, so the restore default is `gdrive-crypt:paperless/current/`. The
`paperless` segment is a directory inside the crypt remote; `gdrive:` is its backing Drive root.
If you customize the destination in the path file, set the corresponding
`GDRIVE_CRYPT_REMOTE` and `GDRIVE_CRYPT_PATH` for the restore before proceeding.

The script verifies remote access and a nonempty decrypted mirror before changing volumes.
No interactive `rclone config` or host remotes are needed.

The script defaults to the acceptance Dropbox path. Override it when restoring another environment:

```bash
DROPBOX_PATH=/Apps/paperless ./restore.sh
```

In `env` mode, use a different credential file with `BACKUP_ENV_FILE=/absolute/path/to/credentials`.
Remote-name overrides (`DROPBOX_REMOTE`, `GDRIVE_REMOTE`, `GDRIVE_CRYPT_REMOTE`) rename
the generated remotes in `env` mode, or select existing container remotes in container mode.
They never select remotes from the host configuration.

### 3. Run the restore script

```bash
./restore.sh
```

The script verifies access to all three remotes, then syncs the Paperless `current/` mirror from
Google Drive into temporary local storage. If `PASSPHRASE` is not exported, it prompts for it
securely. If either persistent volume already exists, the script asks before replacing the
filedata contents and recreating the database volume. The existing filedata volume is retained
so the backup container keeps its volume mount.

In container mode, the decrypted mirror is downloaded to a unique temporary directory inside
`filedata-backup`, then copied to host staging with `docker cp`. The container staging directory
is removed before the backup container is stopped. PostgreSQL dumps are streamed directly from
container rclone to the host. A failed transfer aborts before any volume changes.

### 4. Let the script finish the recovery sequence

The scripted order is:

1. Sync the expanded `current/` tree from the Google Drive crypt remote into temporary local storage
2. Download the latest GPG-encrypted, zstd-compressed PostgreSQL dump from Dropbox
3. After confirmation, stop the Paperless stack and any running `filedata-backup` container,
   recreate the database volume, and replace the contents of `paperless_filedata` with the synced tree
4. Create containers without starting the application stack
5. Start only `paperless-db`
6. Wait for TCP readiness and a local SQL connection to the `postgres` maintenance database, create the target
   database if absent, restore the dump with SQL errors treated as fatal, and verify a SQL
   connection to the restored database
7. Start the remaining Paperless services
8. Start `filedata-backup` if it is stopped, including when it was stopped before recovery.
   Leave an already-running container untouched and report startup failures with a nonzero exit.

The script refuses to remove unrelated containers using the restore volumes. If recovery fails,
`filedata-backup` remains stopped to prevent an incomplete restore from overwriting the remote
mirror. After resolving the failure and verifying recovery, restart it with
`docker start filedata-backup`. A successful restore starts an existing stopped backup container
regardless of its original state; failed or cancelled restores do not start it.

The following operational volumes are recreated by Docker Compose and are not restored from backup:

- `paperless_data`
- `paperless_export`
- `paperless_consume`

### 5. Clean up sensitive shell state

The script unsets `PASSPHRASE` during cleanup. Unset any environment override in the calling shell
after the command returns:

```bash
unset PASSPHRASE
```

## Verification

1. Check that the stack is healthy:

   ```bash
   docker compose ps
   ```

2. Confirm PostgreSQL is reachable:

   ```bash
   docker exec -it paperless-db pg_isready -U paperless -d paperless
   ```

3. Confirm restored originals and archive files are visible in the Paperless web UI.

4. Check the application logs:

   ```bash
   docker compose logs -f paperless
   ```

## Troubleshooting

- **Google Drive reports `invalid_client`**: Google rejected the OAuth client used to
  refresh the access token. Verify that `GOOGLE_DRIVE_CLIENT_ID` and
  `GOOGLE_DRIVE_CLIENT_SECRET` in the backup configuration are a valid matching
  pair from the same Google OAuth client that issued `GOOGLE_DRIVE_REFRESH_TOKEN`.
  If the client was deleted or the refresh token belongs to another client,
  authorize again with the intended client and update the token. Do not clear the
  custom client fields while keeping a refresh token issued to that client.
  Recreate the Local backup container to regenerate its rclone configuration:

  ```bash
  ../../backupServices/filedata/start-backup.sh local
  ./restore.sh --check-only
  ```

  These commands run from the Paperless service directory. The preflight preserves
  rclone's error output so OAuth, network, and permission failures remain visible.
- **Google Drive crypt remote cannot be reached**: in container mode, check the working remote
  with `docker exec filedata-backup rclone size --json gdrive-crypt:paperless/current/`.
  In `env` mode, verify the backup credential file, crypt password and salt, OAuth refresh token,
  OAuth client pair, and `GDRIVE_CRYPT_PATH`.
- **PostgreSQL GPG decryption fails**: verify the passphrase and that the Dropbox dump is intact.
- **Documents are missing**: verify the mirror contains `documents/originals/` and
  `documents/archive/`; files changed after the selected database dump may need re-consumption.
- **Paperless shows broken entries**: the database dump can be older than the file mirror. Recover
  the matching file state from an older Dropbox archive if one is still available, or re-consume
  the affected documents.
- **Restore aborts because the Google Drive crypt path is missing or empty**:
  `restore.sh` verifies `${GDRIVE_CRYPT_REMOTE}:${GDRIVE_CRYPT_PATH}/current/` before touching
  any volume. Confirm the filedata-backup job has run and that `gdrive-crypt` is a `crypt` remote
  backed by `gdrive:`, with the same crypt password used for backup. Check that the mirror
  exists using the backup service's configured rclone, not the host configuration.
  Set `GDRIVE_CRYPT_PATH` to
  `paperless` by default, or to another relative path when the mirror is stored elsewhere.
- **PostgreSQL does not become ready**: inspect `docker logs paperless-db` and confirm the volume
  was recreated cleanly.
- **Database "paperless" does not exist**: the script now waits for PostgreSQL initialization
  to finish by checking TCP readiness and an actual local SQL connection, then creates the target
  database through the `postgres` maintenance database
  when absent. Set `DB_USER` and `DB_NAME` explicitly if using nondefault restore credentials.
  The selected user needs permission to create the database. A successful `pg_isready` alone
  does not prove that the target database exists.

## Optional: Read-only host access to Paperless media

The restore script restores `paperless_filedata` but does not create a host
mount. This volume contains Paperless media mounted in the container at
`/usr/src/paperless/media`; it does not include the separate data, export, or
consume volumes. To browse it on the Docker host at `/mnt/paperless_filedata`,
create a read-only bind mount. Paperless itself remains able to write to its
container mount.

Run this on the Docker host to print the fstab entry using the volume's actual
mountpoint:

```bash
printf '%s /mnt/paperless_filedata none bind,ro 0 0\n' \
  "$(docker volume inspect -f '{{.Mountpoint}}' paperless_filedata)"
```

Create the target directory, add the printed line to `/etc/fstab`, then mount
and verify it:

```bash
sudo mkdir -p /mnt/paperless_filedata
sudoedit /etc/fstab
sudo mount -a
findmnt -no TARGET,OPTIONS /mnt/paperless_filedata
```

Confirm the mount options include `ro`. If it was already mounted manually,
run `sudo umount /mnt/paperless_filedata` before `sudo mount -a` so fstab
applies the read-only option. After a restore, the mount continues to show the
restored files; no extra restore-script step is needed. The host user still
needs read and directory-traversal permission on the files. A user with root
or Docker-daemon access can bypass this read-only view.
