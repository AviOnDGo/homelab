# Paperless-ngx Service Documentation

## Overview

**Service Name:** paperless-ngx
**Purpose:** Document management system — scan, index, and archive physical documents
**Network:** media_network
**Access:** Via Nginx Proxy Manager (no direct port exposure)

## Components

| Service | Container | Image | Purpose |
|---------|-----------|-------|---------|
| **paperless** | paperless | ghcr.io/paperless-ngx/paperless-ngx:latest | Web application |
| **paperless-db** | paperless-db | postgres:latest | PostgreSQL database |
| **paperless-broker** | paperless-broker | redis:latest | Celery task queue broker |
| **paperless-gotenberg** | paperless-gotenberg | gotenberg/gotenberg:latest | Office document conversion (DOCX, XLSX, etc.) |
| **paperless-tika** | paperless-tika | apache/tika:latest | Advanced document parsing and text extraction |

## Volumes & Data

**PostgreSQL Data:**
- Volume: `paperless_postgresdata` (internally managed named volume)
- Mount: `/var/lib/postgresql` in `paperless-db`
- Created automatically by `docker compose up`

**Application Data:**
- Volume: `paperless_filedata` → `/usr/src/paperless/media` (retained documents and derived media)
- Volume: `paperless_data` → `/usr/src/paperless/data` (search index, classifier model, scheduler state)
- Volume: `paperless_export` → `/usr/src/paperless/export` (exported copies — operational, not backed up)
- Volume: `paperless_consume` → `/usr/src/paperless/consume` (ingest inbox — operational, not backed up)

`paperless_postgresdata`, `paperless_data`, `paperless_export`, and `paperless_consume` are created automatically by `docker compose up`.

`paperless_filedata` is configured as an external named volume and SHALL be created before first start if it does not already exist:

```bash
docker volume inspect paperless_filedata >/dev/null 2>&1 || docker volume create paperless_filedata
```

For optional host-side browsing, `paperless_filedata` can be mounted read-only
at `/mnt/paperless_filedata`. This exposes retained media only, is configured
separately from Compose, and is not created by `restore.sh`; see
[RESTORE_GUIDE.md](./RESTORE_GUIDE.md). Paperless retains write access through
its container mount.

## Configuration Files

**`.env`** (gitignored — copy from `.env.example`):

```bash
# PostgreSQL
POSTGRES_DB=paperless
POSTGRES_USER=paperless
POSTGRES_PASSWORD=<password>

# Paperless-ngx
PAPERLESS_REDIS=redis://paperless-broker:6379
PAPERLESS_DBHOST=paperless-db
PAPERLESS_DBNAME=paperless
PAPERLESS_DBUSER=paperless
PAPERLESS_DBPASS=<password>   # must match POSTGRES_PASSWORD
PAPERLESS_SECRET_KEY=<random-50-char-string>
PAPERLESS_URL=https://paperless.yourdomain.com
PAPERLESS_OCR_LANGUAGE=eng
PAPERLESS_OCR_LANGUAGES=nld hin
PAPERLESS_TIKA_ENABLED=1
PAPERLESS_TIKA_GOTENBERG_ENDPOINT=http://paperless-gotenberg:3000
PAPERLESS_TIKA_ENDPOINT=http://paperless-tika:9998
```

Set `PAPERLESS_URL` in the ignored `.env` to the public URL configured in Nginx
Proxy Manager. The value above is a placeholder; `.env.example` contains the
same placeholder for new installations.

## Service Dependencies

**Startup Order:**
1. `paperless-db` + `paperless-broker` + `paperless-gotenberg` + `paperless-tika`
2. `paperless` (depends on all four above)

## Watchtower

`paperless-db` is **excluded** from Watchtower auto-updates (`com.centurylinklabs.watchtower.enable=false`).
Postgres major-version upgrades require a manual `pg_upgrade` and must be performed deliberately.
All other paperless containers follow the standard Watchtower update policy.

## Backup Coverage

✅ **Two-tier backup — database metadata + synchronized document mirror**

### 1. PostgreSQL Database Backup

- **Service:** `backupServices/postgres/`
- **Schedule:** Daily at 3:10 AM (`10 3 * * *`)
- **Format:** GPG-encrypted SQL dump
- **Destination:** Dropbox `/App_acc/paperless/`
- **Retention:** 30 days (configurable via `PAPERLESS_BACKUP_RETENTION_DAYS`)
- **Covers:** users and login state, document metadata, tags, correspondents, history, workflows, archive filenames

### 2. Synchronized Document File Backup

