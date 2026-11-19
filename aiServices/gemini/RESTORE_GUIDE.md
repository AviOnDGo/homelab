# Gemini CLI Restore Guide

Gemini CLI has no persistent container data. Its background container can be
recreated at any time; the Obsidian vault remains at its host path, and the API
key is stored in the local `.env` file. Neither is
managed by a Docker data volume or restored by this guide.

## Prerequisites

- Docker Compose
- The host Obsidian vault directory
- `aiServices/gemini/.env` with a valid Gemini API key and the absolute
  `OBSIDIAN_VAULT_PATH` used by OpenCode

## Restore Steps

### 1. Run the restore helper

```bash
cd aiServices/gemini
./restore.sh
```

The helper confirms that no service data restore is required.

### 2. Rebuild the CLI image if needed

```bash
docker compose build gemini
```

### 3. Start the background container

```bash
docker compose up -d gemini
```

## Verification

```bash
docker exec -it gemini pwd
docker exec -it gemini gemini --version
docker exec gemini git --version
```

Confirm `pwd` prints `/workspace`, Git reports its version, and Gemini CLI starts in the vault.
The homelab repository is not mounted; vault data is modified directly at the host path
and remains outside the scope of this container restore procedure.

## Troubleshooting

| Symptom | Action |
|---|---|
| API authentication fails | Verify the key in the local `.env` file and confirm Google AI API access. |
| `docker exec` reports that the container is not running | Start it with `docker compose up -d gemini` from `aiServices/gemini/`. |
| Workspace files are not writable | Set `GEMINI_UID` and `GEMINI_GID` to the host workspace owner's IDs in `.env`. |
| Obsidian vault is missing | Set `OBSIDIAN_VAULT_PATH` to the existing absolute host path used by OpenCode. |
| Compose reports the network is missing | Create or start the external `ai_network`. |
