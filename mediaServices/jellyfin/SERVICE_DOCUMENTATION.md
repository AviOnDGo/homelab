# Jellyfin Service Documentation

## Overview

Jellyfin provides media playback for Movies, TVSeries, and Music. It runs as an independent Compose stack on `media_network` and `security_network`, listens on container port `8096`, and routes external HTTP(S) egress through the Gluetun proxy at `gluetun:8888`. External user access is routed through Nginx Proxy Manager.

## Persistent Data

| Data | Mount | Backup |
|------|-------|--------|
| Jellyfin configuration and application state | `jellyfin_filedata:/config` | Encrypted filedata archive |
| Movies | `${HOME}/.media/Movies:/data/movies` | Not included |
| TV series | `${HOME}/.media/TVSeries:/data/tvshows` | Not included |
| Music | `${HOME}/.media/Music:/data/music` | Not included |

The old XML configuration is not migrated. Jellyfin starts with fresh configuration; add libraries at `/data/movies`, `/data/tvshows`, and `/data/music`.

## First Deployment

Create the external config volume before starting the stack:

```bash
cd mediaServices/jellyfin
docker volume create jellyfin_filedata
docker compose up -d
```

The external `media_network` and `security_network` networks must already exist. Gluetun must be attached to `security_network` with its internal HTTP proxy enabled.

## Operations

Start or update:

```bash
docker compose up -d
```

Stop:

```bash
docker compose down
```

Status and logs:

```bash
docker compose ps
docker compose logs -f jellyfin
```

Access Jellyfin at `http://<host>:8096` or configure Nginx Proxy Manager to forward the Jellyfin hostname to `jellyfin:8096` on `media_network`. Jellyfin's outbound HTTP(S) requests use `http://gluetun:8888`; localhost requests bypass the proxy.

## Backup

The default filedata backup profile archives only `jellyfin_filedata` using zstd compression and GPG AES256 encryption, then uploads it to the configured Dropbox path. The production environment example sets `/App_acc/jellyfin` and seven-day retention. Media libraries are not part of this backup.

## Restore

Use [RESTORE_GUIDE.md](RESTORE_GUIDE.md) and run `./restore.sh` from this directory. Restore replaces only `jellyfin_filedata`; media directories remain untouched.