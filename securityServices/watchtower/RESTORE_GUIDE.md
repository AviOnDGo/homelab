# Watchtower Restore Guide

## Overview

Watchtower is stateless. Recovery is redeploy + verification only. No backup payload restore is required.

## Script-First Recovery

### 1. Run restore script

```bash
cd securityServices/watchtower
./restore.sh
```

What the script does:

- Validates Docker availability
- Confirms redeploy-only recovery with operator prompt
- Runs `docker compose down` then `docker compose up -d`
- Verifies container is running and checks recent logs for scheduling/update indicators

### 2. Verify recovery

```bash
docker compose -f securityServices/watchtower/docker-compose.yml ps
docker compose -f securityServices/watchtower/docker-compose.yml logs --tail=80 watchtower
```

## Manual Fallback Recovery

```bash
cd securityServices/watchtower
docker compose down
docker compose up -d
docker compose logs --tail=80 watchtower
```

## Notes

- No volume data restore is performed.
- Watchtower requires host Docker socket access at `/var/run/docker.sock`.
