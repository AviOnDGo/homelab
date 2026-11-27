# Syncthing — Service Documentation

## Overview

Syncthing provides peer-to-peer synchronization for the authoritative SecondBrain dataset. This service runs in `containerServices/syncthing/`, joins `container_network`, and persists both Syncthing state and SecondBrain data through named Docker volumes.

## Components

| Container | Image | Purpose |
|-----------|-------|---------|
| `syncthing` | `lscr.io/linuxserver/syncthing:latest` | Synchronization engine and management UI |

## Volumes

| Compose Alias | Volume Name | Mount Path | Purpose |
|---------------|-------------|-----------|---------|
| `syncthing_filedata` | `syncthing_filedata` | `/config` | Syncthing identity, configuration, indexes |
| `secondbrain_filedata` | `secondbrain_filedata` | `/data/SecondBrain` | Authoritative synced dataset |

Create the state volume:

```bash
docker volume inspect syncthing_filedata >/dev/null 2>&1 || docker volume create syncthing_filedata
```

Create the SecondBrain volume as a named bind-backed volume under the host user's home directory:

```bash
: "${HOME:?Set HOME to the host user's home directory}"
SECOND_BRAIN_PATH="${HOME}/Documents/SecondBrain"
mkdir -p "${SECOND_BRAIN_PATH}"
docker volume inspect secondbrain_filedata >/dev/null 2>&1 || \
  docker volume create \
    --driver local \
    --opt type=none \
    --opt o=bind \
    --opt "device=${SECOND_BRAIN_PATH}" \
    secondbrain_filedata
```

## Network

Syncthing joins `container_network` via the compose `default` network alias.

| Network | Scope |
|---------|-------|
| `container_network` | External category network for container services |

## Operations

### Start

```bash
docker compose -f containerServices/syncthing/docker-compose.yml up -d
```

### Stop

```bash
docker compose -f containerServices/syncthing/docker-compose.yml down
```

### Restart

```bash
docker compose -f containerServices/syncthing/docker-compose.yml restart syncthing
```

### Logs

```bash
docker compose -f containerServices/syncthing/docker-compose.yml logs -f syncthing
```

## Backup Coverage

Syncthing backup is implemented through `backupServices/filedata/` with two archive lanes:

- `syncthing` lane: backs up `syncthing_filedata`
- `secondbrain` lane: backs up `secondbrain_filedata`

Current policy:

- Mode: `archive`
- Schedule: daily
- Retention: 7 days
- SecondBrain destination: `/App_acc/SecondBrain`

## NPM Proxy Host

If exposing the Syncthing UI through NPM:

1. Forward host: `syncthing`
2. Forward port: `8384`
3. Scheme: `http`
4. Enable WebSockets support

Prefer NPM routing over direct host port publishing.

## Troubleshooting

- Volume mount failure for `secondbrain_filedata`: verify `${HOME}/Documents/SecondBrain` exists and the bind-backed volume uses it as the `--opt device` path.
- Peers not connecting: verify firewall and that required Syncthing ports are reachable between peers.
- Unexpected resync after restore: confirm restore sequence from `RESTORE_GUIDE.md` was followed (state first, data second, staged reconnect).

## Backup Rollback Procedure

If Syncthing backup lanes cause operational issues, rollback with the following sequence:

1. Remove the Syncthing entry from:
  - `backupServices/filedata/backup-volumes.conf`
2. Remove Syncthing lane variables from:
  - `backupServices/filedata/env.acc.example`
  - `backupServices/filedata/env.prd.example`
3. Recreate filedata-backup container:

```bash
cd backupServices/filedata
./start-backup.sh default
```

4. Keep previously generated Syncthing and SecondBrain backup artifacts until post-rollback verification completes.
