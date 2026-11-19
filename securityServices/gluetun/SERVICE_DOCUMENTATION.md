# Gluetun – ProtonVPN WireGuard

VPN client container providing a ProtonVPN free-tier WireGuard tunnel for the `security_network`. Other containers can route all their traffic through this container using Docker's `network_mode: "service:gluetun"`. Gluetun also provides an HTTP proxy on `gluetun:8888` for services that need proxied HTTP(S) egress while remaining on their own category network.

---

## Required `.env` Variables

Add these to `securityServices/gluetun/.env` (never commit this file):

| Variable | Description | Where to get it |
|---|---|---|
| `WIREGUARD_PRIVATE_KEY` | Your WireGuard private key | ProtonVPN dashboard → Downloads → WireGuard configuration → export `.conf` → `PrivateKey` field |
| `WIREGUARD_ADDRESSES` | WireGuard interface address | Same `.conf` file → `Address` field (e.g., `10.2.0.2/32`) |
| `SERVER_COUNTRIES` | Comma-separated free-tier country names | ProtonVPN free servers are available in `Japan`, `Netherlands`, `USA` |

> **Note**: `FREE_ONLY=on` is set in `docker-compose.yml` to ensure only ProtonVPN free-tier servers are selected.

---

## Start / Stop / Restart

```bash
# Start
docker compose -f securityServices/gluetun/docker-compose.yml up -d

# Stop
docker compose -f securityServices/gluetun/docker-compose.yml down

# Restart
docker compose -f securityServices/gluetun/docker-compose.yml restart

# Recreate (after config change)
docker compose -f securityServices/gluetun/docker-compose.yml up -d --force-recreate

# View logs
docker compose -f securityServices/gluetun/docker-compose.yml logs -f
```

---

## Verify Tunnel Health

Check that traffic exits through a ProtonVPN IP:

```bash
docker exec gluetun wget -qO- https://ifconfig.me/ip
```

Expected: a ProtonVPN IP address (not your home IP). The Gluetun logs also show
the public IP on startup. The address below is a documentation-only example:

```
INFO [ip getter] Public IP address is 203.0.113.10 (example location ...)
```

---

## Attaching Another Container via VPN

To route a container's traffic through the VPN, add it to the same `docker-compose.yml` and set:

```yaml
services:
  my-service:
    image: ...
    network_mode: "service:gluetun"
    depends_on:
      - gluetun
```

The service will share Gluetun's network stack and all its traffic will exit through the VPN.

---

## Internal HTTP Proxy

The HTTP proxy is enabled with `HTTPPROXY=on` and is reachable at `http://gluetun:8888` from containers on `security_network`. Keep the host port mapping commented out; the proxy is intentionally internal.

```yaml
    environment:
      http_proxy: http://gluetun:8888
      https_proxy: http://gluetun:8888
      no_proxy: localhost,127.0.0.1
    networks:
      - default
      - security_network
```

Proxy consumers retain their category network and join `security_network` to reach the proxy. `no_proxy` lists internal destinations that must bypass it.

---

## Rotating WireGuard Credentials

ProtonVPN WireGuard keys do not expire automatically but should be rotated periodically:

1. Go to ProtonVPN dashboard → Downloads → WireGuard configuration
2. Delete the old key and generate a new one
3. Update `WIREGUARD_PRIVATE_KEY` and `WIREGUARD_ADDRESSES` in `securityServices/.env`
4. Recreate the container: `docker compose -f securityServices/gluetun/docker-compose.yml up -d --force-recreate`

---

## Rollback

```bash
# Stop and remove the container (no data loss – Gluetun is stateless)
docker compose -f securityServices/gluetun/docker-compose.yml down

# Remove credentials from securityServices/.env if desired
```
