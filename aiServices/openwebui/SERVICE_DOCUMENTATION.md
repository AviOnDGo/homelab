# Open WebUI Service Documentation

Open WebUI provides a web-based chat interface for interacting with local LLM models served by Ollama. The UI is accessible via Nginx Proxy Manager (NPM) and communicates with Ollama over the shared `ai_network`.

---

## Prerequisites

1. **Ollama must be running** before Open WebUI can serve inference requests:

   ```bash
   docker ps --filter name=ollama --format "{{.Names}}: {{.Status}}"
   # Should show: ollama: Up X minutes (healthy)
   ```

2. Create `.env` from `.env.example`:

   ```bash
   cp aiServices/openwebui/.env.example aiServices/openwebui/.env
   ```

3. Ensure the external volume exists (created once on first setup):

   ```bash
   docker volume inspect openwebui_filedata || docker volume create openwebui_filedata
   ```

---

## Start / Stop

```bash
# Start
docker compose -f aiServices/openwebui/docker-compose.yml up -d

# Stop (volumes are preserved)
docker compose -f aiServices/openwebui/docker-compose.yml down

# Force recreate (e.g. after config change or image upgrade)
docker compose -f aiServices/openwebui/docker-compose.yml up -d --force-recreate
```

---

## Logs

```bash
# Follow live logs
docker compose -f aiServices/openwebui/docker-compose.yml logs -f

# Last 100 lines
docker compose -f aiServices/openwebui/docker-compose.yml logs --tail=100
```

---

## Health Check

```bash
# One-liner status
docker ps --filter name=openwebui --format "{{.Names}}: {{.Status}}"

# Manual probe (from host)
curl -sf http://localhost:8080/ -o /dev/null && echo "OK"
```

Container will show `(healthy)` ~30 s after start. If Ollama is not yet ready, the UI will still load but model requests will fail until Ollama is healthy.

---

## Accessing the UI

Open WebUI is exposed through Nginx Proxy Manager. Configure an NPM proxy host pointing to `openwebui:8080` on `ai_network`.

Use the HTTPS hostname configured in Nginx Proxy Manager. The Compose service
enables authentication with `WEBUI_AUTH=true` and sets both session and
authentication cookies to secure-only. Browser login therefore requires HTTPS;
NPM can continue forwarding to the backend over internal HTTP.

Set `CORS_ALLOW_ORIGIN` in the ignored `.env` to the exact public HTTPS origin
configured in NPM, without a trailing slash. The tracked `.env.example` uses a
reserved example hostname. This restricts cross-origin browser requests, not
server-to-server cloud or agent connections.

---

## Telemetry

The Compose service explicitly sets `DO_NOT_TRACK=true`, `SCARF_NO_ANALYTICS=true`,
and `ANONYMIZED_TELEMETRY=false` to disable the known tracking and anonymized
telemetry paths. These values override the image defaults and any conflicting
entries in `.env`. They do not block unrelated outbound connections; external
egress remains routed through Gluetun as described below.

