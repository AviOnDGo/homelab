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

This deployment intentionally leaves `ADMIN_TOKEN` unset, so the admin panel at `<domain>/admin` remains disabled.

---

## Configuration

New user registrations are disabled by `SIGNUPS_ALLOWED: "false"` in `docker-compose.yml`. A saved `signups_allowed` value in `/data/config.json` can override the Compose setting. If that file exists, verify that `signups_allowed` is `false` or absent. If it is `true`, stop the container, change only that value to `false` with a JSON-aware editor, and start the container again.

The Compose service no longer passes values from `.env` to the container. Before recreating an existing deployment, if it relies on `DOMAIN` for URL-dependent features such as invitations or attachment downloads, copy that URL into the Compose `environment:` section (for example, `DOMAIN: "https://vault.yourdomain.com"`). Do not copy `ADMIN_TOKEN`; the admin panel is intentionally disabled. If an existing `/data/config.json` contains an `admin_token` entry, remove that entry with a JSON-aware editor as part of the migration.

---

## Post-Deployment Checklist

- [ ] Log in with a vault user account and enroll at least one MFA method (TOTP, YubiKey, or Duo)
- [ ] Confirm MFA authenticates successfully before marking deployment complete
- [ ] If `/data/config.json` exists, confirm `signups_allowed` is `false` or absent

---

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---|---|---|
| Admin panel is unavailable | Expected: this deployment leaves `ADMIN_TOKEN` unset | No action is needed; the admin panel is intentionally disabled |
| New user registrations remain enabled | `/data/config.json` contains `signups_allowed: true` | Stop the container, change only `signups_allowed` to `false` with a JSON-aware editor, and start the container again |
| Can't connect from Bitwarden client | NPM proxy misconfigured or required `DOMAIN` is not set | Verify the NPM proxy host and, if needed, set `DOMAIN` in the Compose environment |
| Container exits immediately | Invalid Compose configuration | Check `docker compose logs vaultwarden` |
