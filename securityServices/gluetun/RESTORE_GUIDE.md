# Gluetun Restore Guide

## Overview

Gluetun is stateless. Recovery is redeploy + verification only. No backup payload restore is required.

## Script-First Recovery

### 1. Run restore script

```bash
cd securityServices/gluetun
./restore.sh
```

What the script does:

- Validates Docker availability
- Confirms redeploy-only recovery with operator prompt
- Runs `docker compose down` then `docker compose up -d`
- Verifies container is running and checks recent logs for VPN-ready indicators

### 2. Verify recovery

```bash
docker compose -f securityServices/gluetun/docker-compose.yml ps
docker compose -f securityServices/gluetun/docker-compose.yml logs --tail=80 gluetun
```

## Manual Fallback Recovery

```bash
cd securityServices/gluetun
docker compose down
docker compose up -d
docker compose logs --tail=80 gluetun
```

## Notes

- No volume data restore is performed.
- Ensure required runtime configuration files exist before redeploy.
