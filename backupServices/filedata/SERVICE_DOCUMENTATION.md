# Filedata Backup Service - Service Documentation

## Overview

The filedata backup service provides automated backups of Docker volumes for the homelab infrastructure. It supports two per-service modes:

- `archive`: tar + zstd + GPG + Dropbox upload (legacy/default mode)
- `sync-crypt`: `rclone sync` to a configured crypt remote, with optional dated retention for replaced/deleted files

Immich and RomM filedata use `sync-crypt` mode, while most other services remain on `archive` mode.

**Key Features:**
- Automated daily backups via cron scheduling
- Per-service mode selection via environment variables
- GPG AES256 encryption for archive-mode artifacts
- rclone crypt encryption for sync-crypt remotes
- Multi-cloud support (Dropbox, MEGA, Google Drive, and Filen)
- Configurable retention policies
- Discord notifications (optional)
- Generic volume support (easily extensible)

## Architecture

### Container Details

**Service Name:** `filedata-backup`  
**Container Name:** `filedata-backup`  
**Image:** `homelab/filedata-backup:local` (built from digest-pinned Alpine 3.24.3)
**Network Mode:** `bridge` (for rclone cloud uploads)

### System Architecture

```
┌─────────────────────────────────────────────────────────────┐
│               filedata-backup Container                      │
│     (custom Alpine image with backup scripts and tools)      │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Mounted Volumes (Read-Only):                               │
│  ├─ pihole_filedata → /backup-sources/pihole:ro           │
│  ├─ npm_filedata → /backup-sources/npm:ro                  │
│  ├─ vaultwarden_filedata → /backup-sources/vaultwarden:ro │
│  ├─ jackett_filedata → /backup-sources/jackett:ro         │
│  ├─ radarr_filedata → /backup-sources/radarr:ro            │
│  └─ sonarr_filedata → /backup-sources/sonarr:ro            │
│  ├─ transmission_filedata → /backup-sources/transmission:ro│
│                                                              │
│  Cron Jobs:                                                  │
│  ├─ Configured schedule: /backup-script.sh pihole          │
│  ├─ Configured schedule: /backup-script.sh npm             │
│  ├─ Configured schedule: /backup-script.sh vaultwarden     │
│  ├─ Configured schedule: /backup-script.sh radarr          │
│  └─ Configured schedule: /backup-script.sh sonarr          │
│                                                              │
│  Backup Process (per volume, mode dependent):               │
│  archive:                                                   │
│   1. tar | zstd -6 -T1 → compress volume directory         │
│   2. GPG symmetric encryption (AES256)                     │
│   3. Upload encrypted artifact to Dropbox                  │
│   4. Prune local/remote retention                          │
│  sync-crypt:                                               │
│   1. rclone sync source -> <remote>/current/              │
│   2. Move replaced/deleted files to dated archive path     │
│   3. Prune dated archive paths older than retention        │
│                                                              │
└─────────────────────────────────────────────────────────────┘
         ↓                                    ↓
    Bridge Network                Remote Storage Providers
  (for rclone transfers)            (mode-specific destination)
                                   ├─ dropbox:<path> (archive)
                                   ├─ mega-crypt:<path> (sync-crypt)
                                   ├─ gdrive-crypt:<path> (sync-crypt)
                                   └─ filen-crypt:<path> (sync-crypt)
```

### Volume Mounts

| Volume | Mount Point | Mode | Purpose |
|--------|-------------|------|---------|
| `omniroute_filedata` | `/backup-sources/omniroute` | `:ro` | OmniRoute database, settings, and provider credentials |
| `pihole_filedata` | `/backup-sources/pihole` | `:ro` | Pi-hole data source |
| `npm_filedata` | `/backup-sources/npm` | `:ro` | NPM data source |
| `vaultwarden_filedata` | `/backup-sources/vaultwarden` | `:ro` | Vaultwarden data source |
| `radicale_filedata` | `/backup-sources/radicale` | `:ro` | Radicale data source |
| `jackett_filedata` | `/backup-sources/jackett` | `:ro` | Jackett config source |
| `radarr_filedata` | `/backup-sources/radarr` | `:ro` | Radarr config source |
| `sonarr_filedata` | `/backup-sources/sonarr` | `:ro` | Sonarr config source |
| `transmission_filedata` | `/backup-sources/transmission` | `:ro` | Transmission config source |
| `romm_filedata` | `/backup-sources/romm` | `:ro` | RomM library and assets (Local profile) |
| `gpg-secrets` | `/run/secrets` | `:ro` | GPG passphrase |

