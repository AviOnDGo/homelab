# Watchtower Service Documentation

## Overview

Watchtower is an automated Docker container update service that monitors running containers and automatically pulls new images when available. It runs daily at 4 AM, ensures security patches are applied promptly, and sends Discord notifications for all update events.

**Key Features:**
- Automatic container image updates on configurable schedule
- Label-based exclusion for critical services (databases, password vaults)
- Discord webhook notifications for update events
- Automatic cleanup of old images after successful updates
- Preserves all container configuration (volumes, networks, env vars, labels)

## Configuration

### Environment Variables

All configuration is managed through `/securityServices/watchtower/.env`:

| Variable | Value | Description |
|----------|-------|-------------|
| `WATCHTOWER_SCHEDULE` | `0 4 * * *` | Cron schedule for updates (daily at 4 AM) |
| `WATCHTOWER_CLEANUP` | `true` | Remove old images after successful updates |
| `TZ` | `UTC` | Timezone for scheduling |
| `WATCHTOWER_NOTIFICATION_URL` | `discord://...` | Discord webhook for notifications (shoutrrr format) |
| `WATCHTOWER_NOTIFICATIONS` | `shoutrrr` | Notification system to use |
| `WATCHTOWER_INCLUDE_STOPPED` | `false` | Don't update stopped containers |
| `WATCHTOWER_INCLUDE_RESTARTING` | `true` | Update containers that are restarting |

### Excluded Containers

The following containers are protected from automatic updates via the `com.centurylinklabs.watchtower.enable=false` label:

- **vaultwarden** - Password vault requiring manual validation before updates
- **firefly-db** - PostgreSQL database for Firefly III financial data  
- **invidious-db** - PostgreSQL database for Invidious media service

These containers require manual updates to prevent data loss or service disruption.

## Operations

### Start Watchtower
```bash
cd securityServices/watchtower
docker compose up -d
```

### Stop Watchtower
```bash
cd securityServices/watchtower
docker compose down
```

### View Logs
```bash
# Recent logs
docker logs watchtower

# Follow live logs
docker logs -f watchtower

# Last 100 lines
docker logs watchtower | tail -100

# Check for excluded containers
docker logs watchtower | grep -i "excluded\|skipping"

# Check for monitored containers
docker logs watchtower | grep -i "found\|monitoring"
```

### Manual Update Trigger

To trigger an immediate update check (useful for testing):

```bash
docker exec watchtower /watchtower --run-once
```

Then monitor the logs:
```bash
docker logs -f watchtower
```

### Verify Container Status
```bash
# Check if Watchtower is running
docker ps | grep watchtower

# Inspect container details
docker inspect watchtower

# Verify labels on excluded containers
docker inspect vaultwarden | grep watchtower.enable
docker inspect firefly-db | grep watchtower.enable
docker inspect invidious-db | grep watchtower.enable
```

## Monitoring

### What to Monitor
- **Update success/failure notifications** - Check Discord channel daily
- **Log entries at 4 AM** - Verify scheduled runs complete successfully
- **Excluded containers** - Ensure they're not being updated
- **Disk space** - Old images should be cleaned up automatically

### Monthly Maintenance
1. Review update logs: `docker logs watchtower | tail -500`
2. Verify excluded containers still have labels: `docker inspect <container> | grep watchtower`
3. Check for any failed updates and investigate
4. Validate Discord notifications are being received

## Troubleshooting

### Watchtower Not Running
```bash
# Check container status
docker ps -a | grep watchtower

# View startup errors
docker logs watchtower

# Restart service
cd securityServices/watchtower
docker compose restart
```

### Discord Notifications Not Received
1. Verify webhook URL format in `.env` (should be `discord://webhook_id/webhook_token`)
2. Test webhook manually:
   ```bash
   curl -X POST "https://discord.com/api/webhooks/<id>/<token>" \
     -H "Content-Type: application/json" \
     -d '{"content": "Watchtower test notification"}'
   ```
3. Check Watchtower logs for notification errors

### Container Unexpectedly Updated
1. Verify the container has the exclusion label:
   ```bash
   docker inspect <container> | grep watchtower.enable
   ```
2. If missing, add label to `docker-compose.yml` and recreate container:
   ```yaml
   labels:
     - "com.centurylinklabs.watchtower.enable=false"
   ```
3. Recreate: `docker compose up -d`

### Update Failed
1. Check Watchtower logs for error details:
   ```bash
   docker logs watchtower | grep -i error
   ```
2. Common issues:
   - **Network failure**: Retry will occur on next schedule
   - **Image pull failure**: Check registry availability and credentials
   - **Container recreation failure**: Check service health and dependencies
3. Old image is retained automatically for manual rollback

### Rollback Process
If an update causes issues:

1. **Stop Watchtower** (prevent further updates):
   ```bash
   cd securityServices/watchtower
   docker compose down
   ```

2. **Identify old image**:
   ```bash
   docker images | grep <service-name>
   ```

3. **Stop and remove problematic container**:
   ```bash
   docker stop <container>
   docker rm <container>
   ```

4. **Recreate with old image**:
   ```bash
   cd <service-directory>
   # Edit docker-compose.yml to specify old image tag
   docker compose up -d
   ```

5. **Investigate logs** and determine root cause before re-enabling Watchtower

## Network Architecture

- **Network**: `security_network` (external)
- **Socket Access**: A pinned `watchtower-socket-proxy` service mounts
  `/var/run/docker.sock`; Watchtower cannot mount the host socket directly
- **No exposed ports** - Watchtower reaches the socket proxy by container DNS only

## Security Considerations

- Watchtower and the socket proxy are pinned to immutable image digests
- The proxy allowlist limits Docker API categories, but container update access
  remains security-sensitive
- Watchtower retains the ability to inspect, create, start, stop, restart, and
  replace containers through the proxy
- Services that do not require automatic updates must use the
  `com.centurylinklabs.watchtower.enable=false` exclusion label
- Homelab environment (single administrator, no multi-tenancy)

## References

- Official Documentation: https://containrrr.dev/watchtower/
- GitHub Repository: https://github.com/containrrr/watchtower
- Label-based filtering: https://containrrr.dev/watchtower/container-selection/
- Notification configuration: https://containrrr.dev/watchtower/notifications/
