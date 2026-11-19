# Radarr Service Documentation

## Overview

Radarr manages the movie library in an independent Compose stack on `media_network` and `security_network`. It publishes its web interface on host port `7878` and routes external HTTP(S) requests through the Gluetun proxy at `gluetun:8888`.

## Persistent Data

| Data | Mount | Backup |
|------|-------|--------|
| Radarr configuration and application state | `radarr_filedata:/config` | Encrypted filedata archive |
| Downloads | `${HOME}/.media/.downloads:/downloads` | Not included |
| Movies | `${HOME}/.media/Movies:/movies` | Not included |

The config volume is separate from media and downloads. Legacy config-directory files are not mounted by the new stack.

## First Deployment

Create the external config volume before starting the stack. The external `media_network` and `security_network` networks, the shared media directories, and Gluetun's internal HTTP proxy must already be available.

```bash
cd mediaServices/radarr
docker volume create radarr_filedata
docker compose up -d
```

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
docker compose logs -f radarr
```

Open Radarr at `http://<host>:7878` or configure Nginx Proxy Manager to forward its hostname to `radarr:7878` on `media_network`. Outbound HTTP(S) requests use `http://gluetun:8888`; requests to `localhost` and `127.0.0.1` bypass the proxy. Set the movie root folder to `/movies` and the download path to `/downloads`.

## Backup Coverage

The default and Local filedata profiles archive only `radarr_filedata` with zstd compression and GPG AES256 encryption, then upload it to the configured Dropbox path (`/Apps/radarr` in production and `/App_acc/radarr` in acceptance). Both environment examples schedule Radarr at 04:20 with two-day retention. Media and downloads are not included.

## Restore

Use [RESTORE_GUIDE.md](RESTORE_GUIDE.md) and run `./restore.sh` from this directory. Restore replaces only `radarr_filedata`; media and download paths remain untouched.