**Note:** All source volumes are mounted read-only (`:ro`) for safety.
The backup and rclone configuration scripts are included in the image, not bind-mounted.

**Volume Naming Convention:**
All services now use standardized `filedata` volume naming (e.g., `pihole_filedata`, `npm_filedata`) following homelab conventions. This replaces legacy service-specific names like `piholedata` or `npmdata`.

### Network Configuration

**Network Mode:** `bridge`

The service uses bridge networking to allow rclone transfers to configured remotes (for example Dropbox archive uploads, MEGA and Google Drive crypt mirrors, and Filen).

The rclone configuration is generated before cron starts. Archive jobs validate the `dropbox:`
remote before uploading, while sync-crypt jobs validate the configured crypt remote. After changing credentials or remote settings, recreate the container so
`configure-rclone.sh` runs again:

```bash
HOST_PROFILE=local # Change to default or prod as appropriate.
./start-backup.sh "$HOST_PROFILE"
```

### Dependencies

**Runtime Dependencies (installed when building the image):**
- `rclone` - Cloud storage synchronization
- `curl` - Discord webhook notifications
- `bash` - Script execution
- `findutils` - File cleanup utilities
- `gnupg` - GPG encryption
- `tar` - Archive creation
- `zstd` - Compression

**External Service Dependencies:**
- Dropbox API (archive mode and db lane compatibility)
- MEGA, Google Drive, and Filen APIs via rclone backends (sync-crypt mode)
- Discord webhook API (optional, for notifications)

## Configuration

### Compose Deployment Profiles

`docker-compose.yml` is the single base Compose file. It deliberately fails if
started directly; use `start-backup.sh` to generate host-specific mounts and cron
jobs before Compose starts the container.

`backup-volumes.conf` is the host-selection registry. Each `|`-separated entry
gives the backup name, Docker volume name, and comma-separated host profiles.
Every volume includes `default`; `local` and `prod` add host-specific subsets.
Backup names identify the source path (`/backup-sources/<name>`), backup-script
argument, and schedule variable (`<NAME>_CRON_SCHEDULE`, uppercasing and
replacing hyphens with underscores).

The `default` profile selects all registered volumes, while `local` and `prod`
select the volumes listed for those hosts. Host selection is independent of the
acceptance or production `.env` settings, which configure schedules, modes, and
destinations. A selected volume must have a schedule configured in `.env`.

### Unified Startup

From this directory, select the host profile explicitly. Use `default` when the
host should back up every registered volume:

```bash
./start-backup.sh default
./start-backup.sh local
./start-backup.sh prod
```

The `prod` name matches the GitHub environment name, but the profile is selected
explicitly; GitHub environment selection does not automatically select it. The
PostgreSQL backup service continues to use its own Compose files.

The script requires Docker Compose with `up --wait` support. It lists Docker
volumes, warns for each missing expected volume, and generates a temporary Compose
override with read-only mounts and jobs for the volumes present. It fails if Docker
cannot be queried, no selected volumes exist, or a selected schedule is unset.
The container validates that each schedule has five fields, and Compose waits for
the cron process to become healthy. Backup output goes to
`/var/log/cron_<backup-name>.log` inside the container.

Re-run the script after adding a volume or changing the host configuration; it
rebuilds and recreates the backup container. A volume created later is not picked
up automatically. Review missing-volume warnings and verify jobs and logs after
startup; a warning means that volume is not being backed up. The generated
override is removed on exit, while Docker retains the created container for
normal restart. For example:

