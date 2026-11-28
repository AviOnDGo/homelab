# Immich Service Documentation

## Overview

**Service Name:** immich
**Purpose:** Self-hosted photo and video management with ML-assisted search and recognition
**Network:** media_network
**Access:** Via Nginx Proxy Manager to `immich:2283`

## Service Components

| Service Key | Container Name | Purpose |
|-------------|----------------|---------|
| `immich` | `immich` | Immich API and web application |
| `immich-ml` | `immich-ml` | Machine-learning inference workers |
| `immich-redis` | `immich-redis` | Cache/queue backend (Valkey) |
| `immich-db` | `immich-db` | PostgreSQL database |

## Storage and Volumes

| Volume | Type | Mounted In | Mount Path | Notes |
|--------|------|------------|------------|-------|
| `immich_library` | External named volume | `immich` | `/data/library` | Original assets and layout data |
| `immich_profile` | External named volume | `immich` | `/data/profile` | Avatar/profile images |
| `immich_upload` | External named volume | `immich` | `/data/upload` | Uploaded media payloads |
| `immich_data` | Named volume | `immich` | `/data` | Generated thumbnails, transcoded videos and local dumps; not included in file backups |
| `immich_model_cache` | External named volume | `immich-ml` | `/cache` | Downloaded ML models |
| `immich_postgresdata` | Internal named volume | `immich-db` | `/var/lib/postgresql` | PostgreSQL data directory |

For optional host-side browsing, `immich_upload` can be mounted read-only at
`/mnt/immich_upload`. This host mount is configured separately from Compose and
is not created by `restore.sh`; see [RESTORE_GUIDE.md](./RESTORE_GUIDE.md).
Immich retains write access through its container mount.

Create external volumes before first deployment:

```bash
docker volume inspect immich_library >/dev/null 2>&1 || docker volume create immich_library
docker volume inspect immich_profile >/dev/null 2>&1 || docker volume create immich_profile
docker volume inspect immich_upload >/dev/null 2>&1 || docker volume create immich_upload
docker volume inspect immich_model_cache >/dev/null 2>&1 || docker volume create immich_model_cache
docker network inspect media_network >/dev/null 2>&1 || docker network create media_network
```

For an existing deployment, the new `immich_data` mount does not automatically
copy data from the previous container's `/data` storage. Preserve or migrate
that data before recreating the container; generated thumbnails and videos can
otherwise be regenerated.

## Configuration

- Environment variables are loaded from `.env` (runtime-managed, not committed).
- PostgreSQL tuning is applied via `immich-db` `command:` `-c` flags in compose.
- Direct host port exposure is disabled; proxy through NPM.
- NVIDIA GPU acceleration for `immich-ml` and transcoding requires the NVIDIA Container Toolkit on the host.
- Install and verify the NVIDIA host driver separately (`nvidia-smi -L`).
  Then run [`configure-nvidia-container-toolkit.sh`](../../scripts/host/configure-nvidia-container-toolkit.sh)
  to configure Docker's NVIDIA runtime. Restart Docker during a maintenance window.

## Backup Coverage

Immich uses a split-lane backup policy:

- File lane (`immich_library`, `immich_profile`, `immich_upload`): `filedata-backup` runs `sync-crypt` mode to `mega-crypt` with `current/` plus dated `deleted-archive/` retention buckets.
- Database lane (`immich_postgresdata`): `db-backup` runs the standard encrypted `pg_dump` flow and uploads to Dropbox.

Retention for Immich sync-crypt deleted/replaced-file archives is set to 30 days
in the three Immich entries in
[`backup-volumes.conf`](../../backupServices/filedata/backup-volumes.conf).

### Fresh Local installation and backup setup

1. Configure the service environment using `.env.example`, create the volumes and
   network above, then start Immich. Confirm uploads work before enabling backups.
   If recovering existing data instead, follow `RESTORE_GUIDE.md` first: syncing
   empty volumes can overwrite existing remote mirrors.
