# Radarr Restore Guide

## Prerequisites

- Docker Engine and Docker Compose installed and running
- The external `media_network` and `security_network` Docker networks exist
- Gluetun is running on `security_network` with its internal HTTP proxy enabled
- `rclone`, `gpg`, and `zstd` are installed on the host
- The `dropbox` rclone remote can access `/App_acc/radarr` (the script default), or the path supplied with `DROPBOX_PATH`
- The GPG passphrase used by `backupServices/filedata` is available
- `${HOME}/.media/.downloads` and `${HOME}/.media/Movies` are available; these paths are not restored

## Restore Steps

### 1. Enter the service directory and stop Radarr

```bash
cd mediaServices/radarr
docker compose down
```

### 2. Configure the restore source and passphrase

The script defaults to `dropbox:/App_acc/radarr` and securely prompts for the passphrase. Production backups are stored under `/Apps/radarr`, so set `DROPBOX_PATH=/Apps/radarr` when restoring from that profile. Set `DROPBOX_REMOTE`, `DROPBOX_PATH`, or `PASSPHRASE` when invoking the script to override those values.

### 3. Restore the config volume

```bash
./restore.sh
```

The script downloads the latest matching `radarr_*.tar.zst.gpg` archive. If `radarr_filedata` exists, it asks before replacing it. It creates the volume when absent, restores the archive, and starts Radarr. The downloads and Movies paths are not modified.

### 4. Clean up sensitive shell state

The script clears its passphrase variable and removes temporary files. If `PASSPHRASE` was exported in the calling shell, clear it after the script exits:

```bash
unset PASSPHRASE
```

## Verification

1. Confirm the container is running:

   ```bash
   docker compose ps
   ```

2. Review startup logs:

   ```bash
   docker compose logs --tail 100 radarr
   ```

3. Open Radarr at `http://<host>:7878` or through its Nginx Proxy Manager host.
4. Confirm the configured root folder resolves to `/movies` and downloads resolve to `/downloads`.

## Troubleshooting

- **No matching backup found**: verify the rclone remote and path and confirm a `radarr_*.tar.zst.gpg` archive exists.
- **GPG decryption fails**: verify the passphrase used by the filedata backup service.
- **Container does not start**: inspect `docker compose logs radarr`; the script leaves the stack stopped after a failed startup check.
- **Media is missing**: this restore covers only `radarr_filedata`; restore media and downloads from their separate storage source.
- **Restore script is unavailable**: for a new or empty volume, run the following from this directory and replace `<backup-filename>` with the selected archive name. For production archives, replace `/App_acc/radarr` with `/Apps/radarr`. GPG prompts for the passphrase.

   ```bash
   docker compose down
   docker volume create radarr_filedata
   mkdir -p /tmp/radarr-restore
   rclone copy "dropbox:/App_acc/radarr/<backup-filename>.tar.zst.gpg" /tmp/radarr-restore
   gpg --decrypt "/tmp/radarr-restore/<backup-filename>.tar.zst.gpg" | zstd -d | docker run --rm -i -v radarr_filedata:/restore alpine sh -c 'cd /restore && tar -xf -'
   docker compose up -d
   ```