The upstream Open WebUI image currently sets these same defaults in its
[Dockerfile](https://github.com/open-webui/open-webui/blob/main/Dockerfile).

---

## External Egress via Gluetun (VPN Proxy)

Open WebUI routes external HTTP(S) calls (e.g. OpenAI-compatible API requests) through the `gluetun` VPN container's HTTP proxy at `gluetun:8888`. This keeps NPM's `openwebui:8080` target and the `ollama:11434` inference path untouched — only outbound external traffic is affected.

- `openwebui` joins only `ai_network` and `security_network`: the former supports
  NPM, Ollama, and agent integrations; the latter reaches `gluetun` by container name.
  It does not join `knowledge_network`, limiting direct access to that network's
  supporting services. Uploaded Knowledge bases remain available within Open WebUI;
  any external integration needs an endpoint reachable over its retained networks.
- Lowercase `http_proxy` and `https_proxy` are set to `http://gluetun:8888`.
- Matching `no_proxy` and `NO_PROXY` values come from `WEBUI_NO_PROXY` in the
  ignored `.env`. The default exempts `localhost`, `127.0.0.1`, `ollama`,
  `openwebui`, `opencode`, and `hermes`. Before recreating an existing deployment,
  add any host-specific Ollama or agent addresses to this list, preserving the
  default entries. Otherwise those requests can be sent to Gluetun instead of
  directly to the host. Hermes must be deployed on `ai_network` before its
  hostname resolves.
- Proxy environment variables apply only to clients that honor them; they do not
  enforce an outbound firewall or VPN kill switch.
- `gluetun` must be deployed and healthy (with valid ProtonVPN WireGuard credentials in `securityServices/gluetun/.env`) for external egress to succeed. If `gluetun` is down, external API calls from Open WebUI will fail even though the UI and local inference continue to work.

Verify the proxy is applied:

```bash
docker exec openwebui env | grep -i proxy
```

To confirm traffic actually traverses the VPN, trigger an external connection test from the Open WebUI admin UI and check for a corresponding entry in `docker compose -f securityServices/gluetun/docker-compose.yml logs -f`.

---

## Backup and Restore Dependency

Open WebUI data (`openwebui_filedata`) is intentionally included in `backupServices/filedata/`
because it contains user accounts, chat history, and UI settings.

Tier C backup classification for `openwebui_filedata`:

- Essential (backed up): `webui.db`, `webui.db-wal`, `webui.db-shm`, `uploads/`
- Rebuildable (excluded): `cache/`, `vector_db/`

This service targets core restore usability within 10 minutes. Core usability means healthy service plus recoverable account/chat/settings state. RAG/vector index readiness is intentionally out-of-SLO and may rebuild after restore.

This service depends on filedata backups for disaster recovery. Use
`aiServices/openwebui/RESTORE_GUIDE.md` for restore procedures.

---

## Changing the Ollama Backend

If Ollama is running on a non-default URL, update `OLLAMA_BASE_URL` in `.env`:

```bash
# .env
OLLAMA_BASE_URL=http://my-custom-ollama:11434
```

Then recreate the container:

```bash
docker compose -f aiServices/openwebui/docker-compose.yml up -d --force-recreate
```

---

## Upgrading

Watchtower manages image updates automatically. To upgrade manually:

1. Pull the latest image from the `:main` channel:

   ```bash
   docker compose -f aiServices/openwebui/docker-compose.yml pull
   ```
2. Recreate the container:

   ```bash
   docker compose -f aiServices/openwebui/docker-compose.yml up -d --force-recreate
   ```
3. User data (conversations, settings) in the external volume is **not affected**.

### Rollback

If the `:main` image causes regressions:

1. Temporarily pin a known-good tag in `aiServices/openwebui/docker-compose.yml` (example: `ghcr.io/open-webui/open-webui:v0.6.30`).
2. Pull and recreate the container:

   ```bash
   docker compose -f aiServices/openwebui/docker-compose.yml pull
   docker compose -f aiServices/openwebui/docker-compose.yml up -d --force-recreate
   ```
3. Verify health:

   ```bash
   docker ps --filter name=openwebui --format "{{.Names}}: {{.Status}}"
   ```
4. Once upstream fixes are available on `:main`, restore `image: ghcr.io/open-webui/open-webui:main` and recreate again.

---

## Troubleshooting

| Symptom | Action |
|---|---|
| Container exits immediately | Check logs: `docker logs openwebui`; verify `ai_network` exists and Ollama is up |
| UI loads but models unavailable | Verify `OLLAMA_BASE_URL` in `.env`; check `docker exec openwebui curl -sf $OLLAMA_BASE_URL/api/tags` |
| NPM returns 502 | Confirm `openwebui` container is healthy: `docker ps --filter name=openwebui` |
| Health check failing | Check if port 8080 is responding inside container: `docker exec openwebui curl -sf http://localhost:8080/` |
