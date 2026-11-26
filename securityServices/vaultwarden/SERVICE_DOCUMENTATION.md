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

The admin panel is available at `<domain>/admin` when an `ADMIN_TOKEN` is configured. No admin token is configured by default, so the admin panel is disabled. If admin access is needed, configure `ADMIN_TOKEN` through a secure, untracked deployment mechanism.

---

## Configuration

New user registrations are disabled by `SIGNUPS_ALLOWED: "false"` in `docker-compose.yml`. To change this setting, update the Compose environment and recreate the container.

Set `DOMAIN` in the Compose environment to the full public URL (e.g., `https://vault.yourdomain.com`) if you need URL-dependent features such as invitations or attachment downloads.

---

## Post-Deployment Checklist

- [ ] Log in with a vault account and enroll at least one MFA method (TOTP, YubiKey, or Duo)
- [ ] Confirm MFA authenticates successfully before marking deployment complete
- [ ] Confirm new user registrations remain disabled

---

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---|---|---|
| Admin panel is unavailable | `ADMIN_TOKEN` is not configured | Configure `ADMIN_TOKEN` securely if admin access is needed |
| Can't connect from Bitwarden client | NPM proxy misconfigured | Verify the NPM proxy host and, if needed, set `DOMAIN` in the Compose environment |
| Container exits immediately | Invalid Compose configuration | Check `docker compose logs vaultwarden` |
