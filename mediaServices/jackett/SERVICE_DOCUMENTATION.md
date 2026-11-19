# Jackett Service Documentation

## Overview

Jackett provides torrent indexer search to Sonarr and Radarr. It runs as an
independent Compose stack on `media_network` and `security_network`; its web
interface is not published on a host port. Use Nginx Proxy Manager to route to
`jackett:9117` on `media_network`.

## Persistent Data

| Data | Mount | Backup |
|------|-------|--------|
| Jackett configuration | `jackett_filedata:/config` | Encrypted filedata archive |
| Downloads | `${HOME}/.media/.downloads:/downloads` | Not included |

The previous tracked bind-mounted Jackett configuration was removed and is not
imported. A new volume starts with fresh configuration. Configure indexers and
reconnect Sonarr and Radarr after deployment, or restore an existing encrypted
archive.

## First Deployment

The external networks and Gluetun HTTP proxy must already be available.

```bash
cd mediaServices/jackett
docker volume create jackett_filedata
docker compose up -d
```

## Operations

```bash
docker compose ps
docker compose logs -f jackett
docker compose down
```

Configure Sonarr and Radarr to use `http://jackett:9117`. Jackett's proxy
environment variables route proxy-aware HTTP(S) requests through
`http://gluetun:8888`; local requests bypass the proxy.

## Backup and Restore

The default and Local filedata profiles archive only `jackett_filedata` daily
at 04:30, with seven-day retention. Production archives use
`/Apps/jackett`; acceptance archives use `/App_acc/jackett`. Downloads are not
included.

Use [RESTORE_GUIDE.md](RESTORE_GUIDE.md) and run `./restore.sh` from this
directory to restore the latest archive.