```bash
docker logs filedata-backup
docker exec filedata-backup crontab -l
```

The host profiles select these volumes:

| Profile | Scope |
|---------|-------|
| Default | Every registered volume |
| Prod | `freshrss`, `npm`, `pihole`, `vaultwarden` |
| Local | `hermes`, `n8n`, `omniroute`, `openwebui`, `romm`, `paperless`, `radicale`, `immich`, `npm` |

OmniRoute's `omniroute_filedata` volume contains provider credentials and is
included in the default and Local profiles. Its archive backups use GPG
encryption; the GPG passphrase and `.env` credentials remain outside the
tracked environment examples.

Jellyfin configuration backups are enabled only in the default profile.
Local and Prod do not select its volume or schedule its backup job.

### Compose And Crontab Ordering

Paperless belongs to Knowledge Services. Its volume mounts, declarations, and cron
jobs are grouped there in the default and Local profiles. The move to
`knowledgeServices/paperless/` does not change `paperless_filedata`, the backup
schedule, or the `gdrive-crypt:paperless/current/` mirror destination.

The registry is grouped by service category and service name. The startup script
generates the source mounts, volume declarations, and cron jobs for only the
selected volumes that exist on the host. Shared secrets remain in the base
Compose file.

The generated Compose override keeps mount and job ordering consistent. Its
crontab starts with `# Crontab for filedata backups`, then appends category
comments and jobs. This ordering does not change the execution times supplied
by per-volume cron variables.

Example startup commands:

```bash
./start-backup.sh default
./start-backup.sh prod
./start-backup.sh local
```

### Image Builds And Reboot Safety

All profiles build the local image from `Dockerfile`. Scripts and tools are included
in the image so Docker can restart the container before an encrypted home directory
is unlocked, without downloading packages. Only named data and secrets volumes
are mounted at runtime. `.dockerignore` allows only the Dockerfile and required
scripts into the build context; credentials and other local files are excluded.
Compose still needs `.env` when creating or recreating a container, but Docker
does not reread it when restarting an existing container after a reboot.

Run from this directory to migrate an existing deployment or apply script changes:

```bash
./start-backup.sh local
docker inspect --format '{{.State.Status}} {{.HostConfig.RestartPolicy.Name}}' filedata-backup
docker inspect --format '{{range .Mounts}}{{println .Type .Destination}}{{end}}' filedata-backup
docker exec filedata-backup pidof crond
```

Use `default` or `prod` for those hosts. Rebuild and recreate after changing the
script or its dependencies; `docker restart` alone does not pick up image changes.
Leave the container running before reboot:
`unless-stopped` intentionally preserves an explicit stop.

### Setting up your environment:

**For a host using production backup destinations:**
```bash
cp env.prd.example .env
# Edit .env with your secrets
# Choose the host profile in backup-volumes.conf
./start-backup.sh prod
```

**For Local:**
```bash
cp env.acc.example .env
# Edit .env with your secrets
./start-backup.sh local
```

### Environment Variables

Configuration is managed via `.env` file in `backupServices/filedata/`.

`env_file: .env` supplies backup modes directly to the container and its cron
jobs; the Compose startup command does not export mode defaults. The script
uses `archive` when `{SERVICE}_BACKUP_MODE` is unset or empty. Set
`IMMICH_LIBRARY_BACKUP_MODE`, `IMMICH_PROFILE_BACKUP_MODE`,
`IMMICH_UPLOAD_BACKUP_MODE`, `PAPERLESS_BACKUP_MODE`, and the Local profile's
`ROMM_BACKUP_MODE` explicitly to
`sync-crypt` wherever those volumes use encrypted synchronization. The tracked
environment examples include these settings. Hyphenated job names use
uppercase underscore environment keys, such as `immich-library` mapping to
`IMMICH_LIBRARY_BACKUP_MODE`.

