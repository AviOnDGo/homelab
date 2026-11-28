# PostgreSQL Backup - Quickstart Guide

## Compose Profile Selection

Select the deployment profile when starting the service:

| Environment | Command | Current backup scope |
|-------------|--------------|----------------------|
| Default homelab | `./start-backup.sh default local` or `./start-backup.sh default prod` | `firefly`, `romm`, `paperless`, `immich`, `invidious`, `firefoxsync` |
| Prod | `./start-backup.sh prod` | `firefly` |
| Local | `./start-backup.sh local` | `romm`, `paperless`, `immich`, `invidious` |

The script generates a temporary Compose override from `backup-databases.conf`
and removes it after deployment. It fails before deployment if a selected source
volume or network is missing. The base Compose file cannot start backups alone.
Every registered database is included in `default`, so all registered volumes
and networks, including Firefox Sync's, are required when starting that profile.
The old Local and Remote Compose files remain in the repository but are no
longer supported. Start backups with `start-backup.sh`.

Generated profiles use schedules and retention from `backup-databases.conf`.
Retention must be a positive number of days. The backup script requires the
generated policy and ignores older retention settings. The `local` and `prod`
profiles load `path.local` and `path.prod` respectively; `default` requires an
explicit destination choice. The selected path file overrides older destination
settings. Missing or invalid path entries stop deployment.
Schedules use five BusyBox cron fields; weekday numbers range from 0 (Sunday)
through 6 (Saturday). Startup checks the field count and allowed characters,
but not field ranges or steps; verify schedules before deployment.

Before migrating an existing deployment, compare its current schedules and
retention values with the registry and adjust the registry if necessary. Retention
controls deletion of local and Dropbox backups. Compare existing Dropbox paths
with the selected path file before recreating the container: the selected paths
control both uploads and remote cleanup. In particular, the previous Invidious
script default was 7 days, while the registry specifies 30 days.

### Compose And Crontab Ordering

The generated profiles order source mounts, top-level volumes, and cron jobs by service
category, then name: Financial, Gaming, Knowledge, Media, and Security Services,
as applicable. Source-volume sections use `## <Category> Services` comments;
generated crontabs use matching `# <Category> Services` comments. The crontab
header `# Crontab for database backups` is written with `>`; category comments
and jobs are appended with `>>`.

Network references and declarations are sorted by network name. Disabled entries
retain their sorted positions. Shared secrets follow source
volumes, and `gpg-secrets` follows top-level source-volume declarations. These
ordering rules do not change configured cron execution times.

When adding a database-backed service, register it in `backup-databases.conf`,
add its case to `db-backup-script.sh`, and update the environment example, specs,
and service documentation. The backup script needs both a database case and a
registry-retention mapping for each added database.

## 🚀 Setup (5 minutes)

### Step 1: Configure Credentials

From `backupServices/postgres`, create `.env` from `.env.example` if it does not
already exist. Configure the selected databases' usernames and passwords, Dropbox
credentials, and GPG passphrase; the Discord webhook is optional. Do not overwrite
an existing `.env`. The older `setup-backup.sh` targets obsolete configuration.

Database hosts default to `<service>-db`; database names and backup names default
to `<service>`. Existing `{SERVICE}_DB_HOST`, `{SERVICE}_DB_NAME`, and
`{SERVICE}_BACKUP_NAME` settings remain supported as overrides.

Every database backup requires a nonempty GPG passphrase. The
`/run/secrets/gpg-passphrase` file takes precedence over `GPG_PASSPHRASE`,
even if the file is empty. If the selected passphrase is empty, the backup
fails before creating or uploading a dump.

### Step 2: Start the Service
```bash
./start-backup.sh local
```

The local `homelab/db-backup:local` image includes the backup script and all tools,
including `zstd`, on a digest-pinned PostgreSQL Alpine base. No scripts are
bind-mounted from the host and no packages are installed during startup. This
allows Docker to restart it before an encrypted home directory is unlocked.
The build context allowlist in `.dockerignore` excludes credentials and unrelated
files. Compose reads `.env` only during creation/recreation; Docker uses the stored
container environment when restarting it.

