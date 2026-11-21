# Firefox — Service Documentation

## Overview

Firefox is a self-hosted, containerised browser running in `containerServices/firefox/`. It streams a full Firefox browser session directly to any web browser via noVNC over HTTP (port 5800 inside the container, mapped to host port 3000). It provides isolated, persistent browser sessions without requiring a separate remote desktop platform or a secure context.

Firefox is deployed in `containerServices/firefox/` and is accessible directly on host port 3000 or via Nginx Proxy Manager.

---

## Components

| Container | Image | Internal Port | Protocol | Notes |
|-----------|-------|---------------|----------| ------|
| `firefox` | `jlesage/firefox:latest` | `5800` | HTTP (noVNC web UI) | Mapped to host port 3000; also NPM upstream |

---

## Volumes

| Compose Alias | External Volume | Mount Path | Purpose | Create Command |
|---------------|----------------|-----------|---------|----------------|
| `filedata` | `firefox_filedata` | `/config` | Browser profile, bookmarks, extensions, preferences | `docker volume create firefox_filedata` |

---

## Network

| Interface | Details |
|-----------|---------|
| Network | `container_network` (via compose `default` alias) |
| Port 3000 (host) | Mapped to container port 5800 — noVNC web UI; also used by NPM upstream |
| Port 5900 | Internal VNC port — not exposed on host |

Firefox joins `container_network` via the compose `default` network alias (`networks: default: external: true, name: container_network`).

---

## Configuration

No environment variables are set. Only `shm_size` is configured.

| Key | Value | Description |
|-----|-------|-------------|
| `shm_size` | `4gb` | Shared memory allocated to the container. Required for Firefox to render without crashes. Set as a compose service-level key, not an environment variable. |

> **Important**: Do not reduce `shm_size` below `1gb`. Firefox will crash on startup or during page rendering without sufficient shared memory.

---

## Operations

### Start
```bash
docker compose -f containerServices/firefox/docker-compose.yml up -d
```

### Stop
```bash
docker compose -f containerServices/firefox/docker-compose.yml down
```

### Restart
```bash
docker compose -f containerServices/firefox/docker-compose.yml restart firefox
```

### Logs
```bash
docker compose -f containerServices/firefox/docker-compose.yml logs -f firefox
```

---

## NPM Proxy Host Setup

To access Firefox via Nginx Proxy Manager:

1. In NPM, create a new **Proxy Host**
2. **Domain names**: `firefox.<your-domain>`
3. **Forward Hostname / IP**: `firefox`
4. **Forward Port**: `5800`
5. **Scheme**: `http`
6. Enable **WebSockets Support** ← required for noVNC streaming
7. Add SSL certificate as usual

> **Note**: Use `http` as the NPM upstream scheme. The noVNC interface (port 5800) is plain HTTP.

---

## Troubleshooting

### Firefox crashes immediately on startup
- Check `shm_size` is set to `"4gb"` in `docker-compose.yml`
- Run `docker inspect firefox | grep ShmSize` — should show `4294967296` (4 GB in bytes)

### noVNC interface does not load via NPM
- Verify **WebSockets Support** is enabled on the NPM proxy host
- Ensure the upstream is `http://firefox:5800`
- Check that NPM and Firefox containers can reach each other via `container_network`

### Profile data lost after container recreation
- The `firefox_filedata` volume should persist data across recreations
- Verify the volume is correctly mounted: `docker inspect firefox | grep firefox_filedata`
- If the volume was deleted, restore from backup using `RESTORE_GUIDE.md`
