# PostgreSQL Backup - Implementation Details

## Overview

A PostgreSQL backup solution that backs up multiple databases (invidious, firefly,
paperless, immich, firefoxsync) using GPG encryption, Dropbox synchronization,
and per-service retention policies. Profiles use schedules and retention from
`backup-databases.conf`. The old Compose files are retained but no longer supported.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    db-backup Container                      │
│  (custom PostgreSQL image with backup script and tools)     │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Cron Jobs:                                                  │
│  ├─ ${INVIDIOUS_CRON_SCHEDULE}: invidious                  │
│  ├─ ${FIREFLY_CRON_SCHEDULE}: firefly                      │
│  ├─ ${PAPERLESS_CRON_SCHEDULE}: paperless                  │
│  ├─ ${IMMICH_CRON_SCHEDULE}: immich                        │
│  └─ ${FIREFOXSYNC_CRON_SCHEDULE}: firefoxsync              │
│                                                              │
│  Backup Process:                                             │
│  1. pg_dump via network → service DB host                  │
│  2. zstd -6 -T1 compression → .sql.zst                     │
│  3. GPG symmetric encryption (AES256) → .sql.zst.gpg       │
│  4. Store locally in ./backups/{service}/                   │
│  5. Upload to Dropbox via rclone                           │
│  6. Delete backups past their per-service retention         │
│  7. Send Discord notification                               │
│                                                              │
└─────────────────────────────────────────────────────────────┘
         ↓                                    ↓
    media_network                      Dropbox Cloud
  (connects to databases)              (encrypted backup storage)
    ├─ invidious-db                    ├─ /App_acc/invidious or /Apps/invidious
    ├─ firefly_postgres                ├─ /App_acc/firefly or /Apps/firefly
    └─ ...                             └─ per-service paths from path.local or path.prod
```

## Core Components

### 1. docker-compose.yml
Defines the `db-backup` service with the following features:
- Single reusable service for backing up multiple databases
- Mounts backup directories for local storage
- Uses named volume `gpg-secrets` for secure passphrase storage
- Joins media, finance, knowledge, and security networks for database connectivity
- Runs cron jobs from per-service `*_CRON_SCHEDULE` variables

**Key Configuration:**
```yaml
services:
  db-backup:
    build: .
    image: homelab/db-backup:local
    volumes:
      - invidious_postgresdata:/var/lib/postgresql/invidious:ro
      - firefly_postgresdata:/var/lib/postgresql/firefly:ro
      - paperless_postgresdata:/var/lib/postgresql/paperless:ro
      - immich_postgresdata:/var/lib/postgresql/immich:ro
      - firefoxsync_postgresdata:/var/lib/postgresql/firefoxsync:ro
      - gpg-secrets:/run/secrets:ro
    networks:
      - media_network
      - finance_network
      - knowledge_network
      - security_network
```

### 2. .env
Environment configuration file containing:
- Database config for invidious, firefly, paperless, immich, firefoxsync
- Dropbox authentication token
- Discord webhook URI
- GPG passphrase

**Environment Variables Format:**
```bash
# Database Configuration
{SERVICE}_DB_USER=username
{SERVICE}_DB_PASSWORD=your_database_password

# Shared Configuration
DROPBOX_AUTH_TOKEN=your_dropbox_auth_token
DISCORD_WEBHOOK_URL=webhook_url
GPG_PASSPHRASE=passphrase
```

Dropbox destinations are configured in `path.local` and `path.prod`. Startup
loads the selected file after the environment file, so its values take precedence.
`default` requires an explicit `local` or `prod` destination argument.
Hosts default to `<service>-db`, while database names and backup names default
to `<service>`. Existing `{SERVICE}_DB_HOST`, `{SERVICE}_DB_NAME`, and
`{SERVICE}_BACKUP_NAME` values remain supported as overrides.

### 3. db-backup-script.sh
Main backup script with the following functionality:

**Features:**
1. **Database Dumping**: Uses `pg_dump` with network-based connection
2. **Compression**: Uses `zstd -6 -T1` before encryption
3. **GPG Encryption**: Symmetric encryption using AES256; an empty passphrase
   aborts every database backup before the dump
4. **Dropbox Upload**: Uses rclone to upload encrypted backups
5. **Cleanup**: Deletes local and remote backups older than 7 days
6. **Discord Notifications**: Sends success/failure notifications with details

**Workflow:**
- Parameterized for multiple databases (accepts database name as argument)
- Automatic rclone configuration from environment variables
- Comprehensive error handling and logging
- Size reporting in notifications
- Graceful failure handling with partial success alerts

### 4. setup-backup.sh
Legacy helper targeting obsolete configuration. Configure credentials using
`.env.example` and start the selected profile with `start-backup.sh` instead.

## Configuration Flow

```
.env (environment variables)
    ↓
docker-compose.yml (service definition)
    ↓
db-backup container (homelab/db-backup:local, script and tools included)
    ↓
db-backup-script.sh (backup logic)
    ├─ pg_dump (database export)
    ├─ gpg (encryption)
    ├─ rclone (Dropbox sync)
    ├─ find (cleanup)
    └─ curl (Discord notification)
