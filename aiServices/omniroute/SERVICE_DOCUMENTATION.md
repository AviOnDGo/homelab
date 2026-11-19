# OmniRoute Service Documentation

OmniRoute is an OpenAI-compatible gateway for connecting local and hosted model
providers behind one endpoint. It runs on `ai_network`, shares Ollama's internal
network, and stores its database and provider credentials in `omniroute_filedata`.

## Prerequisites

1. Ensure Docker and the external AI network are available:

   ```bash
   docker network inspect ai_network
   docker network inspect security_network
   ```

2. Create the service environment file:

   ```bash
   if [ ! -e aiServices/omniroute/.env ]; then
     cp aiServices/omniroute/.env.example aiServices/omniroute/.env
   fi
   ```

3. Create the persistent volume:

   ```bash
   docker volume inspect omniroute_filedata || docker volume create omniroute_filedata
   ```

4. Optionally set `JWT_SECRET` and `API_KEY_SECRET` in `.env` before first
   startup. Otherwise, OmniRoute generates and persists them in the data volume.
   Generate values with:

   ```bash
   openssl rand -base64 48
   openssl rand -hex 32
   ```

   Keep `.env` private and do not commit it.

## Start / Stop

```bash
# Start
docker compose -f aiServices/omniroute/docker-compose.yml up -d

# Stop (persistent data is preserved)
docker compose -f aiServices/omniroute/docker-compose.yml down

# Recreate after configuration changes
docker compose -f aiServices/omniroute/docker-compose.yml up -d --force-recreate
```

## Access Through NPM

The Compose file does not publish a host port. Configure an NPM proxy host with:

- Scheme: `http`
- Forward Hostname/IP: `omniroute`
- Forward Port: `20128`

NPM must be attached to `ai_network`. Prefer HTTPS and an NPM access list for
dashboard access. If using HTTPS, set `NEXT_PUBLIC_BASE_URL` to the public
origin and `AUTH_COOKIE_SECURE=true` in `.env`.

The dashboard and OpenAI-compatible API share port `20128`. The API requires
an OmniRoute API key (`REQUIRE_API_KEY=true`); create one in the dashboard and
use it for clients. Do not expose the container directly to an untrusted
network.

## Logs and Health

```bash
# Container status and health
docker ps --filter name=omniroute --format "{{.Names}}: {{.Status}}"
docker inspect --format '{{.State.Health.Status}}' omniroute

# Follow logs
docker compose -f aiServices/omniroute/docker-compose.yml logs -f

# Probe the dashboard from the AI network
docker run --rm --network ai_network curlimages/curl:8.10.1 \
  -fsS http://omniroute:20128/ -o /dev/null
```

The container healthcheck runs OmniRoute's `healthcheck.mjs` script. The probe
above verifies network reachability; use the container health status and logs
to diagnose application readiness.

## Experimenting With Models

1. Open the OmniRoute dashboard through NPM.
2. Add Ollama as a provider using the internal URL `http://ollama:11434`.
   Both services are on `ai_network`; no host port is needed.
3. Add other providers with their supported API credentials, then test each
   provider explicitly before trying automatic routing.
4. To experiment with OmniRoute's automatic provider selection, use model
   aliases such as `auto` or `auto/coding` from a compatible client. Automatic
   selection considers the connected providers and their configured models.
   Start with only providers you are comfortable allowing it to select.

To try OmniRoute from Open WebUI without replacing its existing Ollama
connection, add a separate OpenAI-compatible connection with base URL
`http://omniroute:20128/v1` and an OmniRoute API key.

OmniRoute uses Gluetun's HTTP proxy for upstream provider calls. The service
joins `security_network` to reach `gluetun:8888`;
`HTTP_PROXY` and `HTTPS_PROXY` are set in `.env.example`, while `NO_PROXY`
keeps local traffic such as `ollama` and the healthcheck off the proxy.
`PROXY_FAIL_OPEN=false` prevents direct-egress fallback if the proxy is
unavailable. Add these settings to an existing private `.env`, then recreate
the container. The dashboard remains reachable through NPM on `ai_network`.

Gluetun must be deployed and healthy for external provider calls to succeed.
Verify that the proxy variables reached the container and make a provider
request while checking Gluetun logs:

```bash
docker exec omniroute env | grep -iE '^(http_proxy|https_proxy|no_proxy|proxy_fail_open)='
docker compose -f securityServices/gluetun/docker-compose.yml logs -f
```

For Gemini, use a Gemini API key and a model available through the Gemini API.
The Gemini website session or a Google AI subscription does not automatically
provide API access or API quota. Do not use Gemini CLI OAuth credentials with
OmniRoute: Google's Gemini CLI terms warn against accessing the service through
third-party tools.

Provider credentials are stored in the persistent data volume. Backups for this
volume are included in the encrypted filedata backup workflow.

## Backup and Restore

`omniroute_filedata` is included in encrypted filedata backups. Use the
script-first restore workflow:

```bash
cd aiServices/omniroute
./restore.sh
```

See [RESTORE_GUIDE.md](RESTORE_GUIDE.md) for prerequisites and recovery details.

## Troubleshooting

| Symptom | Action |
|---|---|
| NPM returns 502 | Confirm OmniRoute and NPM are attached to `ai_network`; inspect `docker logs omniroute` |
| API returns an authentication error | Create an API key in the dashboard and send it as a Bearer token |
| Ollama provider is unreachable | Confirm Ollama is running and use `http://ollama:11434` rather than a host address |
| Provider credentials or settings disappear | Confirm `omniroute_filedata` is mounted and was not removed |
| Dashboard login fails behind HTTPS | Set `NEXT_PUBLIC_BASE_URL` and `AUTH_COOKIE_SECURE=true` in `.env`, then recreate the service |
