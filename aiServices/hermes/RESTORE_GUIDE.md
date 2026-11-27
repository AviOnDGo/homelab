# Hermes Restore Guide

Hermes filedata backups contain the `hermes_filedata` Docker volume and are
stored as GPG-encrypted `.tar.zst.gpg` archives. The Obsidian vault is mounted
from the host through `OBSIDIAN_VAULT_PATH`; it is not included in this volume
backup and must be restored separately from its own backup.

## Prerequisites

- Docker and Docker Compose
- `rclone`, configured with the `dropbox` remote
- `gpg`, `zstd`, and `tar`
- The GPG passphrase used for filedata backups
- Hermes Compose environment configured in `aiServices/hermes/.env`
- A Hermes backup in the configured Dropbox path (default `/App_acc/hermes`)

## Restore Steps

### 1. Run the primary restore script

From the repository root:

```bash
cd aiServices/hermes
./restore.sh
```

The script prompts for the GPG passphrase, downloads and validates the latest
`hermes_*.tar.zst.gpg` backup, asks before replacing existing data, restores
`hermes_filedata`, starts Hermes, and verifies that the volume is populated and
the container is running. Set `DROPBOX_PATH` for another backup directory, for
example `/Apps/hermes`. Use `./restore.sh --if-missing` to skip when the
volume already exists, or `./restore.sh --force` only when intentionally
skipping overwrite confirmations.

### 2. Manual fallback

If the script is unavailable, stop Hermes and prepare the volume:

```bash
docker compose down
docker volume inspect hermes_filedata >/dev/null 2>&1 \
  && docker volume rm hermes_filedata
docker volume create hermes_filedata
export PASSPHRASE='<your_gpg_passphrase>'
```

Restore a downloaded backup archive:

```bash
rclone copyto \
  dropbox:/App_acc/hermes/hermes_<timestamp>.tar.zst.gpg \
  /path/to/hermes_<timestamp>.tar.zst.gpg
gpg --batch --yes --pinentry-mode loopback --passphrase-fd 3 \
  -d /path/to/hermes_<timestamp>.tar.zst.gpg 3<<<"$PASSPHRASE" \
  | zstd -d \
  | docker run --rm -i -v hermes_filedata:/restore alpine \
      sh -c 'cd /restore && tar -xf -'
```

Then start Hermes and clear the passphrase from the shell:

```bash
docker compose up -d
unset PASSPHRASE
```

## Verification

```bash
docker compose ps
docker logs --tail 100 hermes
docker run --rm -v hermes_filedata:/restore:ro alpine \
  sh -c 'find /restore -mindepth 1 -maxdepth 1 -print'
```

Confirm that the Hermes container is running and that restored files are
present in the volume. Verify the Obsidian vault mount separately:

```bash
docker exec hermes ls -la /opt/data/workspace/secondBrain
```

## Troubleshooting

| Symptom | Action |
|---|---|
| No Hermes backup found | Check the selected Dropbox directory with `DROPBOX_PATH` and confirm that a `hermes_*.tar.zst.gpg` backup exists. |
| GPG or decompression validation fails | Confirm the passphrase and retry with another available backup; the script validates the archive before changing the volume. |
| Hermes does not start after restore | Check `docker compose logs hermes` and confirm the Compose environment file is configured. |
| Obsidian vault is missing | The vault is a host bind mount, not part of `hermes_filedata`; check `OBSIDIAN_VAULT_PATH` and restore the host vault separately. |
