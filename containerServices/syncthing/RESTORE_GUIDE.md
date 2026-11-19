# Syncthing — Restore Guide

This guide is script-first. Use `restore.sh` for normal recovery.

## Prerequisites

- Docker and Docker Compose installed
- Access to encrypted `syncthing` backup artifacts (`syncthing_*.tar.zst.gpg`)
- `rclone`, `gpg`, `zstd`, and `tar` available on the host
- GPG passphrase used by `filedata-backup`
- Peers can be temporarily isolated during restore window

## Restore Steps

### 1. Stop Syncthing and isolate peers

```bash
docker compose -f containerServices/syncthing/docker-compose.yml down
```

Before restoring, disable or disconnect peer devices to prevent immediate reconciliation while data is being replaced.

### 2. Run the restore script

```bash
cd containerServices/syncthing
./restore.sh
```

If `PASSPHRASE` is not exported, the script prompts for it securely. The script downloads
the latest `syncthing_*.tar.zst.gpg`, prompts before clearing an existing
`syncthing_filedata` volume, restores Syncthing configuration, ensures `syncthing_data`
exists, and sets `syncthing_data` ownership to `1000:1000`. If either volume is missing,
the script creates it without prompting.

### 3. Ensure required volumes exist

```bash
docker volume inspect syncthing_filedata >/dev/null 2>&1 || docker volume create syncthing_filedata
docker volume inspect syncthing_data >/dev/null 2>&1 || docker volume create syncthing_data
docker run --rm -v syncthing_data:/data alpine chown -R 1000:1000 /data
```

### 4. Download and decrypt backup artifact

Example commands (adjust filename/date):

```bash
rclone copy dropbox:/App_acc/syncthing/ /tmp/syncthing-restore --include "syncthing_*.tar.zst.gpg"

gpg --decrypt -o /tmp/syncthing-restore/syncthing.tar.zst \
  /tmp/syncthing-restore/syncthing_YYYY-MM-DD_HH-MM-SS.tar.zst.gpg
```

### 5. Restore Syncthing config volume

```bash
docker run --rm \
  -v syncthing_filedata:/restore-target \
  -v /tmp/syncthing-restore:/backup \
  alpine sh -c "cd /restore-target && rm -rf ./* && zstd -d /backup/syncthing.tar.zst -c | tar -xf -"
```

### 6. Start Syncthing and perform staged reconnect

```bash
docker compose -f containerServices/syncthing/docker-compose.yml up -d
```

Reconnect peers one-by-one after local verification completes.

## Verification

1. Confirm container health:

```bash
docker compose -f containerServices/syncthing/docker-compose.yml ps
```

2. Confirm Syncthing logs show clean startup:

```bash
docker compose -f containerServices/syncthing/docker-compose.yml logs --tail 100 syncthing
```

3. Validate `syncthing_data` ownership:

```bash
docker run --rm -v syncthing_data:/data alpine sh -c 'stat -c "%u:%g" /data'
```

4. Validate peer synchronization status in Syncthing UI before reconnecting all peers.

## Troubleshooting

- Decrypt failure: verify passphrase and artifact integrity.
- Empty restore target: verify tar structure with `zstd -d <archive> -c | tar -tf - | head`.
- Unexpected conflict files: ensure peers were isolated before restore and reconnected in stages.

## Rollback

If restore introduces unexpected behavior:

1. Stop Syncthing:

```bash
docker compose -f containerServices/syncthing/docker-compose.yml down
```

2. Reapply the prior known-good Syncthing artifact.
3. If needed, temporarily disable backup cron entries for `syncthing` in filedata backup compose while investigating.
4. Restart Syncthing and reconnect peers in stages.

## Monthly Restore Drill

Run this restore procedure at least once per month in a controlled window and record:

- Artifact timestamps restored
- Verification outcomes
- Any corrective actions required
