# OpenCode Service Documentation

OpenCode runs in a dedicated container built from the pinned OpenCode
`1.19.4` npm package. It is attached to `ai_network` and bind-mounts only
the configured Obsidian vault at `/workspace`. No other host directory or
Docker volume is mounted. OpenCode session and configuration data are not
persisted and can be lost when the container is recreated.

The image includes Git for version control inside the mounted vault.

## Prerequisites

- Docker Compose
- The external `ai_network`
- An existing Obsidian vault directory on the host
- A private `aiServices/opencode/.env` file with a strong server password and
  the absolute path to the vault

Create the local environment file from the tracked example and set its values:

```bash
cp aiServices/opencode/.env.example aiServices/opencode/.env
${EDITOR:-vi} aiServices/opencode/.env
```

`OBSIDIAN_VAULT_PATH` must identify an existing host directory. Compose will
fail rather than create the directory if the path is invalid.

## Start and Stop

Start or recreate the service:

```bash
docker compose --env-file aiServices/opencode/.env \
  -f aiServices/opencode/docker-compose.yml up -d --build --force-recreate opencode
docker exec opencode git --version
```

Recreating or restarting alone reuses the existing image; it does not install
packages added to the Dockerfile. Rebuild after Dockerfile changes.

Stop the service:

```bash
docker compose -f aiServices/opencode/docker-compose.yml down
```

## Access

The service listens on port `4096` inside `ai_network`. No host port is
published by default. Configure an Nginx Proxy Manager host pointing to
`opencode:4096` on `ai_network`; keep authentication enabled and use HTTPS.
The web server uses HTTP Basic authentication. Set a strong password in the
untracked `.env` file.

OpenCode can connect to cloud model providers using the container's outbound
network access. The Compose service intentionally does not set `cap_drop` or
`security_opt`; in this deployment, those overrides prevented cloud model
access. Preserve the existing boundaries by keeping the vault mount scoped to
the authorized workspace, not mounting the Docker socket, and requiring
authentication over HTTPS through the proxy.

## Workspace and Data Persistence

The configured Obsidian vault is mounted read-write at `/workspace`, which is
the container's working directory. OpenCode can read and edit files in that
vault. The Docker socket and all other host paths are not mounted.

Only the Obsidian vault is persisted by this service. OpenCode session,
configuration, and cache data remain in the container's writable layer and
are not backed up by the filedata backup service. Recreating the container
can discard that data. Back up the Obsidian vault using its existing
host-level backup process.

## Logs and Status

```bash
docker compose -f aiServices/opencode/docker-compose.yml ps
docker compose -f aiServices/opencode/docker-compose.yml logs -f
```

Check the installed tools:

```bash
docker exec opencode opencode --version
docker exec opencode git --version
```

Check the HTTP endpoint from the host through your configured proxy:

```bash
curl --user opencode https://your-opencode-host/global/health
```

## Troubleshooting

If Git is not found after recreating the container, run the rebuild and
recreation command in **Start and Stop**, then verify with
`docker exec opencode git --version`.
