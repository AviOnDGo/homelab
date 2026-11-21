# Invidious Service Context

## Overview
Invidious is a privacy-respecting alternative frontend for YouTube. This service runs in Docker containers with PostgreSQL as the database backend.

## Architecture

### Services
The deployment consists of three interconnected services:

1. **invidious** - Main application service
   - Image: `quay.io/invidious/invidious:latest`
   - Port: `3000:3000`
   - Depends on: `invidious-db`
   - Purpose: YouTube frontend interface

2. **companion** - Invidious companion service
   - Image: `quay.io/invidious/invidious-companion:latest`
   - Internal communication on port 8282
   - Purpose: Handles YouTube library caching and additional features
   - Communication URL: `http://companion:8282/companion`

3. **invidious-db** - PostgreSQL 14 database
   - Image: `postgres:14`
   - Container name: `invidious-db`
   - Volume: `postgresdata` → `/var/lib/postgresql/data`
   - Purpose: Persistent storage for Invidious data

### Network
- Network name: `media_network`
- Type: Internal (not external)
- All three services communicate on this network

## Configuration Files

### .env
Contains all sensitive credentials and configuration:
- `POSTGRES_DB=invidious` - Database name
- `POSTGRES_USER=kemal` - Database user
- `POSTGRES_PASSWORD=kemal` - Database password
- `GPG_PASSPHRASE=vanilla absolve-spout-conductor-tulip-confusing` - For backup encryption/decryption
- `CONTAINER_NAME=invidious-db` - Database container identifier
 - `BACKUP_FILE=/path/to/backup.sql.zst.gpg` - Path to encrypted, zstd-compressed backup file

### docker-compose.yml
Orchestrates the three-service stack with:
- Service dependencies (`invidious` depends on `invidious-db`)
- Environment variable injection from `.env`
- Volume management for persistent data
- Network configuration
- Security settings (companion service uses read-only filesystem)

## Backup and Restore Infrastructure

### Current Implementation Status
✅ **Restore Script** - `restore.sh` (Created: December 12, 2025)
❌ **Backup Script** - Not yet implemented
❌ **Remote Backup** - Not yet implemented

### Restore Process (restore.sh)

**Purpose:** Restore Invidious PostgreSQL database from an encrypted GPG backup file.

**Script Location:** `mediaServices/invidious/restore.sh` (relative to the repository root)

**Workflow:**
1. **Configuration Loading**
   - Sources `.env` file for all required variables
   - Validates presence of: `POSTGRES_DB`, `POSTGRES_USER`, `POSTGRES_PASSWORD`, `GPG_PASSPHRASE`, `BACKUP_FILE`
   - Auto-detects container name if not specified

2. **Backup File Validation**
   - Verifies backup file exists at specified path
   - Checks file accessibility

3. **Container Status Management**
   - Checks if database container exists (exits with error if not)
   - Verifies if container is running
   - Starts container automatically if stopped
   - Waits for PostgreSQL to become ready (max 10 attempts, 3-second intervals)

4. **Database Restoration**
   - Decrypts GPG file using passphrase from `.env`
   - Pipes decrypted SQL directly to PostgreSQL via `docker exec`
   - Command: `gpg --decrypt | docker exec -i psql`

5. **Verification and Reporting**
   - Counts tables in restored database
   - Displays color-coded success/failure messages
   - Provides troubleshooting hints on failure

**Usage:**
```bash
# Run from the repository root
cd mediaServices/invidious
./restore.sh
```

**Key Features:**
- ✅ No manual input required - all secrets from `.env`
- ✅ Automatic container lifecycle management
- ✅ Database readiness checking
- ✅ Comprehensive error handling
- ✅ Color-coded terminal output
- ✅ Verification step after restore

**Dependencies:**
- Docker (for container management)
- GPG (for decryption)
- PostgreSQL client tools (bundled in container)
- Bash shell

## Database Details

### PostgreSQL Configuration
- **Version:** 14
- **Database Name:** `invidious`
- **User:** `kemal`
- **Password:** `kemal`
- **Data Volume:** `postgresdata`
- **Mount Point:** `/var/lib/postgresql/data`

