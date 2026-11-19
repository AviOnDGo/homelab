# Invidious Service Documentation

## Service Overview

**Service Name:** invidious  
**Database Service:** invidious-db  
**Companion Service:** companion (container: invidious-companion)  
**Network:** media_network  
**PostgreSQL Volume:** invidious_postgresdata  
**Web Interface Port:** 3000  
**Purpose:** Privacy-focused YouTube frontend

## Components

1. **Invidious** (invidious) - Main application container
2. **PostgreSQL Database** (invidious-db) - Data persistence for channels, videos, and user preferences
3. **Invidious Companion** (companion / invidious-companion) - YouTube library caching service

## Volume Locations

- **PostgreSQL Data:** `invidious_postgresdata` volume mounted at `/var/lib/postgresql` in invidious-db container
- **Location on Host:** Managed by Docker (use `docker volume inspect invidious_postgresdata` to find path)

## Configuration

### Environment Variables
Located in `.env` (not committed to git):

```bash
# PostgreSQL Configuration
POSTGRES_DB=invidious
POSTGRES_USER=kemal
POSTGRES_PASSWORD=<password>
```

### INVIDIOUS_CONFIG
Defined inline in `docker-compose.yml`:
- Database connection settings (host: `invidious-db`)
- HMAC key for API security
- Companion service configuration (private_url: `http://companion:8282/companion`)
- Companion secret key

## Backup Configuration

- **Script Location:** `backupServices/postgres/db-backup-script.sh`
- **Backup Format:** SQL dump with GPG encryption
- **Backup Retention:** 500 days
- **Backup Destination:** Dropbox (`/Apps/invidiousBackup`)

## Network Architecture

All Invidious services communicate within the isolated `media_network`:
- invidious → invidious-db (PostgreSQL connection)
- invidious → companion (YouTube library cache)
- No direct external access to database or companion

For external HTTP(S) egress, `invidious` also joins `security_network` and uses
the Gluetun HTTP proxy at `http://gluetun:8888`. The lowercase `http_proxy` and
`https_proxy` variables direct external requests through Gluetun, while
`no_proxy=localhost,127.0.0.1` keeps local requests direct. The database and
companion remain connected only to `media_network`.

Gluetun must be running and healthy for Invidious external requests to succeed.
Verify the proxy configuration with:

```bash
docker exec invidious env | grep -i proxy
```

## Service Dependencies

**Startup Order:**
1. invidious-db (must be ready first)
2. companion
3. invidious (depends on both)

**Critical Dependencies:**
- PostgreSQL database must be accessible at `invidious-db:5432`
- Companion service must be reachable at `http://companion:8282`
- HMAC and companion keys must match between services

## Common Operations

### Check Service Status
```bash
cd mediaServices/invidious
docker compose ps
```

### View Logs
```bash
# All services
docker compose logs -f

# Specific service
docker logs invidious
docker logs invidious-db
docker logs invidious-companion
```

### Restart Services
```bash
docker compose restart
```

### Verify Database Connection
```bash
docker exec -it invidious-db psql -U kemal -d invidious -c "\dt"
```

## Troubleshooting

### Database Connection Issues
- Verify `invidious-db` container is running
- Check credentials in `.env` match those in `INVIDIOUS_CONFIG`
- Ensure database host is set to `invidious-db` in config

### Companion Service Issues
- Verify `companion` container is healthy
- Check `SERVER_SECRET_KEY` matches `invidious_companion_key`
- Test connectivity: `docker exec invidious wget -qO- http://companion:8282/companion`

### Video Playback Problems
- Clear browser cache
- Verify companion service is running
- Check Invidious logs for YouTube API errors
- Confirm HMAC key is correctly configured

## Security Considerations

- PostgreSQL credentials stored in `.env` (excluded from git)
- HMAC key used for API request signing
- Companion service uses secret key for authentication
- Invidious external HTTP(S) egress is routed through Gluetun on `security_network`
- Database and companion services remain isolated within `media_network`
- No containers run as root (companion has `cap_drop: ALL`)

## Restoration

For database restoration procedures, see [RESTORE_GUIDE.md](RESTORE_GUIDE.md)

## Additional Resources

- [Invidious Documentation](https://docs.invidious.io/)
- [Invidious GitHub Repository](https://github.com/iv-org/invidious)
- [PostgreSQL Documentation](https://www.postgresql.org/docs/current/)