To migrate an existing container or apply script/dependency changes:

```bash
./start-backup.sh local
docker inspect --format '{{.State.Status}} {{.HostConfig.RestartPolicy.Name}}' db-backup
docker inspect --format '{{range .Mounts}}{{println .Type .Destination}}{{end}}' db-backup
docker exec db-backup pidof crond
```

Rebuild and recreate after script changes; restarting alone does not update the
image. Leave the container running before reboot: `unless-stopped` preserves
an explicit stop.

### Step 3: Verify Running
```bash
# Check container status
docker ps | grep db-backup

# View logs
docker logs -f db-backup

# Verify cron jobs
docker exec db-backup cat /etc/crontabs/root
```

## 🧪 Test Backup

For the default environment:
```bash
# Test Invidious backup
docker exec db-backup /usr/local/bin/backup-script.sh invidious

# Test Firefly backup
docker exec db-backup /usr/local/bin/backup-script.sh firefly

# Test Firefox Sync backup
docker exec db-backup /usr/local/bin/backup-script.sh firefoxsync

# Check backed up files
ls -lah ./backups/invidious/
ls -lah ./backups/firefly/
```

For the local environment:
```bash
# Test RomM backup
docker exec db-backup /usr/local/bin/backup-script.sh romm

# Test Invidious backup
docker exec db-backup /usr/local/bin/backup-script.sh invidious

# Test Paperless backup
docker exec db-backup /usr/local/bin/backup-script.sh paperless

# Test Immich backup
docker exec db-backup /usr/local/bin/backup-script.sh immich

```

For the prod environment:
```bash
# Test Firefly backup
docker exec db-backup /usr/local/bin/backup-script.sh firefly
```

## 📅 Backup Schedule

### Effective Schedule (from `backup-databases.conf`)

| Database | Schedule | Retention |
|----------|----------|-----------|
| Firefly | `5 3 * * *` | 120 days |
| RomM | `25 3 * * *` | 30 days |
| Paperless | `10 3 * * *` | 30 days |
| Immich | `0 2 * * *` | 30 days |
| Invidious | `0 3 */2 * *` | 30 days |
| Firefox Sync | `20 3 * * *` | 30 days |

Recreate the selected profile after changing a registry policy. Manually running
a database not selected by the profile fails rather than using a fallback policy.

### Profile Notes

- `./start-backup.sh default local` or `./start-backup.sh default prod` schedules
  all six registered databases using the chosen destination file.
- `./start-backup.sh local` schedules `romm`, `paperless`, `immich`, and `invidious`.
- Firefox Sync is registered in `default` only; it is not scheduled in `local`
  or `prod`.
- Paperless runs in `knowledgeServices/paperless/` on `knowledge_network`. Both the
  default and Local backup profiles join that network to reach `paperless-db`;
  keep `media_network` for Invidious.
- `./start-backup.sh prod` schedules `firefly`.

Automatic cleanup uses each database's configured retention for local and
Dropbox backups.

## 🔧 Common Commands

```bash
# Start or recreate the selected profile
./start-backup.sh local

# Stop service
docker stop db-backup

# Restart the existing container with its stored configuration
docker start db-backup

# View logs
docker logs -f db-backup

# Manual backup
docker exec db-backup /usr/local/bin/backup-script.sh invidious
docker exec db-backup /usr/local/bin/backup-script.sh firefly
```

## ❓ Troubleshooting

### Service won't start
```bash
docker logs db-backup
```

### Backup not running at scheduled time
```bash
# Check cron logs
docker logs db-backup | grep -i cron

# Manually run to test
docker exec db-backup /usr/local/bin/backup-script.sh invidious
```

