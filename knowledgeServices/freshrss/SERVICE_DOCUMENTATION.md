# FreshRSS — Service Documentation

## Overview

FreshRSS is a self-hosted RSS/Atom feed aggregator. It is deployed in the homelab under the `knowledgeServices` category and routed exclusively through Nginx Proxy Manager. Feed subscriptions, read/unread state, and user configuration are all stored in the named external volume `freshrss_filedata`.

---

## Components

| Service | Container | Image | Role | Internal Port |
|---|---|---|---|---|
| `freshrss` | `freshrss` | `freshrss/freshrss:latest` | Feed aggregator | 80 |

---

## Volumes & Data

All persistent data is stored in a named external Docker volume.

| Volume | Purpose | Container Path |
|---|---|---|
| `freshrss_filedata` | Application data, SQLite database, extensions, configuration | `/var/www/FreshRSS` |

Create the volume before first start:

```bash
docker volume create freshrss_filedata
```

---

## Network

FreshRSS runs on the `knowledge_network` Docker network (external). Port 80 is **not** exposed directly on the host — all traffic is routed via Nginx Proxy Manager.

```bash
# Create the network if not already present
docker network inspect knowledge_network >/dev/null 2>&1 || docker network create knowledge_network
```

---

## Configuration

All configuration is inlined in `docker-compose.yml`. No `.env` file is required.

| Variable | Description | Value |
|---|---|---|
| `TZ` | Timezone | `UTC` |
| `CRON_MIN` | Feed refresh interval (minute pattern) | `*/15` |

To change the refresh interval, edit `CRON_MIN` in `docker-compose.yml` and recreate the container.

---

## Operations

```bash
# Start
docker compose -f knowledgeServices/freshrss/docker-compose.yml up -d

# Stop
docker compose -f knowledgeServices/freshrss/docker-compose.yml down

# Restart
docker compose -f knowledgeServices/freshrss/docker-compose.yml restart freshrss

# Follow logs
docker compose -f knowledgeServices/freshrss/docker-compose.yml logs -f freshrss
```

---

## Nginx Proxy Manager Setup

Add a new proxy host in NPM:

| Field | Value |
|---|---|
| **Domain Names** | `freshrss.<your-domain>` |
| **Scheme** | `http` |
| **Forward Hostname / IP** | `freshrss` |
| **Forward Port** | `80` |
| **SSL Certificate** | Select or request a Let's Encrypt cert |

NPM resolves `freshrss` to the container via Docker DNS on `knowledge_network`.

---

## First-Run Setup

On first access, FreshRSS will prompt for database and admin account configuration. Complete the setup wizard in the web UI before adding feeds.

---

## Troubleshooting

### Feeds not refreshing automatically

Check that `CRON_MIN` is set correctly:
```bash
docker inspect freshrss | grep CRON_MIN
```
Check cron logs inside the container:
```bash
docker exec freshrss cat /var/log/freshrss/cron.log
```

### Container not reachable via NPM

1. Confirm the container is running and on the correct network:
   ```bash
   docker ps | grep freshrss
   docker network inspect knowledge_network | grep freshrss
   ```
2. Confirm NPM's proxy host points to `freshrss:80` (not `localhost:80`).
3. Check NPM logs for proxy errors.

### Volume data missing after recreate

Confirm the external volume exists and was not accidentally removed:
```bash
docker volume inspect freshrss_filedata
```
If missing, restore from backup — see `RESTORE_GUIDE.md`.