### Container Naming
Docker Compose generates the container name as:
- Format: `<directory>-<service>-<replica>`
- Actual: `invidious-db`

## Security Considerations

### Encryption
- All backups are encrypted with GPG using AES256 cipher
- Passphrase stored in `.env` file (should be kept secure)
- `.env` file should never be committed to version control

### Container Security (companion service)
- Runs with no capabilities (`cap_drop: ALL`)
- Read-only root filesystem
- No new privileges allowed
- Minimizes attack surface

### API Keys
- **HMAC Key:** `REDACTED` - Used for request signing
- **Companion Key:** `REDACTED` - Used for internal service communication
- **Note:** Documentation recommends using different keys for HMAC and Companion

## Future Implementation Needs

### 1. Backup Script
Pattern to follow from other homelab services (financialServices):
- Create `dataBackup.sh` script
- OS detection (Linux/macOS)
- Container runtime detection (Docker/Podman)
 - Generate timestamped filename: `invidious_YYYY-MM-DD.sql.zst.gpg`
- Database dump with GPG encryption
- Target directory: `~/invidiousBackup`
- Call remote backup script after successful backup

### 2. Remote Backup Script
Pattern to follow from securityServices:
- Create `remoteBackupInvidious.sh` script
- Upload to cloud storage via `rclone`
- Target remote: `dropbox:Apps/invidiousBackup`
- Support multiple remotes if needed
- Progress reporting

### 3. Scheduled Automation
- Add cron job or systemd timer for automatic backups
- Integrate with the centralized backup services rather than committing backups
  to Git
- Daily backup schedule recommended

### 4. Notification System
- Use the existing backup-service notification mechanism for Discord webhooks
- Notify on backup success/failure
- Include backup size and duration in notifications

## Operational Notes

### Starting the Stack
```bash
# Run from the repository root
cd mediaServices/invidious
docker-compose up -d
```

### Stopping the Stack
```bash
docker-compose down
```

### Viewing Logs
```bash
docker-compose logs -f invidious
docker-compose logs -f invidious-db
```

### Database Access
```bash
docker exec -it invidious-db psql -U kemal -d invidious
```

### Volume Management
The PostgreSQL data persists in the `postgresdata` named volume. To completely reset:
```bash
docker-compose down
docker volume rm invidious_postgresdata
docker-compose up -d
```

## Troubleshooting

### Restore Failures
Common issues and solutions:
1. **Invalid GPG passphrase** - Verify `GPG_PASSPHRASE` in `.env`
2. **Container not found** - Run `docker-compose up -d` first
3. **Database not ready** - Script auto-handles with retry logic
4. **Corrupted backup** - Verify backup file integrity
5. **Permission issues** - Ensure Docker user has proper permissions

### Container Issues
```bash
# Check container status
docker ps -a | grep invidious

# Restart containers
docker-compose restart

# View container logs
docker-compose logs -f
```

## Development History

### December 12, 2025
- **Created:** `restore.sh` script
- **Features implemented:**
  - Environment-based configuration
  - Container lifecycle management
  - GPG decryption with streaming
  - Database readiness checking
  - Comprehensive error handling
  - Verification after restore

### Changes from Original dataRestoreInvidious.sh
The new `restore.sh` differs from any existing restore scripts:
- Uses `.env` for all secrets (no user prompts)
- Automatic container start if stopped
- No temporary files (direct piping)
- Enhanced validation and error messages
- Cleaner, more maintainable code structure

## References

### Related Documentation
- Invidious Configuration: https://github.com/iv-org/invidious/blob/master/config/config.example.yml
- PostgreSQL 14 Documentation: https://www.postgresql.org/docs/14/

### Homelab Patterns
This service follows established patterns from:
- **financialServices** - PostgreSQL backup/restore pattern
- **securityServices** - Enhanced container runtime detection
- **containerServices** - Docker Compose orchestration

### File Locations
- Service directory: `mediaServices/invidious/` (relative to the repository root)
- Backup directory: `~/invidiousBackup/` (recommended, not yet created)
- Remote path: `Apps/invidiousBackup` (for rclone, not yet configured)
