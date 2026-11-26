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

The default deployment leaves `ADMIN_TOKEN` and `DISABLE_ADMIN_TOKEN` unset. The admin panel at `<domain>/admin` is disabled only after any saved `admin_token` has also been removed as described below.

---

## Configuration

New user registrations are disabled by `SIGNUPS_ALLOWED: "false"` in `docker-compose.yml`, but saved settings in `/data/config.json` take precedence. A nonempty `signups_domains_whitelist` permits registration from those domains even when signups are otherwise disabled. Organization invitations can still allow invited users to register.

### Migrating an existing deployment

The Compose service no longer passes values from `.env` to the container. Before recreating it:

1. Preserve any required settings previously supplied through `.env`, including `DOMAIN` and SMTP settings needed for email 2FA, invitations, or other mail. Put non-secret settings in a private Compose override outside the repository. Provision credentials outside version control as files mounted under `/run/secrets/`; Vaultwarden supports the `_FILE` suffix for configuration values. For example, an override can contain:

   ```yaml
   services:
     vaultwarden:
       environment:
         DOMAIN: "https://vault.yourdomain.com"
         SMTP_HOST: "smtp.yourdomain.com"
         SMTP_FROM: "vaultwarden@yourdomain.com"
         SMTP_PORT: "587"
         SMTP_SECURITY: "starttls"
         SMTP_USERNAME_FILE: "/run/secrets/smtp_username"
         SMTP_PASSWORD_FILE: "/run/secrets/smtp_password"
       volumes:
         - /absolute/path/to/smtp_username:/run/secrets/smtp_username:ro
         - /absolute/path/to/smtp_password:/run/secrets/smtp_password:ro
   ```

   Replace the placeholders and preserve any other settings your deployment requires. Protect the override and credential files with appropriate permissions. Do not copy `ADMIN_TOKEN` or `DISABLE_ADMIN_TOKEN`, or a nonempty `SIGNUPS_DOMAINS_WHITELIST`. If SMTP is unauthenticated, omit the username and password file entries.
2. Stop Vaultwarden. If `/data/config.json` exists in `vaultwarden_filedata`, use a JSON-aware editor to remove `admin_token`, set `signups_allowed` to `false` or remove it, and empty or remove `signups_domains_whitelist`. Update or remove a saved `domain` if it differs from the intended `DOMAIN`; also reconcile saved SMTP values because they override the environment. Preserve the remaining settings and protect the file and any backups because they can contain secrets.
3. Recreate the service with the override (use its absolute path on every subsequent Compose operation):

   ```bash
   docker compose -f docker-compose.yml -f /absolute/path/to/vaultwarden.override.yml up -d
   ```

   If no override is needed, use `docker compose up -d`. Verify that `/admin` is unavailable, uninvited registrations are disabled, and required mail-dependent features, including email 2FA if used, work.

---

## Post-Deployment Checklist

- [ ] Log in with a vault user account and enroll at least one MFA method (TOTP, YubiKey, or Duo)
- [ ] Confirm MFA authenticates successfully before marking deployment complete
- [ ] If `/data/config.json` exists, confirm `admin_token` is absent, `signups_allowed` is `false` or absent, and `signups_domains_whitelist` is empty or absent

---

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---|---|---|
| Admin panel is available | A saved `admin_token` or an admin setting enables it | Remove the saved token and ensure `ADMIN_TOKEN` and `DISABLE_ADMIN_TOKEN` are unset, then recreate the container |
| New user registrations remain enabled | Saved `signups_allowed` is `true` or the domain whitelist is nonempty | Stop the container and correct both saved settings as described above |
| Can't connect from Bitwarden client | NPM proxy misconfigured or required `DOMAIN` is incorrect | Verify the NPM proxy host, Compose environment, and any saved `domain` |
| Container exits immediately | Invalid Compose configuration | Check `docker compose logs vaultwarden` |