2. Configure `backupServices/filedata/.env` using `.env.example`: set MEGA
   credentials and both crypt passwords as applicable. Review the three Immich
   destinations in `path.local` and their modes and schedules in
   `backup-volumes.conf`. Keep the crypt password and optional salt safe for recovery.
3. Configure `backupServices/postgres/.env` using `.env.example`. Set database
   credentials matching the Immich service and a GPG passphrase. The host,
   database, and backup names default to `immich-db`, `immich`, and `immich`.
   Review the
   Dropbox destination in `backupServices/postgres/path.local`.
   Set the database schedule in `backup-databases.conf` before the file
   schedules (the registry uses 02:00 versus 03:00, 03:15, and 03:30). Recreate
   the backup container after changing the registry.
4. Rebuild and recreate the Local filedata backup container, and recreate the
   Local PostgreSQL backup container:

   ```bash
   ../../backupServices/filedata/start-backup.sh local
   ../../backupServices/postgres/start-backup.sh local
   ```

5. From `mediaServices/immich`, test the database first and then each file lane:

   ```bash
   docker exec db-backup /usr/local/bin/backup-script.sh immich
   docker exec filedata-backup /usr/local/bin/backup-script.sh immich-library
   docker exec filedata-backup /usr/local/bin/backup-script.sh immich-profile
   docker exec filedata-backup /usr/local/bin/backup-script.sh immich-upload
   ./restore.sh --check-only
   ```

   Empty but valid volumes require the explicit override described in the
   restore guide. Check command exit statuses and remote contents. Keep a second
   independent backup: sync-crypt is not a point-in-time snapshot. For a
   consistent recovery point, stop the Immich server during a database backup
   followed by all three file backups; schedules alone cannot guarantee this.
   The standard backup container reports dump and Dropbox upload failures and
   requires GPG encryption for every database.

## Operations

### Start

```bash
cd mediaServices/immich
docker compose up -d
```

### Stop

```bash
cd mediaServices/immich
docker compose down
```

### Restart

```bash
cd mediaServices/immich
docker compose restart
```

### Update Images and Recreate

```bash
cd mediaServices/immich
docker compose pull
docker compose up -d --force-recreate
```

### Post-Upgrade Verification

After an Immich version bump, verify the stack and GPU runtime before treating the upgrade as complete:

```bash
cd mediaServices/immich
docker compose ps
docker info --format '{{json .Runtimes}}' | grep -i nvidia
docker logs immich --tail 100
docker logs immich-ml --tail 100
docker logs immich-db --tail 100
```

Confirm that `immich` is running the pinned `IMMICH_VERSION` from `.env.example`, `immich-ml` starts with the `cuda` image tag, and the logs do not show database or GPU initialization errors.

### Status

```bash
cd mediaServices/immich
docker compose ps
```

### Logs

```bash
cd mediaServices/immich
docker compose logs -f
```

Per-service logs:

```bash
docker logs immich
docker logs immich-ml
docker logs immich-redis
docker logs immich-db
```

## Troubleshooting

### `immich` cannot reach database

1. Confirm database container is healthy:
```bash
docker compose ps immich-db
docker logs immich-db
```
2. Confirm compose uses service hostname `immich-db` where relevant.
3. Confirm credentials in `.env` match database variables.

### `immich` background jobs are stuck

1. Check queue backend:
```bash
docker logs immich-redis
```
2. Check ML service health and logs:
```bash
docker logs immich-ml
```

### Poor app performance

1. Verify database is using tuned settings from compose `command:` flags.
2. Verify host has sufficient CPU/RAM for current library size.
3. Check long-running queries and ingestion load in `immich-db` logs.

## Restore Guidance

Use `restore.sh` as described in `RESTORE_GUIDE.md`. It uses rclone in the existing backup container; host-installed rclone is not required.

## Rollback Commands

If deployment validation fails after this standardization, revert relevant files to the last known good commit:

```bash
git checkout <known-good-commit> -- mediaServices/immich/docker-compose.yml mediaServices/immich/hwaccel.ml.yml
```

If documentation cleanup must be reverted:

```bash
git checkout <known-good-commit> -- mediaServices/immich/README.md mediaServices/immich/setup.sh
```
