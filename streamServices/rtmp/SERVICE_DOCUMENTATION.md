# RTMP Service Documentation

## Overview

RTMP runs an Nginx RTMP ingest and restreaming container from
`streamServices/rtmp/`. The service is stateless; destination stream keys stay in
the untracked `nginx.conf`, while `nginx.conf.example` documents the required
shape without credentials.

## Configuration

1. Create the external network if it does not exist:

   ```bash
   docker network inspect stream_network >/dev/null 2>&1 ||
     docker network create stream_network
   ```

2. Copy the safe template:

   ```bash
   cd streamServices/rtmp
   cp nginx.conf.example nginx.conf
   ```

3. Uncomment the required destinations and replace their host and stream-key
   placeholders in the untracked `nginx.conf`. Do not commit that file.

The RTMP ingest port is not published on the host. Only containers attached to
the external `stream_network` can reach the relay. A trusted publishing
container can publish to:

```text
rtmp://rtmp:1935/ingest
```

OBS, another host process, or a remote client cannot connect until a host port
is explicitly published. The loopback-only mapping in `docker-compose.yml` is
commented as an opt-in. Enable it for local host publishing, but do not replace
the `127.0.0.1` binding with an all-interface mapping.

## Operations

```bash
# Start
docker compose -f streamServices/rtmp/docker-compose.yml up -d

# Stop
docker compose -f streamServices/rtmp/docker-compose.yml down

# Logs
docker compose -f streamServices/rtmp/docker-compose.yml logs -f rtmp

# Validate configuration syntax
docker compose -f streamServices/rtmp/docker-compose.yml \
  exec rtmp nginx -t
```

## Architecture

- The image is pinned to an immutable digest.
- The container joins the external `stream_network`.
- CPU and memory limits prevent a misbehaving relay from exhausting the host.
- No recordings are persisted; add an externally named volume and backup
  integration before enabling recording.
- Remote destinations receive the stream from the `stream` application.

## Recovery

Use `./restore.sh` from this directory. Recovery redeploys the stateless
container and verifies that it remains running without startup errors. A
recording backup is neither required nor performed.

See [RESTORE_GUIDE.md](RESTORE_GUIDE.md) for the complete sequence.

## Troubleshooting

- **Container exits immediately:** verify `nginx.conf` exists and run `nginx -t`.
- **Host publisher cannot connect:** this is expected because no host port is
  published. Use a publisher container on `stream_network` or intentionally add
  a loopback-only mapping.
- **Container publisher cannot connect:** verify the publisher joins
  `stream_network` and publishes to `rtmp://rtmp:1935/ingest`.
- **Destinations receive no stream:** verify the untracked keys and outbound
  access, then inspect `docker compose logs rtmp`.
- **Network error at startup:** create `stream_network` before starting RTMP.
