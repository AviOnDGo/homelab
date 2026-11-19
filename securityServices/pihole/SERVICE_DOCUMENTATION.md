# Pi-hole DNS Service

Pi-hole network-wide ad blocking DNS server for the homelab infrastructure.

## Service Configuration

- **Container:** `pihole`
- **Image:** `pihole/pihole:latest`
- **Network:** `service` (local network)
- **Ports:** 
  - 53/tcp, 53/udp (DNS)
  - 9004:80 (Web Interface)
- **Volume:** `filedata` mounted at `/etc/pihole`

## Volume Migration History

**Date:** February 8, 2026  
**Change:** Migrated from legacy `piholedata` volume to standardized `filedata` volume name

This migration aligns Pi-hole with the homelab's standardized volume naming conventions:
- Non-database storage uses `filedata` volume name
- Consistent with other services (NPM, etc.)
- Simplifies backup and maintenance procedures

See [RESTORE_GUIDE.md](./RESTORE_GUIDE.md) for restore and rollback instructions.

## Access

- Web Interface: http://localhost:9004/admin
- Password: Set via `FTLCONF_webserver_api_password` environment variable

## Data Persistence

The following data persists in the `filedata` volume:
- DNS blocklists (gravity.db)
- Query logs (pihole-FTL.db)
- Custom DNS records and CNAME entries
- Pi-hole settings and configuration
- DHCP lease information (if DHCP enabled)

## Maintenance

### Start Service
```bash
docker compose up -d
```

### Stop Service
```bash
docker compose down
```

### View Logs
```bash
docker compose logs -f
```

### Update Image
```bash
docker compose pull
docker compose up -d
```

## Backup Considerations

The `filedata` volume should be included in backup procedures to preserve:
- Custom blocklist configurations
- Historical query data
- Pi-hole settings

Volume location: `/var/lib/docker/volumes/pihole_filedata/_data`
