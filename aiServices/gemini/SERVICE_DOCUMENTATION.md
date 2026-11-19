# Gemini CLI Service Documentation

Gemini CLI runs in a persistent utility container named `gemini`. The container
mounts only the Obsidian vault at `/workspace`, its default working directory.
It remains running in the background so `docker exec` can open a shell or start
Gemini CLI directly in the vault.

The image includes Git for version control inside the mounted vault.
After updating the Dockerfile, rebuild and recreate the container to install it:

```bash
docker compose up -d --build --force-recreate gemini
docker exec gemini git --version
```

Recreating or restarting alone reuses the existing image; it does not install
packages added to the Dockerfile.

## Prerequisites

- Docker Compose
- The external `ai_network` Docker network
- A Gemini API key

Create the local environment file:

```bash
cd aiServices/gemini
cp .env.example .env
```

Set `GEMINI_API_KEY` in `.env` and set `GEMINI_UID` and `GEMINI_GID` to the
host user and group IDs that own the workspace:

```bash
id -u
id -g
```

Set `OBSIDIAN_VAULT_PATH` to the absolute host path of the same vault mounted
for OpenCode. Gemini can access it at `/workspace` inside the container. The
mount is read/write, so vault edits are reflected on the host. Compose fails
if the variable is unset or the host path does not exist.

Do not commit or share `.env`; it contains a live API key.

## Start, access, and stop

Start the background container from this directory:

```bash
docker compose up -d gemini
```

Open a shell directly in the Obsidian vault:

```bash
docker exec -it gemini bash
```

Docker requires a command after the container name; `docker exec -it gemini`
alone is incomplete. If Bash is unavailable, use:

```bash
docker exec -it gemini sh
```

Run Gemini CLI from the vault directory:

```bash
docker exec -it gemini gemini
```

The working directory for `docker exec` is `/workspace`, which is the Obsidian
vault, not the homelab repository. Gemini CLI uses its normal interactive confirmation
behavior; do not enable unattended approval modes when using writable mounts
unless that is intentional.

Stop the background container when it is not needed:

```bash
docker compose down
```

No persistent service data volume is used; the vault remains at its host path.
CLI settings and session data in the container are lost when it is recreated.

After changing an existing deployment from separate repository and vault mounts,
recreate the container to apply the new workspace:

```bash
docker compose up -d --force-recreate gemini
docker exec -it gemini pwd
```

The directory printed should be `/workspace`, containing your vault files.

## Logs and troubleshooting

CLI output appears in the terminal running `docker exec`. Check the installed
version with:

```bash
docker exec -it gemini gemini --version
docker exec gemini git --version
```

| Symptom | Action |
|---|---|
| `docker exec` reports that the container is not running | Start it with `docker compose up -d gemini` from this directory. |
| `git` is not found after recreating the container | Rebuild the image with `docker compose up -d --build --force-recreate gemini`, then run `docker exec gemini git --version`. |
| Compose reports `GEMINI_API_KEY` is unset | Set a valid key in `aiServices/gemini/.env`. |
| Gemini cannot write workspace files | Set `GEMINI_UID` and `GEMINI_GID` to the host IDs that own the files. |
| Compose reports `ai_network` is missing | Create the shared network or start the service that owns it. |
| API requests fail | Check API key validity, Google AI API access, and host/container internet connectivity. |

## Updating Gemini CLI

The CLI package version and local image tag are pinned in the Dockerfile and
Compose file. Update both version references together, then rebuild:

```bash
docker compose build --no-cache gemini
docker compose up -d --force-recreate gemini
docker exec -it gemini gemini --version
docker exec gemini git --version
```

## Security notes

- The container runs as the configured non-root UID/GID, drops all Linux
  capabilities, and enables `no-new-privileges`.
- Only the configured Obsidian vault is mounted read/write at `/workspace`.
  The homelab repository, Docker socket, and host home directory are not mounted.
- The API key is supplied through the local `.env` file and is not stored in
  the image or workspace.
- The mounted vault includes hidden files and Obsidian configuration. Gemini
  CLI and its tools can access mounted files and the
  API key in their process environment; use a workspace without secrets that
  should not be exposed to the coding agent.
- Gemini CLI can execute tools and modify mounted files. Review its proposed
  actions and diffs before accepting changes.
