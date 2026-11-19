# Transmission Restore Guide

## Prerequisites

- Docker Engine and Docker Compose installed and running
- The external `media_network` and `security_network` networks exist
- Gluetun is available on `security_network`
- `mediaServices/transmission/.env` exists with valid Transmission credentials
- `rclone`, `gpg`, and `zstd` are installed on the host
- The configured Dropbox remote can access the Transmission archive directory
- The GPG passphrase used by `backupServices/filedata` is available

## Restore Steps

### 1. Enter the service directory and stop Transmission

```bash
cd mediaServices/transmission
docker compose down
```

### 2. Set the restore source and passphrase

The restore script defaults to `dropbox:/App_acc/transmission` and securely
prompts for the passphrase. Set `DROPBOX_PATH=/Apps/transmission` when restoring
production archives. `DROPBOX_REMOTE`, `DROPBOX_PATH`, and `PASSPHRASE` can
override the defaults.

### 3. Restore the config volume

```bash
./restore.sh
```

The script restores the latest matching archive, replacing
`transmission_filedata`, then starts Transmission. It temporarily stops
`filedata-backup` if it is running so the volume can be replaced, and restarts
it on exit. It does not modify downloads, the watch directory, or `.env`
credentials.

### 4. Verify the restore

```bash
docker compose ps
docker compose logs --tail 100 transmission
```

Confirm the Transmission web interface is reachable through its configured
Nginx Proxy Manager route and that the download and watch paths resolve.

### 5. Clean up sensitive shell state

The script clears its passphrase variable and removes temporary files. If
`PASSPHRASE` was exported in the calling shell, clear it after the script exits:

```bash
unset PASSPHRASE
```

## Verification

Confirm `transmission_filedata` is mounted at `/config` and the Transmission
container is running with `docker compose ps`.

## Troubleshooting

- **No archive found**: verify `DROPBOX_REMOTE`, `DROPBOX_PATH`, and the
  matching `transmission_*.tar.zst.gpg` archive.
- **GPG decryption fails**: verify the filedata backup passphrase.
- **Compose reports missing credentials**: create `.env` from `.env.example`
  and set valid credentials.
- **Container does not start**: inspect `docker compose logs transmission`
  and confirm both external networks exist.
- **Restore script is unavailable**: stop Transmission, download an archive
  with `rclone copy`, then restore it into the external volume. GPG prompts
  for the passphrase.

```bash
docker compose down
docker volume create transmission_filedata
mkdir -p /tmp/transmission-restore
rclone copy "dropbox:/App_acc/transmission/<backup-filename>.tar.zst.gpg" /tmp/transmission-restore
gpg --decrypt "/tmp/transmission-restore/<backup-filename>.tar.zst.gpg" | zstd -d | docker run --rm -i -v transmission_filedata:/restore alpine sh -c 'cd /restore && tar -xf -'
docker compose up -d
```