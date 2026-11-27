# Ollama Service Documentation

Ollama provides local large language model (LLM) inference. It exposes a REST API on port 11434, accessible to other services on `ai_network` via the DNS name `ollama`.

---

## Prerequisites

1. Create `.env` from `.env.example`:

   ```bash
   cp aiServices/ollama/.env.example aiServices/ollama/.env
   ```

2. Ensure `ai_network` exists (created and owned by NPM):

   ```bash
   docker network inspect ai_network
   ```

3. Ensure the external volume exists (created once on first setup):

   ```bash
   docker volume create ollama_data
   ```

---

## Start / Stop

```bash
# Start
docker compose -f aiServices/ollama/docker-compose.yml up -d

# Stop (volumes are preserved)
docker compose -f aiServices/ollama/docker-compose.yml down

# Force recreate (e.g. after config change)
docker compose -f aiServices/ollama/docker-compose.yml up -d --force-recreate
```

---

## Logs

```bash
# Follow live logs
docker compose -f aiServices/ollama/docker-compose.yml logs -f

# Last 100 lines
docker compose -f aiServices/ollama/docker-compose.yml logs --tail=100
```

---

## Health Check

The container reports its own health status via `docker ps`. The check calls `GET /api/tags`.

```bash
# One-liner status
docker ps --filter name=ollama --format "{{.Names}}: {{.Status}}"

# Manual probe
docker exec ollama curl -sf http://localhost:11434/api/tags | python3 -m json.tool
```

Container will show `(healthy)` once the API is ready (~20 s after start).

---

## Model Management

Models are stored in the `ollama_data` named Docker volume (see [Persistent Model Storage](#persistent-model-storage-ollama_data-volume) below).

```bash
# List downloaded models
docker exec ollama ollama list

# Pull a model
docker exec ollama ollama pull llama3.2:3b

# Update a model to the latest version
docker exec ollama ollama pull llama3.2:3b

# Remove a model to free disk space
docker exec ollama ollama rm llama3.2:3b

# Run a model interactively in the terminal
docker exec -it ollama ollama run llama3.2:3b

# Show model details (size, parameters, quantisation)
docker exec ollama ollama show llama3.2:3b

# Show currently loaded models and which device (GPU/CPU) they use
docker exec ollama ollama ps
```

Models are not pulled automatically at container startup. Pull any required model with
`ollama pull <model>` after the service starts; downloaded models persist in the
`ollama_data` volume.

---

## Persistent Model Storage (`ollama_data` Volume)

All downloaded models are stored in the `ollama_data` named Docker volume mounted at `/root/.ollama` inside the container.

| Property | Value |
|---|---|
| Volume name | `ollama_data` |
| Mount point | `/root/.ollama` inside container |
| Host path | `/var/lib/docker/volumes/ollama_data/_data` |
| Typical size | ~2 GB per 3B-parameter model (Q4 quantised) |

```bash
# Inspect the volume
docker volume inspect ollama_data

# Check disk usage of the volume
du -sh /var/lib/docker/volumes/ollama_data/_data

# List models currently in the volume
docker exec ollama ollama list
```

**Models survive container recreation**: because the volume is external, `docker compose down` and `--force-recreate` do not delete model files. Only `docker volume rm ollama_data` removes them.

### Backup Consideration

The `ollama_data` volume is **intentionally excluded** from automated filedata backups. Model weights are large (2+ GB each) and freely re-downloadable from the Ollama model registry, so backing them up wastes storage quota.

If you still want to include it, register it in
`backupServices/filedata/backup-volumes.conf` and configure its schedule,
mode, and destination in the filedata environment examples:

```text
ollama|ollama_data|default
```

Add `local` and/or `prod` to the profile list when Ollama is deployed on those
hosts.

Also add `OLLAMA_RETENTION_DAYS=7` to `backupServices/filedata/.env`.

The exclusion is intentional: Open WebUI stores user-owned state that should be recoverable,
while Ollama model files are large, reproducible artifacts that can be pulled again.

---

## Optional Resource Constraints (Quick Enable)

By default, Ollama runs without enforced memory or CPU limits.

To quickly enable limits on low-resource hosts:

1. Set desired values in `aiServices/ollama/.env.example` and copy/update `.env`.
2. In `aiServices/ollama/docker-compose.yml`, uncomment:
   - `mem_limit: ${OLLAMA_MEMORY_LIMIT}`
   - `cpus: ${OLLAMA_CPU_LIMIT}`
3. Recreate the container:

   ```bash
   docker compose -f aiServices/ollama/docker-compose.yml up -d --force-recreate
   ```

---

## GPU Acceleration

GPU is **disabled by default** (CPU-only inference). To enable:

1. Open `aiServices/ollama/docker-compose.yml`.
2. Under `deploy.resources`, uncomment **one** of the GPU `reservations` blocks:
   - **NVIDIA** — requires [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html#installation)
   - **AMD ROCm** — requires ROCm-capable GPU and drivers
3. Restart the container:

   ```bash
   docker compose -f aiServices/ollama/docker-compose.yml up -d --force-recreate
   ```

4. Verify GPU is picked up:

   ```bash
   docker exec ollama ollama ps   # shows active model + device
   ```

---

## Upgrading

Watchtower manages image updates automatically. To upgrade manually:

1. Pull the latest image for the rolling channel (`ollama/ollama`):

   ```bash
   docker compose -f aiServices/ollama/docker-compose.yml pull
   ```
2. Recreate the container:

   ```bash
   docker compose -f aiServices/ollama/docker-compose.yml up -d --force-recreate
   ```
3. Models stored in the external volume are **not affected**.

### Rollback

If the latest rolling image causes regressions:

1. Temporarily pin a known-good tag in `aiServices/ollama/docker-compose.yml` (example: `ollama/ollama:0.6.8`).
2. Pull and recreate the container:

   ```bash
   docker compose -f aiServices/ollama/docker-compose.yml pull
   docker compose -f aiServices/ollama/docker-compose.yml up -d --force-recreate
   ```
3. Verify health:

   ```bash
   docker ps --filter name=ollama --format "{{.Names}}: {{.Status}}"
   ```
4. Once the upstream issue is fixed, restore `image: ollama/ollama` and recreate again.

---

## Troubleshooting

| Symptom | Action |
|---|---|
| Container exits immediately | Check logs: `docker logs ollama`; ensure `ai_network` exists |
| API not responding | Check health: `docker ps --filter name=ollama`; wait for `(healthy)` |
| GPU not detected | Verify drivers installed; check uncommented GPU block in compose file |
| Model download fails | Check internet access from container: `docker exec ollama curl -I https://ollama.com` |
| High memory usage | Reduce `OLLAMA_MEMORY_LIMIT` in `.env` and recreate container |
