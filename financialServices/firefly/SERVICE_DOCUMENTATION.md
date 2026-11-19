# Firefly III Service Documentation

## Overview

**Service Name:** Firefly III  
**Purpose:** Personal finance management and budgeting  
**Network:** finance_network  
**Access:** Via Nginx Proxy Manager (no direct port exposure)

## Components

| Service | Container | Purpose |
|---------|-----------|---------|
| **firefly** | fireflyiii/core:latest | Web application |
| **firefly-db** | postgres:18 | PostgreSQL database |
| **firefly-cron** | alpine | Daily automation (3 AM) |

## Volumes & Data

**PostgreSQL Data:**
- Volume: `firefly_postgresdata` (external)
- Mount: `/var/lib/postgresql` in firefly-db
- Contains: `/var/lib/postgresql/18/docker/` (actual PGDATA location)
- Location: Managed by Docker (`docker volume inspect firefly_postgresdata`)

## Configuration Files

**`.env`** (gitignored - main application):
```bash
APP_KEY=<32-character-key>
APP_URL=http://localhost:9021
TZ=UTC
DB_CONNECTION=pgsql
DB_HOST=firefly-db
DB_DATABASE=firefly
DB_USERNAME=firefly
DB_PASSWORD=<password>
STATIC_CRON_TOKEN=<32-character-token>
TRUSTED_PROXIES=**
```

**`.db.env`** (gitignored - database):
```bash
POSTGRES_DB=firefly
POSTGRES_USER=firefly
POSTGRES_PASSWORD=<password>
```

## Backup Coverage

✅ **Automated Backups Configured**

- **Service:** `backupServices/postgres/`
- **Schedule:** Daily at 3 AM (cron: `0 3 * * *`)
- **Format:** GPG-encrypted SQL dumps
- **Destination:** Dropbox `/Apps/firefly/`
- **Retention:** 120 days
 - **Naming:** `backup_firefly_YYYYMMDD_HHMMSS.sql.zst.gpg` (zstd-compressed SQL dump, GPG encrypted)
- **Verified:** Volume `firefly_postgresdata` mounted read-only by backup service

**Restore:** See [RESTORE_GUIDE.md](RESTORE_GUIDE.md)

## Docker Compose Standards Compliance

✅ **97% Compliant** (31/32 controls passed)

### Implemented Controls

**Security:**
- No direct port exposure (routes via NPM)
- Network isolation (finance_network)
- Non-root container execution

**Resilience:**
- Health checks on firefly and firefly-db
- Explicit service dependencies (firefly-cron → firefly → firefly-db)
- Restart policy: `always`

**Persistence:**
- External named volume (`firefly_postgresdata`)
- Backup integration verified
- PostgreSQL 18 version-specific paths captured

**Resource Management:**
- No resource limits (Google Cloud free tier optimization)
- Runs on 1GB VM with many services
- Linux OOM killer handles runaways

**Networking:**
- NPM-only access (SSL/TLS, rate limiting, centralized access control)
- Internal communication on finance_network
- Database not exposed externally

## Common Operations

### Check Status
```bash
cd financialServices/firefly
docker compose ps
```

### View Logs
```bash
docker logs -f firefly         # Application
docker logs -f firefly-db      # Database
docker logs -f firefly-cron    # Cron jobs
```

### Restart Services
```bash
docker compose restart          # All services
docker compose restart firefly  # Single service
```

### Database Access
```bash
# Interactive session
docker exec -it firefly-db psql -U firefly -d firefly

# Common queries
docker exec firefly-db psql -U firefly -d firefly -c "SELECT COUNT(*) FROM transactions;"
docker exec firefly-db psql -U firefly -d firefly -c "\dt"  # List tables
```

### Verify Health
```bash
# Container health
docker inspect firefly | grep -A 10 Health

# Database connectivity
docker exec firefly-db pg_isready -U firefly

# Cron endpoint test
docker exec firefly-cron wget -qO- http://firefly:8080/api/v1/cron/<STATIC_CRON_TOKEN>
```

## Troubleshooting