Before any archive or sync-crypt backup, the script checks that the source
directory exists and is an actual mount point. If either check fails, the job
stops before creating an archive or modifying a remote and sends a Discord
failure notification when configured. This applies to scheduled and manual
backups in all profiles. Rebuild and recreate the backup container to apply
the updated script.

The mount check does not verify the volume's identity or contents. An existing
but empty volume can still cause sync-crypt to remove remote files, especially
when retention is zero. Verify the source volume and its contents before
enabling a sync job or replacing a volume.

RomM filedata is enabled in the Local profile only and uses the Filen backend
wrapped by rclone crypt at `filen-crypt:/Romm`.
Before the RomM `sync-crypt` job runs, the script verifies that both `library/`
and `assets/` exist and contain at least one regular file. This prevents an
empty or partially initialized RomM volume from mirroring deletions to Filen.

**Required Variables:**

```bash
# Dropbox Authentication
DROPBOX_AUTH_TOKEN=<token>     # Dropbox access token
DROPBOX_REFRESH_TOKEN=<token>  # Dropbox refresh token

# GPG Encryption (alternative to secrets volume)
GPG_PASSPHRASE=<passphrase>    # Encryption passphrase

# Google Drive OAuth2 (required for Google Drive sync-crypt mode)
GOOGLE_DRIVE_ACCESS_TOKEN=<access-token>
GOOGLE_DRIVE_REFRESH_TOKEN=<refresh-token>
# Set both if the tokens were issued by your own OAuth client
GOOGLE_DRIVE_CLIENT_ID=<client-id>
GOOGLE_DRIVE_CLIENT_SECRET=<client-secret>

# Shared rclone crypt credentials (required for crypt sync-crypt remotes)
MEGA_USER=<email>
MEGA_PASS=<password>
RCLONE_CRYPT_PASSWORD=<primary-passphrase>
RCLONE_CRYPT_PASSWORD2=<secondary-passphrase-optional>

# Filen credentials (Local RomM backup only)
FILEN_EMAIL=<email>
FILEN_PASSWORD=<password>
FILEN_API_KEY=<key-from-filen-export-api-key>

# Volume-Specific Configuration
<SERVICE>_BACKUP_MODE=archive|sync-crypt
<SERVICE>_CRON_SCHEDULE=<cron expression>
<SERVICE>_RETENTION_DAYS=<days>
<SERVICE>_DROPBOX_PATH=<dropbox path>            # archive mode (no rclone crypt)
<SERVICE>_SYNC_CRYPT_REMOTE=<configured crypt remote>  # sync-crypt mode
```

Radarr and Sonarr use archive mode with two-day retention. The default and Local profiles schedule Radarr at 04:20 and Sonarr at 04:25; their Dropbox destinations are `/Apps/radarr` and `/Apps/sonarr` in production and `/App_acc/radarr` and `/App_acc/sonarr` in acceptance. Their restore scripts default to the acceptance paths; set `DROPBOX_PATH` to the production path when restoring production archives. They are not registered in the Prod profile.

Jackett and Transmission use encrypted archive mode with seven-day retention in
the default and Local profiles. Their jobs run at 04:30 and 04:35
respectively, using `/Apps/<service>` in production and `/App_acc/<service>` in
acceptance. Their restore scripts default to acceptance paths; set
`DROPBOX_PATH` to the production path when restoring production archives. They
are not registered in the Prod profile.

At container startup, `configure-rclone.sh` creates one rclone configuration containing every
provider whose credentials are present. Cron jobs only use that configuration and never rewrite it.
Set `{SERVICE}_RETENTION_DAYS=0` for a pure mirror under `current/`; deletions then propagate
without a `deleted-archive` copy. Positive retention values preserve the existing dated archive
behavior.

Example Google Drive and Immich sync-crypt values:

