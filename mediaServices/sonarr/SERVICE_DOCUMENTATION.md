# Sonarr Service Documentation

## Overview

Sonarr manages the TV series library in an independent Compose stack on `media_network` and `security_network`. It publishes its web interface on host port `8989` and routes external HTTP(S) requests through the Gluetun proxy at `gluetun:8888`.

## Persistent Data

| Data | Mount | Backup |
|------|-------|--------|
| Sonarr configuration and application state | `sonarr_filedata:/config` | Encrypted filedata archive |
| Downloads | `${HOME}/.media/.downloads:/downloads` | Not included |
| TV series | `${HOME}/.media/TVSeries:/tv` | Not included |

The config volume is separate from media and downloads. Legacy config-directory files are not mounted by the new stack.

## First Deployment

Create the external config volume before starting the stack. The external `media_network` and `security_network` networks, the shared media directories, and Gluetun's internal HTTP proxy must already be available.

```bash
cd mediaServices/sonarr
docker volume create sonarr_filedata
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
docker compose logs -f sonarr
```

Open Sonarr at `http://<host>:8989` or configure Nginx Proxy Manager to forward its hostname to `sonarr:8989` on `media_network`. Outbound HTTP(S) requests use `http://gluetun:8888`; requests to `localhost` and `127.0.0.1` bypass the proxy. Set the TV root folder to `/tv` and the download path to `/downloads`.

## Backup Coverage

The default and Local filedata profiles archive only `sonarr_filedata` with zstd compression and GPG AES256 encryption, then upload it to the configured Dropbox path (`/Apps/sonarr` in production and `/App_acc/sonarr` in acceptance). Both environment examples schedule Sonarr at 04:25 with two-day retention. Media and downloads are not included.

## Restore

Use [RESTORE_GUIDE.md](RESTORE_GUIDE.md) and run `./restore.sh` from this directory. Restore replaces only `sonarr_filedata`; media and download paths remain untouched.