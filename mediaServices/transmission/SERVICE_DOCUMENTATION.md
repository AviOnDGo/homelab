# Transmission Service Documentation

## Overview

Transmission downloads torrents into the shared media downloads directory. It
runs as an independent Compose stack on `media_network` and `security_network`.
Its web interface is not published on a host port; route Nginx Proxy Manager to
`transmission:9091` on `media_network`.

The `http_proxy` and `https_proxy` variables affect only applications that
honor HTTP(S) proxy settings. They do not tunnel BitTorrent peer traffic
through Gluetun. The current Compose configuration does not provide VPN
isolation for peer traffic.

## Persistent Data

| Data | Mount | Backup |
|------|-------|--------|
| Transmission configuration and queue | `transmission_filedata:/config` | Encrypted filedata archive |
| Downloads | `${HOME}/.media/.downloads:/downloads` | Not included |
| Watch directory | `${HOME}/.media/.watch:/watch` | Not included |

The previous tracked bind-mounted Transmission configuration was removed and
is not imported. A new volume starts with fresh configuration. Existing
downloads are not changed or restored by this service's backup.

## First Deployment

Create a local credentials file from the safe example and replace its sample
password with a unique value. The `.env` file is ignored by Git.

```bash
cd mediaServices/transmission
cp .env.example .env
docker volume create transmission_filedata
docker compose up -d
```

The external networks and Gluetun HTTP proxy must already be available.

## Operations

```bash
docker compose ps
docker compose logs -f transmission
docker compose down
```

Set the downloads path to `/downloads` and the watch path to `/watch`. The
default and Local filedata profiles archive only `transmission_filedata`
daily at 04:35, with seven-day retention. Production archives use
`/Apps/transmission`; acceptance archives use `/App_acc/transmission`.

Use [RESTORE_GUIDE.md](RESTORE_GUIDE.md) and run `./restore.sh` from this
directory to restore the latest archive.