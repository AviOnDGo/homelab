# Radicale — Service Documentation

## Overview

Radicale is a lightweight, privacy-focused CalDAV and CardDAV calendar and contact synchronization server. It is deployed in the homelab under the `knowledgeServices` category and routed exclusively through Nginx Proxy Manager. All calendars, contacts, user credentials, and configuration files are persisted in the named external volume `radicale_filedata`.

---

## Components

| Service | Container | Image | Role | Internal Port |
|---|---|---|---|---|
| `radicale` | `radicale` | `ghcr.io/kozea/radicale:stable` | CalDAV / CardDAV server | 5232 |

---

## Volumes & Data

All persistent collections and user data are stored in a named external Docker volume, with configuration mounted from host `/etc/radicale`.

| Volume / Mount | Purpose | Container Path |
|---|---|---|
| `/etc/radicale` | Configuration files (e.g., config, rights) | `/etc/radicale` |
| `radicale_filedata` | Calendar collections (.ics), contacts (.vcf), and htpasswd credentials | `/var/lib/radicale` |

Create the volume before first start:

```bash
docker volume create radicale_filedata
```

---

## Network

Radicale runs on the `knowledge_network` Docker network (external). Port 5232 is **not** exposed directly on the host — all client requests are reverse-proxied via Nginx Proxy Manager.

```bash
# Create the network if not already present
docker network inspect knowledge_network >/dev/null 2>&1 || docker network create knowledge_network
```

---

## Configuration

Default environment variables are defined in `docker-compose.yml`:

| Variable | Description | Value |
|---|---|---|
| `TZ` | Container Timezone | `UTC` |

Radicale runtime configuration can be customized by placing a custom `config` file inside `/etc/radicale/config`.

### Authentication Setup (htpasswd / bcrypt)

Radicale supports user authentication via an `htpasswd` file stored at `/var/lib/radicale/users` or `/etc/radicale/users`.

To generate a new user credential using bcrypt encryption:

```bash
# Example: Create user "homelab" inside the running container
docker exec -it radicale htpasswd -b -B /var/lib/radicale/users homelab "YourSecurePassword"
```

---

## Operations

```bash
# Start service
docker compose -f knowledgeServices/radicale/docker-compose.yml up -d

# Stop service
docker compose -f knowledgeServices/radicale/docker-compose.yml down

# Restart service
docker compose -f knowledgeServices/radicale/docker-compose.yml restart radicale

# Follow logs
docker compose -f knowledgeServices/radicale/docker-compose.yml logs -f radicale
```

---

## Nginx Proxy Manager Setup

Configure a proxy host in Nginx Proxy Manager:

| Field | Value |
|---|---|
| Scheme | `http` |
| Forward Hostname / IP | `radicale` |
| Forward Port | `5232` |
| WebSockets Support | Enabled |
| Block Common Exploits | Enabled |

### Client Sync Settings
- **iOS / macOS CalDAV URL**: `https://<your-radicale-domain>/<username>/`
- **Android (DAVx⁵) CalDAV/CardDAV Base URL**: `https://<your-radicale-domain>/`
- **Thunderbird / Evolution / WebDAV**: `https://<your-radicale-domain>/<username>/<calendar-id>/`

---

## Backup Integration

Radicale is registered in `backupServices/filedata` under the `archive` backup mode.

- **Source Volume**: `radicale_filedata`
- **Backup Schedule**: Configurable via `RADICALE_CRON_SCHEDULE` (Default: `0 3 * * *`)
- **Retention Period**: Configurable via `RADICALE_RETENTION_DAYS` (Default: `7` days)
- **Encryption**: GPG AES256 symmetric encryption