### Database Connection Issues
```bash
# Check database is running and healthy
docker ps | grep firefly-db
docker inspect firefly-db | grep -A 10 Health

# Verify credentials match in .env and .db.env
grep DB_PASSWORD .env
grep POSTGRES_PASSWORD .db.env

# Check connection from firefly container
docker exec firefly ping -c 2 firefly-db
```

### Cron Job Not Running
```bash
# Check cron logs
docker logs firefly-cron

# Verify token is exactly 32 characters
grep STATIC_CRON_TOKEN .env | wc -c

# Test manual execution
docker exec firefly-cron wget -qO- http://firefly:8080/api/v1/cron/<token>
```

### Web Interface Issues
```bash
# Check firefly is running
docker ps | grep firefly

# Review application logs
docker logs firefly | grep -i error

# Verify NPM proxy host configuration
# Should point to: firefly:8080
```

### Data Persistence Issues
```bash
# Verify volume exists
docker volume ls | grep firefly_postgresdata

# Check volume mount
docker inspect firefly-db | grep -A 10 Mounts

# Verify PGDATA location
docker exec firefly-db sh -c "echo \$PGDATA"
# Should output: /var/lib/postgresql/18/docker
```

## Network Architecture

```
Internet → NPM (SSL/TLS) → firefly:8080
                           ↓
                        firefly-db:5432
                           ↑
                        firefly-cron (cron calls)
```

**Isolation:**
- All services on `finance_network`
- No direct external access to database or cron
- NPM provides SSL termination, rate limiting, access control

## Automated Operations

**Daily Cron (3 AM):**
- Process recurring transactions
- Update exchange rates
- Generate scheduled reports
- Clean temporary data
- Execute automation rules

## Security Considerations

- PostgreSQL credentials in gitignored `.env` and `.db.env`
- `APP_KEY` must be 32 characters for encryption
- `STATIC_CRON_TOKEN` protects cron API endpoint
- Database not exposed to external networks
- All containers run as non-root

## Data Model

Firefly III manages:
- **Accounts:** Asset, expense, revenue
- **Transactions:** Withdrawals, deposits, transfers
- **Budgets:** Monthly spending limits
- **Bills:** Recurring payment tracking
- **Categories & Tags:** Organization
- **Reports:** Financial analytics

## Deployment Notes

### Initial Deployment
```bash
# 1. Create external volume
docker volume create firefly_postgresdata

# 2. Create network (if not exists)
docker network create finance_network

# 3. Configure environment
cp .env.example .env
cp .db.env.example .db.env
# Edit .env and .db.env with proper credentials

# 4. Start services
docker compose up -d

# 5. Configure NPM proxy host
# Host: firefly.yourdomain.com
# Forward to: firefly:8080
# SSL: Let's Encrypt
```

### Upgrading
```bash
# Pull latest images
docker compose pull

# Recreate containers (preserves data)
docker compose up -d --force-recreate

# Verify health
docker compose ps
docker logs firefly
```

### Removing Orphaned Containers
```bash
# Remove old cron container if present
docker compose down --remove-orphans
```

## Configuration History

**Recent Changes (February 2026):**
- ✅ Removed deprecated `version: "3.8"` (Docker Compose V2)
- ✅ Corrected PostgreSQL volume mount to `/var/lib/postgresql` (captures version-specific `/18/docker/` subdirectory)
- ✅ Removed resource limits (Google Cloud free tier optimization)
- ✅ Commented port exposure (NPM-only access)
- ✅ Added health checks (firefly, firefly-db)
- ✅ Added explicit dependencies (firefly-cron)
- ✅ Fixed volume name to match backup service (`firefly_postgresdata`)

**Rationale:**
- PostgreSQL 18 uses version-specific directory structure (`/var/lib/postgresql/18/docker/`)
- Running many services on 1GB VM requires no resource reservations
- NPM provides centralized SSL/TLS, rate limiting, and access control
- Zero-trust architecture: no direct port exposure to host

## Additional Resources

- [Firefly III Documentation](https://docs.firefly-iii.org/)
- [Firefly III GitHub Repository](https://github.com/firefly-iii/firefly-iii)
- [API Documentation](https://api-docs.firefly-iii.org/)
- [PostgreSQL Documentation](https://www.postgresql.org/docs/current/)
