# OmniRoute Restore Guide

This guide covers restoring the OmniRoute application data and provider
credentials from an encrypted filedata backup.

## Prerequisites

- Docker and Docker Compose
- `rclone`, `gpg`, `zstd`, and `tar`
- `aiServices/omniroute/.env` created from `.env.example`
- Access to the configured Dropbox remote and its GPG passphrase
- The `ai_network` Docker network

## Restore Steps

### 1. Navigate to the service and stop the stack

```bash
cd aiServices/omniroute
docker compose down
```

The restore script also stops the stack before replacing its data.

### 2. Set the passphrase

The script prompts for the passphrase if `PASSPHRASE` is unset. To enter it
without putting it in shell history:

```bash
read -r -s -p "GPG passphrase: " PASSPHRASE
echo
export PASSPHRASE
```

### 3. Ensure the target volume exists

```bash
docker volume inspect omniroute_filedata \
  || docker volume create omniroute_filedata
```

### 4. Restore the latest backup

```bash
./restore.sh
```

The script locates the latest `omniroute_*.tar.zst.gpg` backup under
`dropbox:/Apps/omniroute`, asks before replacing the data volume, restores the
archive, starts the service, and verifies its health. Override `DROPBOX_PATH`
if the backup is stored elsewhere. If the `filedata-backup` container is
running, the script pauses it while replacing the volume and restarts it on
successful completion. If a restore fails, the backup container remains
stopped so it cannot back up incomplete data; inspect the restored volume
before restarting it.

### 5. Start and verify the service

```bash
docker compose up -d
docker compose ps
docker logs --tail=100 omniroute
```

The script starts the service itself; the `up -d` command is safe to repeat.
Confirm the dashboard still contains the expected providers and settings.

### 6. Clear the shell passphrase

```bash
unset PASSPHRASE
```

## Verification

- `docker compose ps` reports `omniroute` as healthy.
- `docker logs --tail=100 omniroute` contains no startup or database errors.
- The dashboard loads through NPM and restored providers and settings are present.
- API requests succeed when authenticated with an OmniRoute API key.

## Troubleshooting

| Symptom | Action |
|---|---|
| No backup is found | Check `DROPBOX_PATH` and list files with `rclone lsf dropbox:/Apps/omniroute` |
| GPG decryption fails | Confirm the passphrase and select an intact `.tar.zst.gpg` archive |
| Service does not become healthy | Inspect `docker logs omniroute`; confirm the `.env` file and `ai_network` exist |
| Provider credentials are unreadable | Restore the matching persistent `JWT_SECRET` and `API_KEY_SECRET` values if they were configured outside the data volume |

## Manual Restore Fallback

1. Stop OmniRoute with `docker compose down`. If `filedata-backup` is running,
   stop it too so it releases the volume:

   ```bash
   if docker ps --format '{{.Names}}' | grep -Fxq filedata-backup; then
     docker stop filedata-backup
   fi
   ```

2. Download the chosen archive into a local directory.
3. Ensure `omniroute_filedata` exists, then decrypt and extract:

   ```bash
   docker volume inspect omniroute_filedata \
     || docker volume create omniroute_filedata

   gpg --batch --yes --passphrase "$PASSPHRASE" \
     -d /path/to/omniroute_<timestamp>.tar.zst.gpg \
     | zstd -d \
     | docker run --rm -i -v omniroute_filedata:/restore alpine \
         sh -c 'find /restore -mindepth 1 -maxdepth 1 -exec rm -rf {} \; && cd /restore && tar -xf -'
   ```

4. Restart `filedata-backup` if you stopped it, then start and verify OmniRoute
   with the commands in step 5 above. Clear the shell passphrase as described
   in step 6.
