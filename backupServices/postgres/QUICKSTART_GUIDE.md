# PostgreSQL Backup - Quickstart Guide

## Compose Profile Selection

Choose the compose file that matches your deployment target:

| Environment | Compose File | Current backup scope |
|-------------|--------------|----------------------|
| Default homelab | `docker-compose.yml` | Main postgres backup set |
| Remote | `docker-compose.remote.yml` | `firefly`, `firefoxsync` |
| Local | `docker-compose.local.yml` | `romm`, `invidious`, `immich`, `paperless` |

All profiles use the same per-service cron variables from `.env`:
`FIREFLY_CRON_SCHEDULE`, `ROMM_CRON_SCHEDULE`,
`IMMICH_CRON_SCHEDULE`, `INVIDIOUS_CRON_SCHEDULE`, `PAPERLESS_CRON_SCHEDULE`,
and `FIREFOXSYNC_CRON_SCHEDULE`, as applicable to the selected profile.

### Compose And Crontab Ordering

All profiles order source mounts, top-level volumes, and cron jobs by service
category, then name: Financial, Gaming, Knowledge, Media, and Security Services,
as applicable. Source-volume sections use `## <Category> Services` comments;
generated crontabs use matching `# <Category> Services` comments. The crontab
header `# Crontab for database backups` is written with `>`; category comments
and jobs are appended with `>>`.

Network references and declarations are sorted by network name. Disabled entries
retain their sorted positions. Shared secrets follow source
volumes, and `gpg-secrets` follows top-level source-volume declarations. These
ordering rules do not change configured cron execution times.

When adding a database-backed service, insert its mounts, volume declarations,
required networks, and cron job in their sorted positions in every profile that
deploys it. Add its case to `db-backup-script.sh`, update environment examples,
specs, and service documentation, and leave unrelated disabled entries unchanged.

Set your compose file once per terminal session:

```bash
export BACKUP_COMPOSE_FILE=docker-compose.local.yml
# Use docker-compose.yml or docker-compose.remote.yml in other environments
```

## 🚀 Setup (5 minutes)

### Step 1: Run Setup Script
```bash
# Run from the repository root
cd backupServices/postgres
bash setup-backup.sh
```

Provide when prompted:
- **Dropbox Auth Token**: Get from [Dropbox App Console](https://www.dropbox.com/developers/apps)
- **Discord Webhook URI**: Create in Discord Server Settings > Integrations > Webhooks
- **GPG Passphrase**: Choose a strong passphrase (min 16 chars recommended)

Every database backup requires a nonempty GPG passphrase. The
`/run/secrets/gpg-passphrase` file takes precedence over `GPG_PASSPHRASE`,
even if the file is empty. If the selected passphrase is empty, the backup
fails before creating or uploading a dump.

### Step 2: Start the Service
```bash
docker compose -f "$BACKUP_COMPOSE_FILE" up -d --build
```

The local `homelab/db-backup:local` image includes the backup script and all tools,
including `zstd`, on a digest-pinned PostgreSQL 18.6 Alpine base. No scripts are
bind-mounted from the host and no packages are installed during startup. This
allows Docker to restart it before an encrypted home directory is unlocked.
The build context allowlist in `.dockerignore` excludes credentials and unrelated
files. Compose reads `.env` only during creation/recreation; Docker uses the stored
container environment when restarting it.

To migrate an existing container or apply script/dependency changes:

```bash
docker compose -f "$BACKUP_COMPOSE_FILE" up -d --build --force-recreate db-backup
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

For the remote environment:
```bash
# Test Firefly backup
docker exec db-backup /usr/local/bin/backup-script.sh firefly

# Test Firefox Sync backup
docker exec db-backup /usr/local/bin/backup-script.sh firefoxsync
```

## 📅 Backup Schedule

### Effective Schedule (from `.env`)

| Database    | Cron Variable               | Example Value  | Retention |
|-------------|-----------------------------|----------------|-----------|
| Invidious   | `INVIDIOUS_CRON_SCHEDULE`   | `0 3 */2 * *`  | 30 days   |
| Firefly     | `FIREFLY_CRON_SCHEDULE`     | `5 3 * * *`    | 120 days  |
| Paperless   | `PAPERLESS_CRON_SCHEDULE`   | `10 3 * * *`   | 30 days   |
| Immich      | `IMMICH_CRON_SCHEDULE`      | `0 4 * * *`    | 30 days   |
| FirefoxSync | `FIREFOXSYNC_CRON_SCHEDULE` | `20 3 * * *`   | 30 days   |

### Profile Notes

- `docker-compose.yml` schedules all five databases using the shared `.env` cron vars.
- `docker-compose.local.yml` schedules `romm`, `paperless`, and `invidious`.
- Paperless runs in `knowledgeServices/paperless/` on `knowledge_network`. Both the
  default and Local backup profiles join that network to reach `paperless-db`;
  keep `media_network` for Invidious.
- `docker-compose.remote.yml` schedules `firefly` and `firefoxsync` using their
  respective `FIREFLY_CRON_SCHEDULE` and `FIREFOXSYNC_CRON_SCHEDULE` variables.

Automatic cleanup deletes local and remote backups older than 7 days.

## 🔧 Common Commands

```bash
# Start service
docker compose -f "$BACKUP_COMPOSE_FILE" up -d

# Stop service
docker compose -f "$BACKUP_COMPOSE_FILE" down

# Restart service
docker compose -f "$BACKUP_COMPOSE_FILE" restart

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
NEWDB_DB_HOST=hostname
NEWDB_DB_NAME=database
NEWDB_DB_USER=username
NEWDB_DB_PASSWORD=your_database_password
NEWDB_BACKUP_NAME=newdb
NEWDB_DROPBOX_BACKUP_PATH=/newdb_backups
NEWDB_CRON_SCHEDULE=0 4 * * *  # 4:00 AM
```

### 2. Create backup directory:
```bash
mkdir -p ./backups/newdb
```

### 3. Update `docker-compose.yml` command section:
Add the following line to create a new cron job:
```yaml
# Use > for the first cron entry in the command block so restarts rewrite the crontab cleanly.
echo '$${NEWDB_CRON_SCHEDULE} /usr/local/bin/backup-script.sh newdb' > /etc/crontabs/root
```

### 4. Restart service:
```bash
docker compose -f "$BACKUP_COMPOSE_FILE" restart
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
| `db-backup-script.sh` | Backup logic & encryption |
| `setup-backup.sh` | Interactive setup helper |