```bash
IMMICH_UPLOAD_BACKUP_MODE=sync-crypt
IMMICH_UPLOAD_SYNC_CRYPT_REMOTE=mega-crypt:/Apps/immich-upload
IMMICH_UPLOAD_RETENTION_DAYS=30
IMMICH_UPLOAD_CRON_SCHEDULE=30 3 * * *

PAPERLESS_BACKUP_MODE=sync-crypt
PAPERLESS_SYNC_CRYPT_REMOTE=gdrive-crypt:paperless
PAPERLESS_RETENTION_DAYS=0
```

Filen's rclone backend requires rclone 1.73 or newer. Generate `FILEN_API_KEY`
with `filen export-api-key`; rclone configuration generation obscures the Filen
password and API key in its owner-readable configuration. The Filen backend
provides end-to-end encryption, and `filen-crypt` adds the shared rclone crypt
layer used by the standard filedata sync workflow. If the Filen account password
changes, export a new API key and update all three `FILEN_*` values.

The Local RomM lane is configured as:

```bash
ROMM_BACKUP_MODE=sync-crypt
ROMM_SYNC_CRYPT_REMOTE=filen-crypt:/Romm
ROMM_RETENTION_DAYS=30
ROMM_CRON_SCHEDULE=0 5 * * *
```

### RomM Filen setup

The RomM filedata lane is enabled on the Local profile. Generate a Filen API key with
`filen export-api-key` using the Filen CLI, then set `FILEN_EMAIL`,
`FILEN_PASSWORD`, and `FILEN_API_KEY` in `backupServices/filedata/.env`. Set
`RCLONE_CRYPT_PASSWORD` and the `ROMM_*` settings from the matching environment
example, then start/recreate the Local backup container:

```bash
cd backupServices/filedata
./start-backup.sh local
```

**Optional Variables:**

```bash
# Discord Notifications
DISCORD_WEBHOOK_URI=<webhook>  # Discord webhook URL for notifications
```

If a Google Drive sync fails with `unauthorized_client` while refreshing its token,
confirm the access and refresh tokens are valid and were issued for the configured
OAuth client. If you use your own Google OAuth client, set both
`GOOGLE_DRIVE_CLIENT_ID` and `GOOGLE_DRIVE_CLIENT_SECRET` in `.env`, then recreate
the `filedata-backup` container so the rclone configuration is regenerated. Do not
share token or client-secret values in logs or support requests.

### Secrets Management

GPG passphrase can be stored in two ways:

1. **Docker Volume (Recommended):**
   ```bash
   # Create secrets file
   echo "your-passphrase" > secrets/gpg-passphrase
   chmod 600 secrets/gpg-passphrase
   
   # Create Docker volume
   docker volume create gpg-secrets
   
   # Copy to volume
   docker run --rm -v $(pwd)/secrets:/source -v gpg-secrets:/dest alpine cp /source/gpg-passphrase /dest/
   ```

2. **Environment Variable:**
   ```bash
   # In .env file
   GPG_PASSPHRASE=your-passphrase
   ```

**Security Note:** Docker volume method is preferred as it keeps secrets out of environment variables.

### Cron Schedule Format

The `CRON_SCHEDULE` variable uses standard cron syntax:

```
* * * * *
│ │ │ │ │
│ │ │ │ └─ Day of week (0-7, 0 and 7 = Sunday)
│ │ │ └─── Month (1-12)
│ │ └───── Day of month (1-31)
│ └─────── Hour (0-23)
└───────── Minute (0-59)
```

**Examples:**
- `0 2 * * *` - Daily at 2:00 AM
- `0 */6 * * *` - Every 6 hours
- `0 0 * * 0` - Weekly on Sunday at midnight
- `30 3 * * 1-5` - Weekdays at 3:30 AM

## Operational Procedures

### Initial Setup

**Step 1:** Create the environment file for this host
```bash
cd /path/to/homelab/backupServices/filedata
cp env.acc.example .env
```

For production backup destinations, use `cp env.prd.example .env` instead.
Set the required credentials, destinations, modes, and schedule variables for
the volumes selected by the host profile.

