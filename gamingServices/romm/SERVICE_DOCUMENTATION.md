# RomM Service Documentation

## Overview

RomM (`gamingServices/romm/`) is a self-hosted game library manager: it scans a ROM library, fetches metadata/covers/screenshots from IGDB and other providers, and serves a web UI for browsing and downloading games/saves/states.

## Architecture

| Container   | Image                  | Role                                  |
|-------------|------------------------|----------------------------------------|
| `romm`      | `rommapp/romm:latest`  | Web application and API (port 8080)   |
| `romm-db`   | `postgres:16`          | Game library metadata storage         |

Both containers join `games_network`. `romm` depends on `romm-db` with `condition: service_healthy`.

## Volumes

| Volume              | Mounted at (in container)                            | Purpose                                   | External | Backed up |
|---------------------|------------------------------------------------------|--------------------------------------------|----------|-----------|
| `romm_postgresdata` | (`romm-db`) `/var/lib/postgresql`                    | RomM database, metadata, users, and app state | no       | Local Postgres backup |
| `romm_filedata` | (`romm`) `/romm` | ROM library, uploaded assets, saves, and states | yes | Local filedata backup to Filen |

The `romm_filedata` volume contains RomM's `library/` and `assets/` directories.
Both directories are required for the Local filedata backup to run.

## Environment Variables

See [`.env.example`](.env.example) for the full list. Key variables:
- `DB_NAME`, `DB_USER`, `DB_PASSWD`, `DB_PORT` — must match `romm-db`'s `POSTGRES_DB`/`POSTGRES_USER`/`POSTGRES_PASSWORD`.
- `ROMM_AUTH_SECRET_KEY` — generate with `openssl rand -hex 32`.
- `IGDB_CLIENT_ID` / `IGDB_CLIENT_SECRET`, `SCREENSCRAPER_USER` / `SCREENSCRAPER_PASSWORD`, `RETROACHIEVEMENTS_API_KEY`, `STEAMGRIDDB_API_KEY`, `HASHEOUS_API_ENABLED` — optional metadata provider credentials.

## Network & Access

RomM has no direct host port mapping. Access is exclusively via Nginx Proxy Manager, proxying to `romm:8080` over `games_network`. Configure an NPM proxy host pointing at the `romm` container before relying on external access.

## Operational Commands

```bash
# Start
cd gamingServices/romm
docker compose up -d

# Stop
docker compose down

# Logs
docker compose logs -f romm
docker compose logs -f romm-db

# Check romm-db health
docker inspect --format='{{.State.Health.Status}}' romm-db
```

## Backup & Restore

- `romm_postgresdata` is registered with the **default** and **Local** Postgres
  backup profiles (`backupServices/postgres/backup-databases.conf`), backed up
  to Dropbox at `/App_acc/romm` by the Local `db-backup` profile.
- `romm_filedata` is registered in `backupServices/filedata/backup-volumes.conf` for the **default** and **Local** host profiles. It syncs daily to `filen-crypt:/Romm` with 30-day retention; the Filen backend and rclone crypt layer both encrypt data.
- The sync runs one-way from the volume to Filen under `/Romm/current/`. Any files left at `/Romm` by the previous Filen CLI sync remain untouched and can be removed after the new backup is verified.
- Configure `FILEN_EMAIL`, `FILEN_PASSWORD`, `FILEN_API_KEY`, and `RCLONE_CRYPT_PASSWORD` in `backupServices/filedata/.env`. Generate the API key with `filen export-api-key` using the Filen CLI; the key is sensitive.
- Configure the RomM destination in `backupServices/filedata/path.local`.
- See [`RESTORE_GUIDE.md`](RESTORE_GUIDE.md) and [`restore.sh`](restore.sh) for recovery steps.
- Run `./restore.sh` from this directory for coordinated filedata and database
  recovery. The script prompts before replacing existing data and restarts RomM
  and the Local filedata backup service after recovery.
- Database recovery waits for the final PostgreSQL TCP listener at `127.0.0.1`,
  bypassing the temporary socket-only initialization server. It checks the
  configured `DB_NAME` through `postgres`, creates it if absent, and stops on
  lookup or creation errors before importing the SQL dump.

## Troubleshooting

- **RomM can't reach the database**: check `romm-db` health with `docker inspect --format='{{.State.Health.Status}}' romm-db` and review `docker compose logs romm-db`.
- **Metadata missing after a restore**: confirm both the latest `romm_*.sql.zst.gpg` backup and the `romm_filedata` Filen sync were restored successfully; trigger a manual library rescan from the RomM web UI if needed.
- **No access via NPM**: verify the NPM proxy host targets `romm:8080` over `games_network`.