- **Service:** `backupServices/filedata/`
- **Schedule:** Daily at 4:15 AM (`15 4 * * *`) — intentionally offset from DB backup
- **Format:** rclone crypt mirror
- **Destination:** `gdrive-crypt:paperless/current/`; `gdrive-crypt` is a crypt remote
  backed by the Google Drive root (`gdrive:`)
- **Retention:** 0 days, pure mirror; deletions are propagated and not retained
- **Covers:** `paperless_filedata/documents/originals/**` and `paperless_filedata/documents/archive/**`
- **Excludes:** `documents/thumbnails/**` (rebuildable), `media.lock` (runtime artifact), in both archive and sync modes

The file mirror reflects the latest successful sync, while the PostgreSQL lane is a dated Dropbox
snapshot. A restore can therefore contain files newer than the restored database; re-consume those
documents when needed. The mirror's zero retention setting provides no recovery copy for deletions
or corruption propagated by a successful sync.

**Rclone remotes used for Paperless recovery:** `dropbox` stores the PostgreSQL dump at
`/App_acc/paperless/` by default. `gdrive` is the Google Drive backend, and `gdrive-crypt` is the
crypt remote backed by `gdrive:`. The filedata backup destination is configured as
`gdrive-crypt:paperless`; the backup job appends `/current`. Keep the OAuth credentials and crypt
password available for disaster recovery, but do not store them in this document.

**Not backed up (by design):**
- `paperless_data` — search index, logs, and scheduler state are rebuildable after restore
- `paperless_consume` — pre-ingest inbox; files here are not yet retained library data
- `paperless_export` — exported copies; reproducible from database + retained documents

### Required `.env` entries in `backupServices/postgres/.env`

```bash
PAPERLESS_DB_HOST=paperless-db
PAPERLESS_DB_USER=paperless
PAPERLESS_DB_PASSWORD=<password>
PAPERLESS_DB_NAME=paperless
PAPERLESS_BACKUP_NAME=paperless
PAPERLESS_DROPBOX_BACKUP_PATH=/App_acc/paperless
PAPERLESS_BACKUP_RETENTION_DAYS=30
```

## Common Operations

### Network Placement

All five Paperless containers use the external `knowledge_network`. Only the
`paperless` webserver also joins `ai_network` for AI integrations. Nginx Proxy
Manager reaches `paperless:8000` through `knowledge_network`; no Paperless container
uses `media_network`.

The database backup container also requires `knowledge_network` to resolve
`paperless-db`. Both the default and Local database backup profiles include it.
Filedata backups continue using the same read-only volume mount and crypt mirror.

### Moving an Existing Deployment

The stack now lives in `knowledgeServices/paperless/`. Move the entire service
directory on each deployed host, including its gitignored local configuration,
without changing credentials or the Paperless secret key. Keep the Compose project
name `paperless` and all five existing volume names. No data restore is required
for a same-host move; do not run `restore.sh` or `docker compose down -v`.

For a stopped-stack migration, stop Paperless from its old directory before moving
it, ensure `knowledge_network` and `ai_network` exist, then run
`docker compose up -d --pull never` from the new directory. Update the database backup deployment to its
matching profile so it also joins `knowledge_network`.

For an in-place network migration, connect `db-backup` and all five Paperless
containers to `knowledge_network` using their container names as network aliases,
connect only `paperless` to `ai_network`, then disconnect the five Paperless
containers from `media_network`. These Docker network attachments survive container
restarts. Existing containers retain their original Compose source-path labels
until the next recreation from this directory.

Verify the webserver health, document count, document access, and database-backup
connectivity after migration. If rollback is needed, reconnect all five Paperless
containers to `media_network` with their container-name aliases before disconnecting
them from `knowledge_network`, restore the previous Compose network configuration,
and move the directory back. Preserve the volumes and local credentials throughout.

### Check Service Status
```bash
cd knowledgeServices/paperless
docker compose ps
```

### View Logs
```bash
docker compose logs -f paperless
docker compose logs -f paperless-db
```

### Restart Services
```bash
docker compose restart
```

### Verify Database Connection
```bash
docker exec -it paperless-db psql -U paperless -d paperless -c "\dt"
```

### Trigger Manual Backup
```bash
docker exec db-backup sh /usr/local/bin/backup-script.sh paperless
```

## Troubleshooting

- **Database connection errors**: Confirm `.env` credentials match between `paperless-db` and `paperless` service
- **OCR not working**: Check Tika and Gotenberg containers are healthy; review `docker logs paperless`
- **Documents not processing**: Verify Redis broker is running; check `PAPERLESS_REDIS` value in `.env`
- **Backup fails**: Confirm `PAPERLESS_DB_HOST=paperless-db` is reachable from `db-backup` on `knowledge_network`
