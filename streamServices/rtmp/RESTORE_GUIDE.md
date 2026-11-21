# RTMP Restore Guide

RTMP is stateless. Recovery redeploys the container from its ignored local
`nginx.conf`; no recording or volume restore is required.

## Prerequisites

- Docker is installed and reachable.
- `stream_network` exists as an external Docker network.
- `nginx.conf` was created from `nginx.conf.example` and contains the current
  destination keys.

## Restore Steps

### 1. Navigate to the service directory

```bash
cd streamServices/rtmp
```

### 2. Run the script-first recovery

```bash
./restore.sh
```

The script validates Docker and the local configuration, prompts before
restarting, recreates the container, and checks startup logs.

### 3. Start manually if the script cannot be used

```bash
docker compose down
docker compose up -d
```

## Verification

```bash
docker compose ps
docker compose logs --tail=80 rtmp
docker compose exec rtmp nginx -t
```

Confirm a publishing container on `stream_network` can reach the ingest endpoint
and that the configured destinations receive the stream.

## Troubleshooting

- If configuration validation fails, compare `nginx.conf` with
  `nginx.conf.example` and correct local secrets or destination URLs.
- If the network is missing, run `docker network create stream_network`.
- If the container is not running, inspect the full logs with
  `docker compose logs rtmp`.