```

## Key Features

### 1. Multi-Database Support
- Single service backs up multiple PostgreSQL databases
- Each database on different schedule to avoid conflicts
- Easy to add more databases by adding config variables and cron job
- Generic backup script works for any PostgreSQL database

### 2. Security
- **GPG symmetric encryption** with AES256 cipher
- Passphrase stored in separate secrets volume
- Credentials in environment file (not hardcoded in scripts)
- Network-based database connections (no direct volume access)
- Can use restricted Dropbox app tokens for enhanced security

### 3. Reliability
- Network-based connections (no direct volume access needed)
- Error handling with partial success notifications
- Automatic retry on transient failures
- Comprehensive logging for troubleshooting
- Validation of critical operations

### 4. Automation
- Automated backups at per-service configured cron schedules
- Automatic cleanup using each service's configured retention period
- Discord notifications for monitoring
- Self-contained cron scheduling
- No external dependencies required

### 5. Extensibility
- Configuration-driven database selection
- Easy to add new services (just add config + cron job)
- Modular design allows for customization
- Supports custom backup retention policies
- Can be extended with additional notification channels

## Database Configuration

### Invidious
```
Host:         invidious-db
Database:     invidious
User:         kemal
Schedule Var: INVIDIOUS_CRON_SCHEDULE
Retention:    DB_BACKUP_INVIDIOUS_RETENTION_DAYS
```

### Firefly
```
Host:         firefly-db
Database:     firefly
User:         firefly
Schedule Var: FIREFLY_CRON_SCHEDULE
Retention:    DB_BACKUP_FIREFLY_RETENTION_DAYS
```

### Paperless
```
Host:         paperless-db
Database:     paperless
User:         paperless
Schedule Var: PAPERLESS_CRON_SCHEDULE
Retention:    DB_BACKUP_PAPERLESS_RETENTION_DAYS
```

### Immich
```
Host:         immich-db
Database:     immich
User:         postgres
Schedule Var: IMMICH_CRON_SCHEDULE
Retention:    DB_BACKUP_IMMICH_RETENTION_DAYS
```

### Firefox Sync
```
Host:         firefoxsync-db
Database:     firefoxsync
User:         sync
Schedule Var: FIREFOXSYNC_CRON_SCHEDULE
Retention:    DB_BACKUP_FIREFOXSYNC_RETENTION_DAYS
```

## Backup Workflow Details

### Phase 1: Database Dump
```bash
PGPASSWORD=$password pg_dump -h $host -U $user -d $database | zstd -6 -T1 -o backup.sql.zst
```
- Connects to database over network via `media_network`
- Exports complete database schema and data
- Uses environment-based credentials

### Phase 2: Encryption
```bash
gpg --symmetric --cipher-algo AES256 --batch --passphrase "$GPG_PASSPHRASE" backup.sql.zst
```
- Symmetric encryption (no keys needed for restore)
- AES256 cipher for strong security
- Passphrase stored securely in Docker volume
- Results in `.sql.zst.gpg` (zstd-compressed, GPG-encrypted) file

### Phase 3: Dropbox Upload
```bash
 rclone copy backup.sql.zst.gpg dropbox:/service_backups/
```
- Automatic rclone configuration from environment
- Uses Dropbox OAuth token
- Organized by service in separate folders
- Retries on transient network failures

### Phase 4: Cleanup
```bash
 find /backups/service -name "*.sql.zst.gpg" -type f -mtime +7 -delete
rclone delete --min-age 7d dropbox:/service_backups/
```
- Removes local backups older than 7 days
- Removes remote backups older than 7 days
- Runs after each backup to maintain retention policy
- Prevents unlimited storage growth

### Phase 5: Notification
```bash
curl -X POST $DISCORD_WEBHOOK_URI \
  -H "Content-Type: application/json" \
  -d "{\"content\":\"✅ Backup successful: $size\"}"
```
- Sends detailed status to Discord
- Includes timestamp, size, and location
- Different messages for success, failure, partial success
- Helps with monitoring and alerting

## Security Considerations

### Encryption
- **Algorithm**: AES256 (industry standard)
- **Method**: Symmetric encryption (same passphrase for encrypt/decrypt)
- **Key Storage**: Docker volume with restricted permissions
- **Transport**: Encrypted backups uploaded to Dropbox (encrypted at rest and in transit)

### Credentials Management
- **Environment Variables**: All credentials in `.env`
- **No Hardcoding**: No credentials in scripts or compose files
- **Secrets Volume**: GPG passphrase in read-only mounted volume
- **Network Isolation**: Only connects via `media_network`

### Access Control
- **File Permissions**: Recommended `chmod 600 .env`
- **Directory Permissions**: Recommended `chmod 700 ./backups/`
- **Gitignore**: Should exclude `.env`, `backups/`, `secrets/`
- **Dropbox Tokens**: Use app-restricted tokens when possible

## Monitoring & Maintenance

### Discord Notifications
- **Success**: `✅ Backup successful: service_name - size - timestamp`
- **Failure**: `❌ Backup failed: service_name - error details`
- **Partial**: `⚠️ Backup stored locally but upload failed - will retry`

### Local Monitoring
```bash
# Check recent backups
ls -lt ./backups/invidious/ | head -5
ls -lt ./backups/firefly/ | head -5