### No Discord notifications
- Verify webhook URL in `.env`
- Test webhook:
```bash
curl -X POST "YOUR_WEBHOOK_URL" \
  -H "Content-Type: application/json" \
  -d '{"content":"Test message"}'
```

### Dropbox upload fails
```bash
# Check rclone config
docker exec db-backup rclone config show dropbox

# Test Dropbox access
docker exec db-backup rclone ls dropbox:/
```

### Database connection errors
- Verify database host is accessible from container
- Check credentials in `.env` match database configuration
- Verify the database's network exists and is joined by `db-backup`:
  `knowledge_network` for Paperless, `media_network` for Invidious/Immich.

## 💾 Restore from Backup

### Decrypt Backup
```bash
gpg --decrypt --batch --passphrase "your-passphrase" \
  backup.sql.zst.gpg | zstd -d -o backup.sql
```

### Restore to Invidious
```bash
docker exec -i invidious-db psql -U kemal -d invidious < backup.sql
```

### Restore to Firefly
```bash
docker exec -i firefly-db psql -U firefly -d firefly < backup.sql
```

## 📊 Monitor Backups

### Check Local Backups
```bash
# List recent backups
ls -lt ./backups/invidious/ | head -5
ls -lt ./backups/firefly/ | head -5

# Check disk usage
du -sh ./backups/invidious/
du -sh ./backups/firefly/
```

### Check Dropbox Backups
```bash
docker exec db-backup rclone ls dropbox:/invidious_backups
docker exec db-backup rclone ls dropbox:/firefly_backups
```

### Discord Notifications
Backups send automatic notifications:
- ✅ **Success**: Includes timestamp, file size, Dropbox path
- ❌ **Failure**: Includes error details for troubleshooting
- ⚠️ **Partial Success**: Backup stored locally but Dropbox upload failed

## 🔐 Security Best Practices

```bash
# Add sensitive files to .gitignore
echo ".env" >> .gitignore
echo "backups/" >> .gitignore
echo "secrets/" >> .gitignore

# Secure backup directories
chmod 700 ./backups/
chmod 600 .env
```

**Important:**
- Use strong GPG passphrase (min 16 characters)
- Rotate Dropbox tokens regularly
- Never commit credentials to git
- Keep Discord webhook URL confidential

## 🔄 Adding More Databases

### 1. Add environment variables to `.env`:
```bash
NEWDB_DB_USER=username
NEWDB_DB_PASSWORD=your_database_password
```

### 2. Create backup directory:
```bash
mkdir -p ./backups/newdb
```

### 3. Register the database:
Add its volume, profiles, network, retention and schedule to
`backup-databases.conf`, add its destination to both `path.local` and `path.prod`,
and add its configuration case to `db-backup-script.sh`.

### 4. Recreate the selected profile:
```bash
./start-backup.sh local
```

## 📁 File Structure

```
backupServices/postgres/
├── docker-compose.yml        # Service definition
├── .env                      # Configuration & credentials
├── db-backup-script.sh      # Backup orchestration
├── setup-backup.sh          # Interactive setup helper
└── backups/                 # Local backup storage
  ├── invidious/           # Invidious backups (*.sql.zst.gpg)
  ├── firefly/             # Firefly backups (*.sql.zst.gpg)
  ├── paperless/           # Paperless backups (*.sql.zst.gpg)
  ├── immich/              # Immich backups (*.sql.zst.gpg)
  └── firefoxsync/         # Firefox Sync backups (*.sql.zst.gpg)
```

## 📝 Configuration Files

| File | Purpose |
|------|---------|
| `.env` | Environment variables & credentials |
| `docker-compose.yml` | Docker service definition |
| `backup-databases.conf` | Database profile registry |
| `path.local`, `path.prod` | Environment-specific Dropbox destinations |
| `start-backup.sh` | Generates and deploys a host-specific Compose override |
| `db-backup-script.sh` | Backup logic & encryption |
| `setup-backup.sh` | Interactive setup helper |
