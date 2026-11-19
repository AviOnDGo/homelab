# Kasm Workspaces — Service Documentation

## Overview

Kasm Workspaces is a self-hosted container-streaming platform that delivers full desktop environments and individual applications directly to the browser over HTTPS. It provides disposable, isolated sessions (sandboxed browsing, remote desktops, containerised GUI apps) that leave no persistent state on the client device.

Kasm is deployed in `containerServices/kasm/` and is accessible exclusively via Nginx Proxy Manager.

---

## Components

| Container | Image | Internal Port | Protocol |
|-----------|-------|---------------|----------|
| `kasm` | `lscr.io/linuxserver/kasm:latest` | `3000` | HTTPS (self-signed TLS) |

---

## Volumes

| Volume | Mount Path | Purpose | Create Command |
|--------|-----------|---------|----------------|
| `kasm_filedata` | `/opt/kasm` | Kasm application data: user accounts, workspace definitions, session state, internal certificates | `docker volume create kasm_filedata` |

---

## Network

| Network | Type | Purpose |
|---------|------|---------|
| `container_network` | External | Category network for `containerServices`; provides internal DNS resolution |

Kasm does **not** bind any port to the host interface. All external access is routed through Nginx Proxy Manager.

---

## Configuration

All configuration is inlined in `docker-compose.yml`. No `.env` file is used.

| Variable | Value | Description |
|----------|-------|-------------|
| `PUID` | `1000` | Process user ID (standard linuxserver.io) |
| `PGID` | `1000` | Process group ID (standard linuxserver.io) |
| `TZ` | `UTC` | Container timezone |
| `shm_size` | `1gb` | Shared memory size — required for Chromium-based browser workspaces to function; set as a compose service key, not an environment variable |

> **Important**: `shm_size: "1gb"` must not be reduced. Chromium workspaces will crash at startup without sufficient shared memory.

---

## Operations

### Start
```bash
docker compose -f containerServices/kasm/docker-compose.yml up -d
```

### Stop
```bash
docker compose -f containerServices/kasm/docker-compose.yml down
```

### Restart
```bash
docker compose -f containerServices/kasm/docker-compose.yml restart kasm
```

### View logs
```bash
docker compose -f containerServices/kasm/docker-compose.yml logs -f kasm
```

### Force recreate (after config changes)
```bash
docker compose -f containerServices/kasm/docker-compose.yml up -d --force-recreate
```

---

## NPM Proxy Host Setup

Kasm requires special NPM configuration because its internal server uses HTTPS (not HTTP) and requires WebSocket support for the browser-streaming protocol.

1. In Nginx Proxy Manager, create a new **Proxy Host**
2. **Domain Names**: `kasm.<your-domain>`
3. **Scheme**: `https` *(not `http` — Kasm terminates TLS internally)*
4. **Forward Hostname / IP**: `kasm`
5. **Forward Port**: `3000`
6. **Enable**: `WebSockets Support` toggle ON
7. **SSL tab**: Enable SSL, enable "Force SSL"
8. **Advanced tab** → add the following to disable certificate verification:
   ```
   proxy_ssl_verify off;
   ```
   *(Required because Kasm uses a self-signed internal certificate)*

> **Verify**: After saving, navigate to `https://kasm.<your-domain>` — the Kasm login screen should appear.

---

## First-Run Setup

On first launch, Kasm initialises its database in `kasm_filedata`. This takes ~60 seconds.

1. Watch logs until you see startup complete:
   ```bash
   docker compose -f containerServices/kasm/docker-compose.yml logs -f kasm
   ```
2. Access via NPM URL → set the admin password when prompted
3. Log in and optionally add workspace images (e.g., Chromium, Firefox, Ubuntu Desktop)

---

## Troubleshooting

### Workspace crashes immediately on launch
- **Cause**: Insufficient shared memory
- **Fix**: Confirm `shm_size: "1gb"` is present in `docker-compose.yml` at the service level and recreate the container

### Container not reachable via NPM / 502 Bad Gateway
- **Cause**: NPM upstream scheme is `http` instead of `https`
- **Fix**: Edit the NPM proxy host and change the scheme to `https`; also confirm `proxy_ssl_verify off;` is in the Advanced config

### Kasm login page doesn't load / blank page in browser
- **Cause**: WebSocket support not enabled in NPM
- **Fix**: Edit the NPM proxy host and enable the "WebSockets Support" toggle

### Container takes long to start
- **Expected**: First boot initialises the database (~60 seconds). Subsequent starts are fast.

### Volume not found on startup
- **Fix**: Create the volume before starting: `docker volume create kasm_filedata`

### Network not found on startup
- **Fix**: Create the network before starting: `docker network create container_network`