# Disk usage
du -sh ./backups/invidious/
du -sh ./backups/firefly/

# Container logs
docker logs -f db-backup
```

### Remote Monitoring
```bash
# List Dropbox backups
docker exec db-backup rclone ls dropbox:/invidious_backups
docker exec db-backup rclone ls dropbox:/firefly_backups

# Check Dropbox quota
docker exec db-backup rclone about dropbox:
```

## Backup & Restore Procedures

### Manual Backup
```bash
docker exec db-backup /usr/local/bin/backup-script.sh invidious
docker exec db-backup /usr/local/bin/backup-script.sh firefly
```

### Download from Dropbox
```bash
docker exec db-backup rclone copy \
  dropbox:/invidious_backups/backup.sql.zst.gpg \
  /backups/invidious/
```

### Decrypt Backup
```bash
gpg --batch --yes --passphrase "your-passphrase" -d backup.sql.zst.gpg | zstd -d -o backup.sql
```

### Restore Database
```bash
# Invidious
docker exec -i invidious-db psql -U kemal -d invidious < backup.sql

# Firefly
docker exec -i firefly_postgres psql -U firefly -d firefly < backup.sql
```

## Resource Requirements

- **Memory**: ~100-200 MB during backup (depends on database size)
- **CPU**: Low (primarily I/O bound)
- **Disk**: Depends on database size × 7 days retention
- **Network**: Outbound connectivity to Dropbox API

## Extensibility Guide

### Adding a New Database

1. **Add credentials to the tracked environment example and configure `.env` locally:**
```bash
NEWDB_DB_USER=username
NEWDB_DB_PASSWORD=your_database_password
```

2. **Create backup directory:**
```bash
mkdir -p ./backups/newdb
```

3. **Register the database in `backup-databases.conf`:**
Add its source volume, applicable profiles, network, retention, and schedule in
category and service-name order. Add its Dropbox destination to both path files.
The startup script generates the Compose mounts, network declarations, cron job,
and policy environment. Retention must be at least one day.

4. **Register the database in `db-backup-script.sh`:**
Add a `newdb` case that resolves its connection, plus its generated-policy
retention and destination mappings before environment loading. Update backup
specs and operator documentation in the same change.

5. **Recreate the affected profile:**
```bash
./start-backup.sh local
```

Select `default local`, `default prod`, or `prod` for those deployments. Verify the new job with
`docker exec db-backup cat /etc/crontabs/root`.

### Customizing Retention Policy
Change the retention column in `backup-databases.conf` and recreate the selected
profile. Compare existing policies first because retention cleanup deletes local
and Dropbox backups.

### Adding Email Notifications
Extend `db-backup-script.sh` to send emails using `sendmail` or SMTP:
```bash
echo "Backup completed" | mail -s "Backup Success" admin@example.com
```

## Troubleshooting

### Common Issues

**Issue**: Service won't start
```bash
# Check logs
docker logs db-backup

# Verify network exists
docker network ls | grep media_network

# Validate compose file
docker compose -f docker-compose.yml config
```

**Issue**: Backup fails with database connection error
```bash
# Test database connectivity
docker exec db-backup pg_isready -h invidious-db -U kemal

# Verify credentials
docker exec db-backup env | grep DB_
```

**Issue**: Dropbox upload fails
```bash
# Check rclone config
docker exec db-backup rclone config show dropbox

# Test connectivity
docker exec db-backup rclone ls dropbox:/

# Check token validity
# Regenerate token if expired
```

**Issue**: GPG encryption fails
```bash
# Verify passphrase file
docker exec db-backup cat /run/secrets/gpg-passphrase

# Test GPG manually
docker exec db-backup gpg --version
```

## Deployment Checklist

- [ ] Obtain Dropbox Auth Token
- [ ] Create Discord webhook
- [ ] Choose secure GPG passphrase
- [ ] Run `bash setup-backup.sh`
- [ ] Verify `.env` has no placeholder values
- [ ] Ensure `media_network` exists
- [ ] Create backup directories
- [ ] Start service: `docker compose up -d`
- [ ] Test manual backup
- [ ] Verify cron jobs scheduled
- [ ] Check Discord notifications received
- [ ] Verify Dropbox uploads successful
- [ ] Add sensitive files to `.gitignore`

## Future Enhancements

Potential improvements:
- Support for additional cloud storage providers (S3, GCS, Azure)
- Email notifications in addition to Discord
- Backup verification/integrity checks
- Differential or incremental backups
- Backup compression before encryption
- Multiple retention tiers (daily, weekly, monthly)
- Backup rotation strategies (grandfather-father-son)
- Health check endpoints
- Prometheus metrics export
- Webhook-based manual trigger