**Step 2:** Provision the GPG passphrase in the `gpg-secrets` volume as described
in [Secrets Management](#secrets-management).

**Step 3:** Start the service
```bash
HOST_PROFILE=local # Change to default or prod as appropriate.
./start-backup.sh "$HOST_PROFILE"
```

**Step 4:** Verify service is running
```bash
docker ps | grep filedata-backup
docker logs filedata-backup
```

### Starting and Stopping

**Start service:**
```bash
cd /path/to/homelab/backupServices/filedata
HOST_PROFILE=local # Change to default or prod as appropriate.
./start-backup.sh "$HOST_PROFILE"
```

**Stop service:**
```bash
docker stop filedata-backup
```

**Restart service:**
```bash
docker restart filedata-backup
```

**View logs:**
```bash
# Real-time logs
docker logs -f filedata-backup

# Last 50 lines
docker logs --tail 50 filedata-backup

# Logs from last 24 hours
docker logs --since 24h filedata-backup
```

If a manual archive backup reports `configure_rclone_dropbox: command not found`, recreate the
container using the command above. This indicates that the container is running an older mounted
backup script/configuration pair.

### Manual Backup

Run an immediate backup for any volume:

```bash
# Pi-hole backup
docker exec filedata-backup /bin/bash /usr/local/bin/filedata-backup-script.sh pihole

# NPM backup
docker exec filedata-backup /bin/bash /usr/local/bin/filedata-backup-script.sh npm

# Check logs to monitor progress
docker logs -f filedata-backup
```

### Listing Backups

**Local backups:**
```bash
cd /path/to/homelab/backupServices/filedata
ls -lht backups/pihole/ | head -10
ls -lht backups/npm/ | head -10
```

**Remote backups (Dropbox):**
```bash
cd /path/to/homelab/backupServices/filedata
source .env

# Use rclone via container
docker run --rm -e DROPBOX_AUTH_TOKEN -e DROPBOX_REFRESH_TOKEN -e PIHOLE_DROPBOX_PATH alpine sh -c "\
  apk add --no-cache rclone && \
  mkdir -p /root/.config/rclone && \
  cat > /root/.config/rclone/rclone.conf <<EOF
[dropbox]
type = dropbox
token = {\"access_token\":\"\${DROPBOX_AUTH_TOKEN}\",\"refresh_token\":\"\${DROPBOX_REFRESH_TOKEN}\"}
EOF
  rclone ls dropbox:\${PIHOLE_DROPBOX_PATH}/"
```

### Updating Configuration

**Modify backup schedule or retention:**
```bash
cd /path/to/homelab/backupServices/filedata
nano .env
# Edit CRON_SCHEDULE or RETENTION_DAYS variables
HOST_PROFILE=local # Change to default or prod as appropriate.
./start-backup.sh "$HOST_PROFILE"
```

**Add new volume to backup:**

1. In every profile that deploys the service, insert its read-only mount and
top-level external volume declaration into the correct category and service-name
position. Keep shared resources last and unrelated disabled entries commented:
```yaml
volumes:
  ## Knowledge Services
  - newservice_filedata:/backup-sources/newservice:ro
```

Declare `newservice_filedata` with `external: true` and
`name: newservice_filedata` under the top-level `volumes:` block as well.

2. Insert its job under the matching category in the command, using its own
schedule variable and the mounted script path. Only the crontab header uses `>`;
category comments and all jobs use `>>`:
```bash
echo '${NEWSERVICE_CRON_SCHEDULE} /bin/bash /usr/local/bin/backup-script.sh newservice >> /var/log/cron_newservice.log 2>&1' >> /etc/crontabs/root &&
```

3. Add configuration to both tracked environment examples and configure it
locally in `.env`. Use an appropriately staggered schedule. Update the backup
specs and service documentation in the same change:
```bash
NEWSERVICE_BACKUP_MODE=archive
NEWSERVICE_CRON_SCHEDULE=0 5 * * *
NEWSERVICE_DROPBOX_PATH=/Apps/newservice
NEWSERVICE_RETENTION_DAYS=7
```

For `sync-crypt`, explicitly set the mode and `NEWSERVICE_SYNC_CRYPT_REMOTE`
instead of relying on a Compose default or archive destination.

4. Add the new volume to `backup-volumes.conf` and configure its schedule,
   mode, and destination in both environment examples. Run the startup script
   for each host profile that selects it:
```bash
HOST_PROFILE=local # Change to default or prod as appropriate.
./start-backup.sh "$HOST_PROFILE"
```

The startup script regenerates mounts and cron jobs from the registry; no
per-profile Compose edits are needed.

## Backup Schedule and Retention

### Current Backup Schedule

| Volume | Schedule | Retention | Destination |
|--------|----------|-----------|-------------|
| Pi-hole | Per `CRON_SCHEDULE` | `PIHOLE_RETENTION_DAYS` | `$PIHOLE_DROPBOX_PATH` |
| NPM | Per `CRON_SCHEDULE` | `NPM_RETENTION_DAYS` | `$NPM_DROPBOX_PATH` |
| RomM (Local) | `0 5 * * *` | `ROMM_RETENTION_DAYS` | `filen-crypt:/Romm` |

Default schedule: `0 2 * * *` (2:00 AM daily)  
Default retention: 7 days

### Retention Policy

The backup script automatically deletes:
- **Local backups** older than retention period
- **Remote backups** (Dropbox) older than retention period

This happens after each successful backup run.

### Disk Space Management

**Estimate local storage requirements:**
```
Local Storage = (Volume Size × 1.1) × Retention Days
```

Example: 100MB volume with 7-day retention ≈ 770MB local storage

**Check current usage:**
```bash
du -sh /path/to/homelab/backupServices/filedata/backups/*
df -h /path/to/homelab/backupServices/filedata
```

## Troubleshooting

### Service Won't Start

**Check logs:**
```bash
docker logs filedata-backup
```

**Common issues:**
- Missing `.env` file → Copy the appropriate environment example and configure it
- Invalid cron schedule → Verify each selected volume's `<NAME>_CRON_SCHEDULE`
- Volume mount errors → Check `backup-volumes.conf` and host volume availability

### Backups Not Running

**Verify cron jobs are scheduled:**
```bash
docker exec filedata-backup cat /etc/crontabs/root
```

**Check cron daemon:**
```bash
docker exec filedata-backup ps aux | grep crond
```

**Check container time/timezone:**
```bash
docker exec filedata-backup date
# Should match your TZ setting
```

**Manual test:**
```bash
docker exec filedata-backup /bin/bash /usr/local/bin/filedata-backup-script.sh pihole
```

### GPG Encryption Errors

**Verify GPG passphrase:**
```bash
# Check secrets volume
docker exec filedata-backup ls -l /run/secrets/
docker exec filedata-backup cat /run/secrets/gpg-passphrase

# Check GPG is working
docker exec filedata-backup gpg --version

# Test encryption/decryption
echo "test" | docker exec -i filedata-backup sh -c "\
  apk add --no-cache gnupg && \
  gpg --symmetric --cipher-algo AES256 --batch --yes --passphrase \$(cat /run/secrets/gpg-passphrase) | \
  gpg --decrypt --batch --passphrase \$(cat /run/secrets/gpg-passphrase)"
```

### Dropbox Upload Failures

**Check rclone configuration:**
```bash
docker exec filedata-backup cat /root/.config/rclone/rclone.conf
```

**Test Dropbox connection:**
```bash
docker exec filedata-backup rclone listremotes
docker exec filedata-backup rclone lsd dropbox:
```

**Common issues:**
- Expired tokens → Refresh tokens in .env
- Network connectivity → Check container network mode
- Invalid path → Verify DROPBOX_PATH variables

### Cron Logs Not Showing

**Check cron log file:**
```bash
docker logs filedata-backup | grep CRON
docker exec filedata-backup tail -f /var/log/cron.log
docker exec filedata-backup cat /var/log/cron_pihole.log
docker exec filedata-backup cat /var/log/cron_npm.log
```

### Out of Disk Space

**Clean old local backups manually:**
```bash
cd /path/to/homelab/backupServices/filedata

# Remove backups older than 7 days
find backups/*/backup_*.tar.zst.gpg -mtime +7 -delete

# Or reduce retention in .env
nano .env  # Set RETENTION_DAYS to lower value
HOST_PROFILE=local # Change to default or prod as appropriate.
./start-backup.sh "$HOST_PROFILE"
```

### Discord Notifications Not Sending

**Verify webhook URL:**
```bash
test -s .env && echo "Environment file exists; check webhook configuration privately."
```

**Test webhook:**
```bash
docker exec filedata-backup sh -c "\
  curl -X POST \$DISCORD_WEBHOOK_URI \
  -H 'Content-Type: application/json' \
  -d '{\"content\": \"Test notification from filedata-backup\"}'"
```

## GPG Encryption Details

### Encryption Method

- **Algorithm:** AES256 (symmetric)
- **Method:** GPG symmetric encryption
- **Passphrase:** Stored in Docker volume or environment variable

### Security Considerations

**Strengths:**
- Industry-standard AES256 encryption
- Encrypted backups safe for cloud storage
- Passphrase never logged or transmitted

**Weaknesses:**
- Symmetric key (same passphrase for encryption/decryption)
- If passphrase lost, backups are unrecoverable
- Passphrase stored in plaintext on host system

**Best Practices:**
- Use a strong passphrase (16+ characters)
- Store passphrase securely (password manager recommended)
- Limit access to .env file and secrets directory
- Regular passphrase rotation not recommended (breaks old backups)

### Encryption Process

1. Volume data is archived with `tar` and compressed with `zstd -6 -T1`
2. Archive is encrypted with GPG AES256
3. Unencrypted archive is immediately deleted
4. Only encrypted file (`.tar.zst.gpg`) is stored and uploaded

### Decryption Process

Decryption requires the original GPG passphrase:

```bash
gpg --batch --yes --passphrase "your-passphrase" -d backup.tar.zst.gpg | zstd -dc | tar -xf -
```

## Resource Requirements

### Container Resources

- **CPU:** Minimal idle, peaks during tar compression
- **Memory:** ~50MB idle, ~200MB during backup
- **Disk:** Size of volume + compression overhead (~110% of volume size)
- **Network:** Bandwidth for Dropbox uploads (backup file size)

### Performance Considerations

**Backup Duration:**
- Small volumes (< 100MB): < 1 minute
- Medium volumes (100MB - 1GB): 1-5 minutes
- Large volumes (> 1GB): 5-30+ minutes

**Factors affecting duration:**
- Volume size
- Number of files
- Compression ratio
- Dropbox upload speed

## Security Notes

### Access Control

- Container requires `docker exec` for shell access
- No SSH or remote access configured
- Minimal installed packages (attack surface minimization)

### Data Protection

- Source volumes mounted read-only (prevents accidental modification)
- Backups encrypted before cloud upload
- Secrets stored in Docker volume (not in git)
- .env file excluded from version control

### Network Isolation

- Container uses bridge network for rclone uploads only
- No unnecessary network services running
- No open ports exposed

## Additional Information

**Service Directory:** `backupServices/filedata/`
**Backup Storage:** `backupServices/filedata/backups/<volume>/`  
**Scripts:**
- `filedata-backup-script.sh` - Main backup script

**Related Documentation:**
- [NPM Restore Guide](../../securityServices/npm/RESTORE_GUIDE.md) - NPM-specific restore procedures
- [Pi-hole Restore Guide](../../securityServices/pihole/RESTORE_GUIDE.md) - Pi-hole restore procedures
- [Vaultwarden Restore Guide](../../securityServices/vaultwarden/RESTORE_GUIDE.md) - Vaultwarden restore procedures

For restoration procedures, refer to each service's own RESTORE_GUIDE.md.
