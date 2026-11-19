# OmniRoute Quickstart

## 1. Prepare the service

From the repository root, copy the example environment file and create the
external data volume:

```bash
if [ ! -e aiServices/omniroute/.env ]; then
  cp aiServices/omniroute/.env.example aiServices/omniroute/.env
fi
docker volume inspect omniroute_filedata \
  || docker volume create omniroute_filedata
docker network inspect ai_network
docker network inspect security_network
```

Keep `.env` private. OmniRoute generates and persists `JWT_SECRET` and
`API_KEY_SECRET` in `omniroute_filedata` if you leave them unset.
If serving through HTTPS in NPM, set `NEXT_PUBLIC_BASE_URL` to that public
origin and `AUTH_COOKIE_SECURE=true` in `.env` before first startup.
The example `.env` routes external provider traffic through Gluetun and keeps
Ollama and local health checks off the proxy. Add those proxy settings to an
existing private `.env` before starting or recreating the service.

## 2. Start OmniRoute

```bash
docker compose -f aiServices/omniroute/docker-compose.yml up -d
docker ps --filter name=omniroute --format "{{.Names}}: {{.Status}}"
```

The service does not publish a host port. Configure NPM to forward to
`omniroute:20128` on `ai_network`, then complete the dashboard's initial
password setup over HTTPS. External provider requests use Gluetun's HTTP proxy;
the dashboard and internal Ollama connection remain directly reachable.

## 3. Connect a model

In the dashboard:

1. Add Ollama with base URL `http://ollama:11434`, or add a supported provider
   using its API credentials.
2. Test the provider and create an OmniRoute API key.
3. Use the API endpoint `http://omniroute:20128/v1` with that key.
4. For automatic selection, try `auto` or `auto/coding`. Initially connect only
   providers you want included in automatic selection.

For Gemini API models, use a Gemini API key; a Gemini website session or
consumer subscription does not directly grant Gemini API access or quota.

## Stop and inspect

```bash
docker compose -f aiServices/omniroute/docker-compose.yml logs -f
docker compose -f aiServices/omniroute/docker-compose.yml down
```

The `omniroute_filedata` volume remains in place when the container is stopped.
See [SERVICE_DOCUMENTATION.md](SERVICE_DOCUMENTATION.md) for security and
troubleshooting details.
