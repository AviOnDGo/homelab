# Firefox Sync Service Documentation

## Overview

Self-hosted Firefox Sync server (`syncstorage-rs`) running in `securityServices/firefoxsync/`. Keeps browser bookmarks, history, passwords, open tabs, and add-ons synchronised entirely within the homelab — no data flows to Mozilla's hosted sync endpoints. Authentication still uses Mozilla Accounts (`accounts.firefox.com`); only storage is self-hosted.

## Components

| Container | Image | Internal Port | Role |
|-----------|-------|---------------|------|
| `syncserver` | `ghcr.io/mozilla-services/syncstorage-rs/syncserver-postgres:0.22.0` | 8000 | Sync Storage + Token Server |
| `firefoxsync-db` | `postgres:16` | 5432 | PostgreSQL database |

## Volumes

| Volume | Mount Path | Purpose | Create Command |
|--------|-----------|---------|----------------|
| `firefoxsync_postgresdata` | `/var/lib/postgresql/data` (in `firefoxsync-db`) | PostgreSQL data directory | `docker volume create firefoxsync_postgresdata` |

The PostgreSQL database is named `firefoxsync`. Changing `POSTGRES_DB` does not
rename a database in an existing volume; migrate or restore any existing data
before using this configuration with an older volume.

## Network

- Both containers join `security_network` (external)
- Port 8000 is **not** exposed to the host — all external access via Nginx Proxy Manager
- NPM reaches `syncserver` by container name at `http://syncserver:8000`

## Configuration

### `.env` variables (secrets — copy `.env.example` to `.env`)

| Variable | Description |
|----------|-------------|
| `SYNC_MASTER_SECRET` | Cryptographic secret for token signing. Use a long random string. |
| `SYNC_POSTGRES_PASSWORD` | PostgreSQL password shared between syncserver and firefoxsync-db. |
| `SYNC_TOKENSERVER__INIT_NODE_URL` | Public URL of the sync server (e.g. `https://sync.yourdomain.com`). |

### Inlined environment variables (in `docker-compose.yml`)

| Variable | Value | Notes |
|----------|-------|-------|
| `TZ` | `UTC` | Timezone |
| `SYNC_HOST` | `0.0.0.0` | Listen on all interfaces inside the container |
| `SYNC_PORT` | `8000` | HTTP port |
| `SYNC_TOKENSERVER__ENABLED` | `true` | Enable the combined Token Server |
| `SYNC_TOKENSERVER__RUN_MIGRATIONS` | `true` | Auto-run DB migrations on startup |
| `SYNC_TOKENSERVER__FXA_EMAIL_DOMAIN` | `api.accounts.firefox.com` | Mozilla Accounts domain |
| `SYNC_TOKENSERVER__FXA_OAUTH_SERVER_URL` | `https://oauth.accounts.firefox.com` | Mozilla OAuth endpoint |
| `SYNC_HUMAN_LOGS` | `false` | JSON structured logs |
| `RUST_LOG` | `info` | Log level |

## Operations

```bash
# Start
docker compose -f securityServices/firefoxsync/docker-compose.yml up -d

# Stop
docker compose -f securityServices/firefoxsync/docker-compose.yml down

# Restart
docker compose -f securityServices/firefoxsync/docker-compose.yml restart

# Logs (both containers)
docker compose -f securityServices/firefoxsync/docker-compose.yml logs -f

# Logs (syncserver only)
docker compose -f securityServices/firefoxsync/docker-compose.yml logs -f syncserver

# Logs (database only)
docker compose -f securityServices/firefoxsync/docker-compose.yml logs -f firefoxsync-db
```

## NPM Proxy Host Setup

1. In Nginx Proxy Manager, add a new Proxy Host:
   - **Domain Names**: `sync.yourdomain.com`
   - **Scheme**: `http`
   - **Forward Hostname / IP**: `syncserver`
   - **Forward Port**: `8000`
   - Enable **SSL** with Let's Encrypt
2. Verify the heartbeat: `curl https://sync.yourdomain.com/__heartbeat__` should return HTTP 200

## Firefox Client Configuration

### Desktop

1. Navigate to `about:config` in the address bar
2. Search for `identity.sync.tokenserver.uri`
3. Set the value to `https://sync.yourdomain.com/1.0/sync/1.5`
4. Restart Firefox
5. Sign in with your Mozilla Account — sync will now use the self-hosted server
6. Verify in `about:sync-log`

### Mobile (Firefox for Android / iOS)

1. Go to **Settings → About Firefox**
2. Tap the Firefox logo **6 times** to enable the debug menu
3. Go back to the main Settings menu
4. Tap **Sync Debug**
5. Tap **Custom sync server** and set it to `https://sync.yourdomain.com/1.0/sync/1.5`
6. Tap **Stop Firefox** in the same menu to apply the change
7. Sign in with your Mozilla Account

## Health Check

From within `security_network` (e.g. inside another container on the network):
```bash
curl -f http://syncserver:8000/__heartbeat__
```

From the host (after NPM proxy is configured):
```bash
curl -f https://sync.yourdomain.com/__heartbeat__
```

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| `syncserver` exits immediately after start | PostgreSQL not ready; `depends_on` healthcheck not met | Check `firefoxsync-db` logs: `docker logs firefoxsync-db` |
| Migration errors in syncserver logs | Database connection failure | Verify `SYNC_POSTGRES_PASSWORD` matches in both `.env` and `firefoxsync-db` environment |
| NPM returns 502 | syncserver not running or wrong port | Confirm container is healthy: `docker ps | grep syncserver` |
| Firefox sync fails with "Unable to connect" | Wrong `identity.sync.tokenserver.uri` | Verify the URL ends with `/1.0/sync/1.5` and NPM proxy is working |
| `firefoxsync_postgresdata` volume missing | Volume not created before first run | `docker volume create firefoxsync_postgresdata` then restart |
