# OpenCode Restore Guide

OpenCode does not use persistent container storage, so there is no OpenCode
session or configuration data to restore. The Obsidian vault is mounted from
the host and must be restored with the host-level backup process used for
that vault.

## Prerequisites

- Docker and Docker Compose
- The external `ai_network`
- A restored Obsidian vault directory on the host
- `aiServices/opencode/.env` configured with the vault's absolute path and a
  strong server password

## Restore Steps

### 1. Stop OpenCode

Run from the repository root:

```bash
docker compose -f aiServices/opencode/docker-compose.yml down
```

### 2. Restore the Obsidian Vault

Restore the vault using its host-level backup procedure. OpenCode's
`restore.sh` helper confirms that no container data is restored:

```bash
./aiServices/opencode/restore.sh
```

### 3. Start OpenCode

Confirm `OBSIDIAN_VAULT_PATH` in `aiServices/opencode/.env` points to the
restored vault, then start the service:

```bash
docker compose --env-file aiServices/opencode/.env \
  -f aiServices/opencode/docker-compose.yml up -d --build --force-recreate opencode
```

Rebuilding ensures packages defined in the Dockerfile, including Git, are
installed. Recreating alone reuses the existing image.

## Verification

```bash
docker compose -f aiServices/opencode/docker-compose.yml ps
docker exec opencode pwd
docker exec opencode opencode --version
docker exec opencode git --version
```

Confirm the service is running, `pwd` prints `/workspace`, and both OpenCode
and Git report their versions. Verify the restored vault is available there.

## Troubleshooting

- **The service does not start:** Check the Compose logs, ensure `ai_network`
  exists, and verify that the password is set.
- **The workspace is unavailable:** Ensure `OBSIDIAN_VAULT_PATH` is an
  absolute path to an existing, readable host directory.
- **OpenCode sessions are missing:** Session data is not persisted by this
  service. Recreating the container can discard it.
- **Git is not found:** Repeat the rebuild and recreation command in step 3,
  then run `docker exec opencode git --version`.
- **The UI is unreachable through NPM:** Ensure the proxy host targets
  `opencode:4096` on `ai_network` and that HTTPS and authentication are
  configured.
