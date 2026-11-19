# Hermes Service Documentation

Hermes runs an AI agent gateway and an authenticated dashboard. Nginx Proxy
Manager (NPM) accesses the dashboard over the Docker network.

## Prerequisites

1. Ensure `ai_network` and `security_network` exist:

   ```bash
   docker network inspect ai_network
   docker network inspect security_network
   ```

2. From the repository root, create the service environment file if it does
   not already exist:

   ```bash
   cp -n aiServices/hermes/.env.example aiServices/hermes/.env
   ```

3. Set `HERMES_DASHBOARD_BASIC_AUTH_USERNAME` and
   `HERMES_DASHBOARD_BASIC_AUTH_PASSWORD` to your dashboard credentials, and
   set `OBSIDIAN_VAULT_PATH` to an existing absolute path. Keep credentials
   private and out of version control.

## Start / Stop

```bash
cd aiServices/hermes
docker compose up -d
docker compose down
```

After changing credentials or other Compose settings, recreate the container:

```bash
docker compose up -d --force-recreate
```

## Access Through NPM

Configure an NPM proxy host with:

- Scheme: `http`
- Forward Hostname/IP: `hermes`
- Forward Port: `9119`
- WebSocket Support: enabled
- HTTPS: enabled for client access

Both containers share `ai_network` and `security_network`. The dashboard port
does not need to be published on the host. Sign in with the configured Hermes
dashboard credentials.

## Verification and Logs

From the repository root:

```bash
docker compose -f aiServices/hermes/docker-compose.yml ps
docker logs --tail 100 hermes
docker exec npm curl -sS -o /dev/null -w 'HTTP %{http_code}\n' \
  --connect-timeout 3 http://hermes:9119/
```

The HTTP probe should reach the dashboard; a `302` authentication redirect is
expected when not signed in. Verify login through the NPM hostname as well.

## Troubleshooting

| Symptom | Action |
|---|---|
| NPM returns 502 or the probe cannot connect | Check that Hermes and NPM share a network and inspect the Hermes logs. |
| Logs report that the dashboard refuses to bind without an authentication provider | Configure both dashboard authentication variables and recreate Hermes. `HERMES_DASHBOARD=true` alone is not sufficient. |
| Dashboard loads but login fails | Check the configured credentials and recreate Hermes after changing them. |
| Obsidian bind mount is empty although the host directory contains files | If the vault is under an encrypted home, unlock the home first, then run `docker restart hermes` to reattach the mount. |

With an eCryptfs-encrypted home, a container started before login can bind the
underlying empty directory instead of the unlocked vault. The mount source path
can look correct in `docker inspect` even in this state. After unlocking the home,
restart Hermes and verify the mount:

```bash
docker restart hermes
docker exec hermes stat -f -c '%T' /opt/data/workspace/secondBrain
```

For an eCryptfs-hosted vault, the filesystem type should be `ecryptfs`. To avoid
recurrence, start Hermes after unlocking the home, or move the vault to a
storage location available before container startup and update
`OBSIDIAN_VAULT_PATH`, then recreate Hermes.

The API server is separate from the dashboard; port `8642` is not the NPM
dashboard target.
