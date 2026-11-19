# Vaultwarden Service Documentation

## Overview

Vaultwarden is a lightweight, self-hosted implementation of the Bitwarden password manager server. It provides password vault, secure notes, and TOTP management accessible via any Bitwarden-compatible client or web browser.

**Network:** `security_network`  
**Volume:** `vaultwarden_filedata` → `/data`  
**Access:** Via Nginx Proxy Manager (NPM) reverse proxy — no port directly exposed on host.

---

## Start / Stop

```bash
# Start
cd securityServices/vaultwarden
docker compose up -d

# Stop
docker compose down

# Restart
docker compose restart vaultwarden
```

---

## View Logs

```bash
cd securityServices/vaultwarden
docker compose logs -f vaultwarden
```

---

## Access

Vaultwarden is proxied through NPM. Access through the configured domain (e.g., `https://vault.yourdomain.com`).

The admin panel is available at `<domain>/admin` and requires the `ADMIN_TOKEN` set in `.env`.

---

## Configuration (`.env`)

Key variables (see `.env` for full list):

| Variable | Description |
|---|---|
| `ADMIN_TOKEN` | Bcrypt-hashed token for accessing the `/admin` panel |
| `DOMAIN` | Full URL Vaultwarden is served from (e.g., `https://vault.yourdomain.com`) |
| `SIGNUPS_ALLOWED` | Set to `false` to disable new registrations after initial setup |

---

## Post-Deployment Checklist

- [ ] Log in with admin account and enroll at least one MFA method (TOTP, YubiKey, or Duo)
- [ ] Confirm MFA authenticates successfully before marking deployment complete
- [ ] Set `SIGNUPS_ALLOWED=false` once all users have registered

---

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---|---|---|
| Admin panel returns 404 | `ADMIN_TOKEN` not set in `.env` | Set `ADMIN_TOKEN` and restart |
| Can't connect from Bitwarden client | `DOMAIN` not set or NPM proxy misconfigured | Verify NPM proxy host and `DOMAIN` in `.env` |
| Container exits immediately | Invalid `.env` configuration | Check `docker compose logs vaultwarden` |
