# n8n Restore Guide

This guide restores n8n using the filedata-only flow. The SQLite database is stored inside `n8n_filedata`.

## Prerequisites

- Docker and Docker Compose are installed.
- `rclone`, `gpg`, and `zstd` are installed and configured.
- `aiServices/n8n/.env` exists if local environment overrides are required.
- An encrypted `n8n_filedata` archive (`.tar.zst.gpg`) is available.
- GPG passphrase is available.
- `aiServices/n8n/restore.sh` is executable.

## Automated Restore (Recommended)

The restore script finds the latest n8n archive, confirms volume replacement, restores the SQLite data, starts n8n, and verifies `database.sqlite`.

```bash
cd aiServices/n8n
PASSPHRASE=<your_gpg_passphrase> ./restore.sh
```

Use `DROPBOX_PATH=/App_acc/n8n` for acceptance backups or set `DROPBOX_REMOTE` when the backup remote is not named `dropbox`.

## Manual Restore Fallback

### 1. Navigate to service directory and stop stack

```bash
cd aiServices/n8n
docker compose down
```

### 2. Set passphrase in shell

```bash
export PASSPHRASE=<your_gpg_passphrase>
```

### 3. Ensure required external volume exists

```bash
docker volume inspect n8n_filedata >/dev/null 2>&1 || docker volume create n8n_filedata
```

### 4. Restore filedata archive into n8n_filedata

```bash
docker run --rm \
  -v n8n_filedata:/restore \
  -v /path/to/backup/dir:/backup:ro \
  alpine sh -c "
    apk add --no-cache gnupg tar zstd &&
    gpg --batch --yes --passphrase '${PASSPHRASE}' \
      -d /backup/n8n_filedata_<timestamp>.tar.zst.gpg | \
      zstd -d | tar -xf - -C /restore
  "
```

### 5. Start n8n

```bash
docker compose up -d
```

### 6. Cleanup sensitive shell state

```bash
unset PASSPHRASE
```

## Verification

```bash
# Container status
docker compose ps

# Verify n8n reachable on network
docker run --rm --network ai_network curlimages/curl:8.10.1 -s -o /dev/null -w "%{http_code}\n" http://n8n:5678/

```

Expected outcomes:

- `n8n` reports up
- HTTP probe returns `200`
- Restored workflows and credentials are visible in n8n.

## Troubleshooting

| Symptom | Action |
|---|---|
| GPG decrypt fails | Verify passphrase and file path; test with `gpg -d` before piping |
| n8n starts with empty data | Re-check filedata archive extraction target is `n8n_filedata` |

## Optional: Dropbox Download

If backup files are only in Dropbox, download them first with rclone:

```bash
docker run --rm \
  -v /path/to/local/dir:/download \
  rclone/rclone copy dropbox:/Apps/n8n/ /download/
```
