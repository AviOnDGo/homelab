# n8n Service Documentation

n8n provides workflow automation and integrations. In this repository, n8n uses its default SQLite database stored in the persistent `n8n_filedata` volume and is published through Nginx Proxy Manager (NPM).

## Prerequisites

1. Create service environment file:

```bash
cp aiServices/n8n/.env.example aiServices/n8n/.env
```

2. Ensure the required Docker network exists:

```bash
docker network inspect ai_network
```

3. Ensure required external volumes exist:

```bash
docker volume inspect n8n_filedata || docker volume create n8n_filedata
```

## Start / Stop

```bash
# Start
cd aiServices/n8n
docker compose up -d

# Stop
docker compose down

# Recreate after configuration changes
docker compose up -d --force-recreate
```

## Access Through NPM

Configure an NPM proxy host with the following target values:

- Scheme: `http`
- Forward Hostname/IP: `n8n`
- Forward Port: `5678`

The n8n container is attached to `ai_network`, so NPM can resolve `n8n` by Docker DNS.

## Logs

```bash
# Follow all n8n stack logs
cd aiServices/n8n
docker compose logs -f

# App-only logs
docker logs -f n8n

```

## Health Verification

```bash
# Container status
docker compose -f aiServices/n8n/docker-compose.yml ps

# Compose health status
docker inspect --format '{{.State.Health.Status}}' n8n

# Confirm n8n HTTP response from ai_network
docker run --rm --network ai_network curlimages/curl:8.10.1 -s -o /dev/null -w "%{http_code}\n" http://n8n:5678/
```

Expected outcomes:

- `n8n` shows `Up (healthy)`
- Compose health status is `healthy`
- HTTP probe returns `200`

## Data and Volumes

- n8n application data: `n8n_filedata` mounted at `/home/node/.n8n`
- SQLite database: stored within `n8n_filedata`

## Restore

Use the executable restore workflow for the latest encrypted filedata backup:

```bash
cd aiServices/n8n
PASSPHRASE=<your_gpg_passphrase> ./restore.sh
```

See [RESTORE_GUIDE.md](RESTORE_GUIDE.md) for prerequisites, manual fallback commands, and verification.

## Troubleshooting

| Symptom | Action |
|---|---|
| NPM returns 502 | Confirm both `npm` and `n8n` are on `ai_network`: `docker network inspect ai_network` |
| n8n restarts or exits | Inspect app logs: `docker logs n8n --tail 100` |
| Stack starts but login/workflows missing | Confirm `n8n_filedata` volume exists and is mounted correctly |
