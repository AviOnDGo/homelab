# AFFiNE — Service Documentation

## Overview

AFFiNE is a collaborative workspace that blends the best of a wiki, whiteboard, and spreadsheet into a single application. It is self-hosted in the homelab under the `knowledgeServices` category and routed exclusively through Nginx Proxy Manager.

---

## Components

| Service | Container | Image | Role | Internal Port |
|---|---|---|---|---|
| `affine` | `affine` | `ghcr.io/toeverything/affine:${AFFINE_REVISION}` | Main application server | 3010 |
| `affine_migration` | `affine_migration` | `ghcr.io/toeverything/affine:${AFFINE_REVISION}` | One-shot pre-deploy migration job | — |
| `affine-cache` | `affine-cache` | `redis:7.2-alpine` | Task queue / session cache | 6379 |
| `affine-db` | `affine-db` | `pgvector/pgvector:pg16` | Primary database | 5432 |

---

## Volumes & Data

All persistent data is stored in external named Docker volumes.

| Volume | Purpose | Location |
|---|---|---|
| `affine_filedata` | Uploaded files, images, attachments, and AFFiNE runtime state | `/root/.affine` in container |
| `affine_postgresdata` | PostgreSQL data directory | `/var/lib/postgresql/data` in container |

Create volumes (if not already present):

```bash
docker volume create affine_filedata
docker volume create affine_postgresdata
```

---

## Network

AFFiNE runs on the `knowledge_network` Docker network (external). Port 3010 is **not** exposed directly on the host — all traffic is routed via Nginx Proxy Manager.

```bash
# Create the network if not present
docker network inspect knowledge_network >/dev/null 2>&1 || docker network create knowledge_network
```

---

## Configuration

All secrets and configuration are loaded from `knowledgeServices/affine/.env` (not committed to git).

| Variable | Description | Default |
|---|---|---|
| `AFFINE_REVISION` | Image tag to deploy | `stable` |
| `PORT` | Internal container port (reference only) | `3010` |
| `AFFINE_SERVER_HOST` | Hostname for outgoing links | `localhost` |
| `DB_USERNAME` | PostgreSQL username | `affine` |
| `DB_PASSWORD` | PostgreSQL password | *(set in .env)* |
| `DB_DATABASE` | PostgreSQL database name | `affine` |

---

## Start / Stop / Logs

```bash
# First-time setup (creates network, volumes, starts services)
cd knowledgeServices/affine/
./setup_affine.sh

# Start
docker compose up -d

# Stop
docker compose down

# Restart a single service
docker compose restart affine

# Logs
docker compose logs -f affine
docker compose logs -f affine_migration
docker compose logs -f affine-cache
docker compose logs -f affine-db

# Status
docker compose ps
```

---

## Nginx Proxy Manager

After starting the stack, add a proxy host in NPM:

- **Domain Name**: your chosen domain (e.g., `affine.yourdomain.com`)
- **Scheme**: `http`
- **Forward Hostname/IP**: `affine`
- **Forward Port**: `3010`
- Enable **Websockets Support** (required for AFFiNE real-time collaboration)

---

## Backup Coverage

AFFiNE has two backup integrations:

### PostgreSQL Database (`affine_postgresdata`)

Backed up by `backupServices/postgres/` (`db-backup` service):
- **Schedule**: Daily at 03:15 (`15 3 * * *`)
- **Retention**: 30 days
- **Encryption**: GPG AES256
- **Storage**: Dropbox at `${AFFINE_DROPBOX_BACKUP_PATH}`

Required `.env` additions in `backupServices/postgres/.env`:
```env
AFFINE_DB_HOST=affine-db
AFFINE_DB_USER=affine
AFFINE_DB_PASSWORD=<your_password>
AFFINE_DB_NAME=affine
AFFINE_BACKUP_NAME=backup_affine
AFFINE_DROPBOX_BACKUP_PATH=/Apps/affine
AFFINE_BACKUP_RETENTION_DAYS=30
```

### Filedata Volume (`affine_filedata`)

Backed up by `backupServices/filedata/docker-compose.local.yml` (`filedata-backup` service):
- **Schedule**: Configurable via `AFFINE_CRON_SCHEDULE` in `backupServices/filedata/.env`
- **Encryption**: GPG AES256
- **Storage**: Dropbox at `${AFFINE_DROPBOX_PATH}`

Required `.env` additions in `backupServices/filedata/.env`:
```env
AFFINE_CRON_SCHEDULE=25 2 * * *
AFFINE_DROPBOX_PATH=/Apps/affine
AFFINE_RETENTION_DAYS=30
```

**Manual backup**:
```bash
# Database
docker exec db-backup sh /usr/local/bin/backup-script.sh affine

# Filedata
docker exec filedata-backup /bin/bash /usr/local/bin/backup-script.sh affine
```

## Restore

Use [`restore.sh`](restore.sh) as the primary restore entrypoint for AFFiNE. The script restores the latest Dropbox backups, recreates `affine_filedata` and `affine_postgresdata`, waits for `affine-db` readiness, and keeps the stack down if a restore step fails so the operator can inspect the volumes before retrying.

---

## Updating

AFFiNE is managed by Watchtower. To update manually:

```bash
docker compose pull affine
docker compose up -d affine
```

> **Note**: `affine-db` (pgvector/pgvector:pg16) should **not** be updated automatically across major versions. A Watchtower exclusion label may be added in a future change.
