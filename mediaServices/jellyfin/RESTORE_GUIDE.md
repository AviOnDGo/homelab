# Jellyfin Restore Guide

## Prerequisites

This procedure restores Jellyfin configuration and application state from the latest encrypted filedata archive. Media libraries and tracked M3U bind-mounted files are not included.

- Docker Engine and Docker Compose installed and running
- External Docker networks `media_network` and `security_network` exist
- Gluetun is running on `security_network` with its internal HTTP proxy enabled
- `rclone`, `gpg`, and `zstd` are installed on the host
- The `dropbox` rclone remote is configured and can access `/App_acc/jellyfin`
- GPG passphrase used by `backupServices/filedata`
- `jellyfin_filedata` can be recreated

## Restore Steps

### 1. Enter the service directory and stop Jellyfin

```bash
cd mediaServices/jellyfin
docker compose down
```

### 2. Configure the restore source and passphrase

The script defaults to `dropbox:/App_acc/jellyfin` and securely prompts for the passphrase. To use another remote path, set `DROPBOX_REMOTE` and/or `DROPBOX_PATH` when invoking the script.

### 3. Run the restore script

```bash
./restore.sh
```

The script downloads the latest matching `jellyfin_*.tar.zst.gpg` archive. It asks for confirmation before deleting an existing `jellyfin_filedata` volume, recreates the volume, decrypts and extracts the archive, and starts Jellyfin. On an empty host, it creates the volume before extraction.

### 4. Clean up sensitive shell state

The script unsets its passphrase variable and removes temporary files. If `PASSPHRASE` was exported in the calling shell, clear it after the script exits:

```bash
unset PASSPHRASE
```

## Verification

1. Confirm the container is running:

   ```bash
   docker compose ps
   ```

2. Review the startup logs:

   ```bash
   docker compose logs --tail 100 jellyfin
   ```

3. Open Jellyfin at `http://<host>:8096` or through its Nginx Proxy Manager host.
4. Confirm the libraries are visible from `/data/movies`, `/data/tvshows`, and `/data/music`.

## Troubleshooting

- **No matching backup found**: verify the Dropbox remote and path and confirm a `jellyfin_*.tar.zst.gpg` archive exists.
- **GPG decryption fails**: verify the passphrase matches the one used by the filedata backup service.
- **Container does not start**: inspect `docker compose logs jellyfin`; after a failed restore, keep Jellyfin stopped until the volume contents are reviewed.
- **Media is missing**: this restore covers only `/config`; restore the media directories from their separate backup source.
- **Restore script is unavailable**: stop Jellyfin, download the selected archive from the configured Dropbox path, decrypt and decompress it, and extract the tar stream into a freshly created `jellyfin_filedata` volume. Start Jellyfin only after extraction completes.

## Rollback

If a restore fails after the volume is recreated, keep the service stopped and rerun `./restore.sh` with a known-good archive. The script does not modify media-library directories.