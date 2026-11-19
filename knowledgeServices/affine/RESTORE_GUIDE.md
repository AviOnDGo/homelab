# AFFiNE — Restore Guide

This guide is script-first. Use `restore.sh` for the normal recovery flow. The script restores the latest AFFiNE filedata archive and PostgreSQL dump from Dropbox, prompts before destructive volume recreation, restores filedata first, then the database, and finally brings the stack back up.

## Prerequisites

- Docker and Docker Compose installed
- `rclone`, `gpg`, and `zstd` available on the host
- Access to the Dropbox remote configured for backup retrieval
- GPG passphrase used when the backups were created
- Latest AFFiNE backups available in the Dropbox backup path:
  - `affine_*.tar.zst.gpg` for `affine_filedata`
  - `affine_*.sql.zst.gpg` for `affine_postgresdata`

## Restore Steps

### 1. Enter the service directory

```bash
cd knowledgeServices/affine
```

### 2. Run the restore script

```bash
./restore.sh
```

If `PASSPHRASE` is not exported, the script prompts for it securely. If either `affine_filedata` or `affine_postgresdata` already exists, the script asks before removing and recreating them.

### 3. Let the script finish the recovery sequence

The scripted order is:

1. Restore `affine_filedata`
2. Create containers without starting the application stack
3. Start only `affine-db`
4. Wait for PostgreSQL readiness with `pg_isready`
5. Restore the PostgreSQL dump into `affine_postgresdata`
6. Start the remaining AFFiNE services

## Verification

After the script completes:

1. Check that the stack is healthy:
  ```bash
  docker compose ps
  ```

2. Confirm PostgreSQL is reachable:
  ```bash
  docker exec -it affine-db pg_isready -U affine -d affine
  ```

3. Confirm the restored data is visible in the AFFiNE web UI.

4. Check the logs if anything looks wrong:
  ```bash
  docker compose logs -f affine
  ```

## Manual Fallback

Use the manual flow only if the scripted path is unavailable or you need to recover a partially completed restore.

### 1. Stop the stack

```bash
docker compose down
```

### 2. Restore the filedata volume

Recreate `affine_filedata` if needed, then extract the latest `affine_*.tar.zst.gpg` archive into it.

### 3. Restore the database volume

Start only `affine-db`, wait for PostgreSQL readiness, then restore the latest `affine_*.sql.zst.gpg` dump into the database.

### 4. Start the full stack

```bash
docker compose up -d
```

## Troubleshooting

- **GPG decryption fails**: Verify the passphrase is correct and the backup files are not corrupted.
- **`pg_isready` never succeeds**: Check `docker logs affine-db` and confirm the database volume was recreated cleanly.
- **Data is missing after restore**: Confirm the latest filedata archive was restored into `affine_filedata`.
- **AFFiNE starts but does not show restored content**: Verify the PostgreSQL restore completed successfully before the app stack was started.

## Rollback

If restore fails catastrophically:

```bash
docker compose down
docker volume rm affine_postgresdata affine_filedata
docker volume create affine_postgresdata affine_filedata
# Retry from Step 2
```
