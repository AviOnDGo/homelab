# Jackett Restore Guide

## Prerequisites

- Docker Engine and Docker Compose installed and running
- The external `media_network` and `security_network` networks exist
- Gluetun is available on `security_network`
- `rclone`, `gpg`, and `zstd` are installed on the host
- The configured Dropbox remote can access the Jackett archive directory
- The GPG passphrase used by `backupServices/filedata` is available

## Restore Steps

### 1. Enter the service directory and stop Jackett

```bash
cd mediaServices/jackett
docker compose down
```

### 2. Set the restore source and passphrase

The restore script defaults to `dropbox:/App_acc/jackett` and securely prompts
for the passphrase. Set `DROPBOX_PATH=/Apps/jackett` when restoring production
archives. `DROPBOX_REMOTE`, `DROPBOX_PATH`, and `PASSPHRASE` can override the
defaults.

### 3. Restore the config volume

```bash
./restore.sh
```

The script restores the latest matching archive, replacing `jackett_filedata`,
then starts Jackett. It temporarily stops `filedata-backup` if it is running so
the volume can be replaced, and restarts it on exit. It does not modify
downloads.

### 4. Verify the restore

```bash
docker compose ps
docker compose logs --tail 100 jackett
```

Confirm the expected indexers are present and that Sonarr and Radarr can reach
`http://jackett:9117`.

### 5. Clean up sensitive shell state

The script clears its passphrase variable and removes temporary files. If
`PASSPHRASE` was exported in the calling shell, clear it after the script exits:

```bash
unset PASSPHRASE
```

## Verification

Confirm `jackett_filedata` is mounted at `/config` and the Jackett container is
running with `docker compose ps`.

## Troubleshooting

- **No archive found**: verify `DROPBOX_REMOTE`, `DROPBOX_PATH`, and the
  matching `jackett_*.tar.zst.gpg` archive.
- **GPG decryption fails**: verify the filedata backup passphrase.
- **Container does not start**: inspect `docker compose logs jackett` and
  confirm both external networks exist.
- **Restore script is unavailable**: stop Jackett, download an archive with
  `rclone copy`, then restore it into the external volume. GPG prompts for the
  passphrase.

```bash
docker compose down
docker volume create jackett_filedata
mkdir -p /tmp/jackett-restore
rclone copy "dropbox:/App_acc/jackett/<backup-filename>.tar.zst.gpg" /tmp/jackett-restore
gpg --decrypt "/tmp/jackett-restore/<backup-filename>.tar.zst.gpg" | zstd -d | docker run --rm -i -v jackett_filedata:/restore alpine sh -c 'cd /restore && tar -xf -'
docker compose up -d
```