# Invidious Database Restore Guide

This guide covers the script-first workflow for restoring the Invidious PostgreSQL
database from the latest Dropbox backup.

## Prerequisites

- Docker and Docker Compose installed
- Rclone configured with a reachable `dropbox` remote
- A valid `.env` file in `mediaServices/invidious/` (required)
- GPG passphrase for backup decryption
- Check the database backup destination in
  [`path.local`](../../backupServices/postgres/path.local) or
  [`path.prod`](../../backupServices/postgres/path.prod). The script defaults
  to `/App_acc/invidious` if `DROPBOX_PATH` is unset.

Set and verify the selected destination in your shell before either recovery
path. For example, enter `/App_acc/invidious` for local or `/Apps/invidious`
for prod:

```bash
read -r -p "Selected Dropbox destination: " DROPBOX_PATH
: "${DROPBOX_PATH:?A Dropbox destination is required}" && export DROPBOX_PATH
```

## Restore Steps (Script-First)

### 1. Run restore script

```bash
cd mediaServices/invidious
: "${DROPBOX_PATH:?Set the selected Dropbox destination first}" && bash restore.sh
```

The script performs:
- Preflight checks (`docker`, `rclone`, `gpg`, `zstd`, Docker daemon)
- `.env` presence validation before any remote backup lookup
- Latest backup discovery from the selected `DROPBOX_PATH`
- Download, decrypt, decompress, and import workflow for `*.sql.zst.gpg`

### 2. Passphrase behavior

- If `PASSPHRASE` is already set in your shell, the script uses it.
- If `PASSPHRASE` is missing, the script prompts securely.
- Empty passphrase input fails the restore.

### 3. Existing volume behavior

If `invidious_postgresdata` exists, the script prompts:

`Remove and recreate volume? [Y/n]`

- `Y` (default): remove and recreate the volume, then restore
- `n`: keep current volume and skip restore (starts full stack only)

### 4. Failure posture

If PostgreSQL readiness or post-restore validation fails, the script exits
non-zero and explicitly leaves the stack down for manual inspection.

## Verification

After successful restore:

1. Check stack status:
   ```bash
   docker compose ps
   ```
2. Verify PostgreSQL readiness:
   ```bash
   docker exec invidious-db pg_isready -U kemal -d invidious
   ```
3. Review logs if needed:
   ```bash
   docker compose logs -f
   ```

## Manual Fallback Recovery

Use this only when `restore.sh` cannot be used.
Run the manual steps from `mediaServices/invidious/` after setting
`DROPBOX_PATH` as described in Prerequisites.

### 1. Stop stack

```bash
docker compose down
```

### 2. Discover and download latest backup

```bash
: "${DROPBOX_PATH:?Set the selected Dropbox destination first}" \
  && rclone lsf "dropbox:${DROPBOX_PATH}" --files-only | grep -E '\.sql\.zst\.gpg$' | sort
read -r -p "Backup filename to restore: " BACKUP_FILE
: "${DROPBOX_PATH:?Set the selected Dropbox destination first}" \
  && : "${BACKUP_FILE:?A backup filename is required}" \
  && rclone copy "dropbox:${DROPBOX_PATH}/${BACKUP_FILE}" .
```

### 3. Recreate volume and start database container

```bash
docker volume rm invidious_postgresdata
docker volume create invidious_postgresdata
docker compose create
docker start invidious-db
```

### 4. Restore database

```bash
gpg --batch --yes --passphrase "$PASSPHRASE" -d "$BACKUP_FILE" \
  | zstd -d \
  | docker exec -i invidious-db psql -U kemal -d invidious
```

### 5. Start full stack

```bash
docker compose up -d
```

## Troubleshooting

- Restore reports no backup files: confirm files exist in the selected Dropbox path and match `*.sql.zst.gpg`
- GPG decryption fails: verify passphrase and file integrity
- PostgreSQL readiness failures: inspect `docker logs invidious-db`
- Failed restore validation: stack is intentionally left down; inspect DB container state and rerun after correction

## Rollback Steps

If a restore drill or real restore indicates the updated workflow is unsuitable,
roll back script and guide revisions:

1. From repository root, restore prior versions from git history:
   ```bash
   git checkout <known-good-commit> -- mediaServices/invidious/restore.sh mediaServices/invidious/RESTORE_GUIDE.md
   ```
2. Re-run syntax and docs checks as needed:
   ```bash
   bash -n mediaServices/invidious/restore.sh
   ```
3. Re-run restore using the restored script behavior in a safe environment before production use.

## Security Note

If you exported `PASSPHRASE` manually, clear it after restore:

```bash
unset PASSPHRASE
```

## Additional Information

For service architecture and operational details, see
[openspec/specs/media-services/spec.md](../../openspec/specs/media-services/spec.md).
