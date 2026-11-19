## Requirements

### REQ-001: Database Backup
The system SHALL provide automated PostgreSQL database backups.

#### Scenario: Automated backup execution
- **WHEN** the scheduled backup time arrives
- **THEN** the backup system creates PostgreSQL dumps
- **AND** encrypts them using GPG

#### Scenario: Database passphrase is missing
- **GIVEN** a PostgreSQL backup has an empty or missing GPG passphrase
- **WHEN** the backup job runs
- **THEN** it SHALL fail before creating or uploading a database dump

### REQ-002: Filesystem Backup
The system SHALL provide automated backups of Docker volumes and filesystem data using a standardized filedata backup service.

#### Scenario: Volume backup
- **WHEN** the backup system runs
- **THEN** it backs up configured Docker volumes
- **AND** compresses and encrypts the backup files

#### Scenario: Filedata backup service location
- **WHEN** the filedata backup service is deployed
- **THEN** it MUST be located at `backupServices/filedata/`
- **AND** the service name MUST be `filedata-backup`
- **AND** the container name MUST be `filedata-backup`

#### Scenario: Filedata backup scripts
- **GIVEN** the filedata backup image is built from its service directory
- **WHEN** backup scripts are used for filedata backups
- **THEN** `filedata-backup-script.sh` SHALL be included in the image as
  `/usr/local/bin/backup-script.sh`
- **AND** `configure-rclone.sh` SHALL be included in the image
- **AND** the scripts SHALL NOT require host bind mounts at runtime
- **AND** the backup script SHALL support multiple volume types (pihole, npm, vaultwarden)

#### Scenario: Filedata backup documentation
- **WHEN** filedata backup service is deployed
- **THEN** it MUST include a `RESTORE_GUIDE.md` with restoration procedures
- **AND** it MUST include a `SERVICE_DOCUMENTATION.md` with operational details
- **AND** documentation MUST follow service documentation standards

#### Scenario: Cross-service backup references
- **WHEN** a service is backed up by the filedata backup service
- **THEN** the service's restore guide MUST reference `backupServices/filedata`
- **AND** the reference MUST use the service name `filedata-backup`
- **AND** references MUST be updated when backup service location or name changes

### REQ-003: Backup Encryption
The system SHALL encrypt all backups using GPG with AES256 cipher algorithm.

#### Scenario: Backup encryption
- **WHEN** a backup is created
- **THEN** the backup file is encrypted with GPG
- **AND** cannot be decrypted without the proper passphrase

### REQ-004: Multi-Cloud Support
The system SHALL support backup synchronization to multiple cloud storage providers.

#### Scenario: Dropbox backup
- **WHEN** backups are synchronized
- **THEN** encrypted backups are uploaded to Dropbox
- **AND** stored in the configured directory

#### Scenario: Google Drive backup
- **WHEN** backups are synchronized
- **THEN** encrypted backups are uploaded to Google Drive
- **AND** stored in the configured directory

#### Scenario: OneDrive backup
- **WHEN** backups are synchronized
- **THEN** encrypted backups are uploaded to OneDrive
- **AND** stored in the configured directory

### REQ-005: Retention Policies
The system SHALL implement retention policies for backup management.

#### Scenario: Old backup cleanup
- **WHEN** retention period expires
- **THEN** old backups are automatically deleted
- **AND** storage space is managed efficiently

### REQ-006: Backup Notifications
The system SHALL send backup status notifications through Discord.

#### Scenario: Success notification
- **WHEN** a backup completes successfully
- **THEN** a success notification is sent to Discord
- **AND** includes backup details

#### Scenario: Failure notification
- **WHEN** a backup fails
- **THEN** a failure notification is sent to Discord
- **AND** includes error details

### REQ-007: Scheduled Backups
The system SHALL schedule backups at regular intervals using cron jobs.

#### Scenario: Daily backup execution
- **WHEN** the scheduled backup time arrives
- **THEN** the backup system executes automatically
- **AND** performs the configured backup operations

### REQ-008: Database Specific Backups
The system SHALL provide specialized backup services for critical databases.

#### Scenario: PostgreSQL backup
- **WHEN** PostgreSQL backup runs
- **THEN** it uses pg_dump to create consistent backups
- **AND** backs up all databases and schemas

### REQ-009: Service-Specific Backups
The system SHALL provide backup capabilities for individual services.

#### Scenario: Vaultwarden backup
- **WHEN** Vaultwarden backup runs
- **THEN** it backs up password vault data
- **AND** encrypts the backup with GPG

#### Scenario: Homepage backup
- **WHEN** Homepage backup runs
- **THEN** it backs up configuration and user data
- **AND** ensures service continuity

### REQ-010: Backup Network Isolation
The system SHALL isolate backup services in a dedicated network.

#### Scenario: Backup service communication
- **WHEN** backup services communicate
- **THEN** all communication occurs within the backup network
- **AND** unauthorized access from other networks is prevented

### REQ-011: Filedata backups run on staggered per-service cron schedules
The filedata backup service SHALL schedule each service backup independently using per-service cron schedule environment variables, starting no earlier than 2:00 AM daily and staggered at minimum 5-minute intervals to avoid simultaneous I/O contention.

#### Scenario: Per-service schedule variables declared
- **WHEN** the `backupServices/filedata/docker-compose.yml` command block is inspected
- **THEN** each service (pihole, npm, vaultwarden) MUST reference its own schedule variable (`PIHOLE_CRON_SCHEDULE`, `NPM_CRON_SCHEDULE`, `VAULTWARDEN_CRON_SCHEDULE`)
- **AND** the first cron `echo` in each filedata command block SHALL rewrite `/etc/crontabs/root` with `>` so container starts remain idempotent
- **AND** the variables MUST NOT share a single `CRON_SCHEDULE` value

#### Scenario: Default filedata backup schedule staggering
- **WHEN** the filedata backup service is deployed with default schedule values
- **THEN** pihole backs up every 10 days at 2:00 AM (`0 2 */10 * *`)
- **AND** npm backs up every 7 days at 2:10 AM (`10 2 */7 * *`)
- **AND** vaultwarden backs up at 2:15 AM (`15 2 * * *`)

#### Scenario: Vaultwarden schedule remains independent
- **WHEN** the filedata backup service is deployed
- **THEN** vaultwarden backup schedule is controlled by `VAULTWARDEN_CRON_SCHEDULE` independently of the other service schedule variables

### REQ-012: Postgres database backups run on staggered cron schedules
The postgres backup service SHALL schedule database backups using per-service cron schedule environment variables, with each configured service having exactly one `*_CRON_SCHEDULE` variable shared across compose profiles.

#### Scenario: Compose files reference per-service cron variables
- **GIVEN** `backupServices/postgres/docker-compose.yml`, `docker-compose.remote.yml`, and `docker-compose.local.yml` are inspected
- **WHEN** reviewing the cron `echo` entries in the `db-backup` command blocks
- **THEN** each scheduled database SHALL reference a per-service variable named `{SERVICE}_CRON_SCHEDULE`
- **AND** the first cron `echo` in each postgres command block SHALL rewrite `/etc/crontabs/root` with `>` so container starts remain idempotent
- **AND** profile-specific variables such as `*_REMOTE_CRON_SCHEDULE` and `*_LOCAL_CRON_SCHEDULE` SHALL NOT be used

#### Scenario: Environment examples define one cron variable per postgres service
- **GIVEN** `backupServices/postgres/.env.acc.example` and `.env.prd.example` are inspected
- **WHEN** checking cron-related variable names
- **THEN** each postgres-backed service SHALL define exactly one cron variable: `INVIDIOUS_CRON_SCHEDULE`, `FIREFLY_CRON_SCHEDULE`, `PAPERLESS_CRON_SCHEDULE`, `AFFINE_CRON_SCHEDULE`, `IMMICH_CRON_SCHEDULE`, `FIREFOXSYNC_CRON_SCHEDULE`

### REQ-013: Service-Specific Backup Schedules
The backup system SHALL use per-service configurable cron schedules that reflect each service's data change frequency and acceptable backup intervals.

#### Scenario: Pi-hole backup schedule
- **WHEN** the filedata backup system is configured
- **THEN** Pi-hole backups MUST run every 10 days (`0 2 */10 * *`)
- **AND** Pi-hole backup retention MUST be set to 61 days

#### Scenario: NPM backup schedule
- **WHEN** the filedata backup system is configured
- **THEN** NPM (Nginx Proxy Manager) backups MUST run every 7 days (`0 2 */7 * *`)
- **AND** NPM backup retention MUST be set to 57 days

#### Scenario: Invidious backup schedule
- **WHEN** the PostgreSQL backup system is configured
- **THEN** Invidious database backups MUST run every 2 days (`0 3 */2 * *`)
- **AND** Invidious backup retention MUST be set to 30 days

#### Scenario: Unchanged services
- **WHEN** backup schedules are updated
- **THEN** Vaultwarden and Firefly backup schedules and retention MUST remain unchanged

### REQ-014: Every service SHALL be covered by backup before deployment is considered complete
When a service is newly added or standardized, it SHALL have backup integration configured as part of the standardization work. A service without backup coverage SHALL be considered incompletely standardized.

The backup mechanism is determined by the type of persistent data:

| Data type | Backup service | Configuration location |
|---|---|---|
| PostgreSQL database | `backupServices/postgres/` (`db-backup` service) | Add cron entry + case block to `db-backup-script.sh`; mount the postgres volume |
| Docker volume / filesystem data | `backupServices/filedata/` (`filedata-backup` service) | Register the volume via env vars in `.env` and mount in `docker-compose.yml` |

A service MAY use both mechanisms (e.g., has both a postgres DB and file storage).

#### Scenario: Service standardized without backup
- **WHEN** a service's docker-compose.yml is updated to follow homelab standards (network, volumes, etc.)
- **THEN** a backup task for that service SHALL also be present in the same change's task list
- **AND** the service's `SERVICE_DOCUMENTATION.md` SHALL explicitly state whether backup is configured or explicitly deferred with a rationale

#### Scenario: PostgreSQL-backed service backup integration
- **WHEN** a service uses a PostgreSQL database
- **THEN** the service's postgres volume SHALL be mounted into `db-backup` in `backupServices/postgres/docker-compose.yml`
- **AND** a cron entry SHALL be present in the `db-backup` command for that service
- **AND** a case block SHALL exist in `backupServices/postgres/db-backup-script.sh` for that service's database

#### Scenario: Filesystem/volume-backed service backup integration
- **WHEN** a service uses persistent Docker volumes (non-database storage)
- **THEN** those volumes SHALL be registered in `backupServices/filedata/` via mount declarations in `docker-compose.yml`
- **AND** the volume name and retention period SHALL be defined via environment variables in `backupServices/filedata/.env` (e.g., `{VOLUME_NAME}_DROPBOX_PATH`, `{VOLUME_NAME}_RETENTION_DAYS`)
- **AND** a cron entry SHALL be present in the `filedata-backup` container command for each registered volume
- **NOTE** `filedata-backup-script.sh` is fully generic and resolves configuration via env var indirection — no per-service block is required in the script itself

#### Scenario: Backup deferred with documented rationale
- **WHEN** backup integration is explicitly deferred (e.g., service not yet production-ready)
- **THEN** the deferral SHALL be documented in the service's `SERVICE_DOCUMENTATION.md` under the "Backup Coverage" section
- **AND** a tracking task SHALL be created in the relevant OpenSpec change or a follow-up change
- **AND** the deferral SHALL NOT be treated as a permanent state

### REQ-015: Legacy Immich backup scripts removed
The system SHALL NOT contain Duplicity- or MEGA-based backup scripts in the `mediaServices/immich/` directory. These scripts are superseded by the homelab standard backup infrastructure.

#### Scenario: Legacy files absent from the repository
- **WHEN** the repository is inspected
- **THEN** the following files SHALL NOT exist under `mediaServices/immich/`:
  - `configureDuplicityRclone.sh`
  - `dataBackup.sh`
  - `dataRestore.sh`
  - `scriptRCloneBackup.sh`

### REQ-016: Immich photo volumes included in filedata backup
The system SHALL include each of the three named Immich photo volumes (`immich_library`, `immich_profile`, `immich_upload`) in the `backupServices/filedata` backup service, each mounted independently as read-only. These volumes SHALL be backed up through the reusable `sync-crypt` file lane using `rclone crypt` over a MEGA-backed remote path, with latest-good-state stored under `current/`. The ML model cache is ephemeral and is not included.

| Volume | Mount path in backup container |
|---|---|
| `immich_library` | `/backup-sources/immich-library` |
| `immich_profile` | `/backup-sources/immich-profile` |
| `immich_upload` | `/backup-sources/immich-upload` |

#### Scenario: Photo volumes mounted read-only in backup container
- **GIVEN** the filedata backup service starts
- **WHEN** mounted source volumes are inspected
- **THEN** `immich_library`, `immich_profile`, and `immich_upload` SHALL each be mounted as read-only at their declared paths

#### Scenario: Local backup profile
- **GIVEN** Immich is deployed in the Local environment
- **WHEN** the Local filedata backup profile is started
- **THEN** all three Immich volumes SHALL be mounted read-only
- **AND** their scheduled sync-crypt jobs SHALL be enabled

#### Scenario: Scheduled sync-crypt runs for each photo volume
- **GIVEN** each Immich volume has a configured cron schedule
- **WHEN** its schedule fires
- **THEN** the backup script SHALL run sync-crypt mode for that volume into `<remote-path>/current/`
- **AND** replaced/deleted files SHALL be preserved under `<remote-path>/deleted-archive/YYYY-MM-DD/`

### REQ-017: Backup environment variables declared for Immich filedata volumes
The system SHALL define Immich filedata environment variables in `backupServices/filedata/.env` for each volume's mode, destination, schedule, and retention behavior. This SHALL include mode selection and 30-day deleted/replaced-file retention for sync-crypt operation.

#### Scenario: Backup service starts without missing variable errors
- **GIVEN** Immich-related mode and destination variables are present in `.env`
- **WHEN** `docker compose up -d` is run in `backupServices/filedata/`
- **THEN** all Immich-related variables SHALL resolve without configuration errors
- **AND** the filedata-backup container SHALL start successfully

#### Scenario: Immich deleted/replaced-file retention is 30 days
- **GIVEN** Immich sync-crypt retention is configured
- **WHEN** cleanup runs after backup
- **THEN** deleted-archive content older than 30 days SHALL be removed
- **AND** content within 30 days SHALL remain available for restore

### REQ-018: Immich PostgreSQL database backed up by standard postgres backup service
The system SHALL add the Immich database (`immich_postgresdata`) to the `backupServices/postgres` service so that the Immich PostgreSQL database is backed up by the same GPG-encrypted `pg_dump` pipeline used for Invidious, Firefly, and Paperless, with Dropbox as destination.

#### Scenario: Immich database volume mounted read-only in db-backup container
- **GIVEN** the `db-backup` container starts
- **WHEN** mounted volumes are inspected
- **THEN** `immich_postgresdata` SHALL be mounted at `/var/lib/postgresql/immich` as read-only

#### Scenario: Scheduled pg_dump runs for Immich database
- **GIVEN** the configured cron schedule for `immich` fires inside `db-backup`
- **WHEN** the backup script executes
- **THEN** `pg_dump` SHALL run against the Immich database
- **AND** the resulting dump SHALL be zstd-compressed, GPG-encrypted, and uploaded to Dropbox using naming `immich_{timestamp}.sql.zst.gpg`

#### Scenario: Immich dump or upload fails
- **GIVEN** an Immich backup is running
- **WHEN** the database dump or Dropbox upload fails
- **THEN** the backup command SHALL return a nonzero status
- **AND** an Immich backup without a GPG passphrase SHALL NOT be uploaded

#### Scenario: Local database backup
- **GIVEN** Immich is deployed in the Local environment
- **WHEN** the Local PostgreSQL backup profile is started
- **THEN** its Immich database volume and scheduled backup job SHALL be enabled

#### Scenario: db-backup container joins media_network
- **GIVEN** the `db-backup` container starts
- **WHEN** container network attachments are inspected
- **THEN** it SHALL be connected to `media_network` to reach `immich-db`

### REQ-019: Immich file-lane restore SHALL support containerized rclone execution
The Immich file-lane restore workflow SHALL use the existing `filedata-backup` container's configured remotes. Host-installed `rclone` SHALL NOT be required.

#### Scenario: File-lane restore runs without host rclone
- **GIVEN** the operator has Docker available but `rclone` is not installed on the host
- **WHEN** the operator follows `mediaServices/immich/RESTORE_GUIDE.md`
- **THEN** each of `immich_library`, `immich_profile`, and `immich_upload` SHALL be restorable using the `filedata-backup` container's rclone
- **AND** the restore flow SHALL read from the configured `mega-crypt` `current/` paths

### REQ-019: Immich upload data migrated from bind-mount to named volumes
The system SHALL provide a migration path for existing photo data from the legacy `${UPLOAD_LOCATION}` host path into the three named Docker volumes (`immich_library`, `immich_profile`, `immich_upload`) before the service is restarted with the new compose configuration.

#### Scenario: Existing photo data preserved after migration
- **WHEN** the migration script or manual copy completes
- **THEN** all files previously at `${UPLOAD_LOCATION}/library`, `${UPLOAD_LOCATION}/profile`, and `${UPLOAD_LOCATION}/upload` SHALL be present inside their respective named volumes
- **AND** the `immich` container SHALL start without reporting missing library data

### REQ-020: Remote Backup Profile — Scoped Volume Set
When deployed to a remote host, the `filedata-backup` service SHALL protect only the
four remote-profile source volumes plus `gpg-secrets` using
`backupServices/filedata/docker-compose.remote.yml`. The canonical
`docker-compose.yml` SHALL retain the full homelab backup set.

#### Scenario: Remote backup volumes are exactly the active service set
- **GIVEN** the Remote filedata backup profile is selected
- **WHEN** `backupServices/filedata/docker-compose.remote.yml` is inspected
- **THEN** the `volumes:` mount list of the `filedata-backup` service SHALL
  contain source volumes `freshrss_filedata`, `npm_filedata`, `pihole_filedata`,
  and `vaultwarden_filedata`, followed by `gpg-secrets`, in that order
- **AND** volumes for openwebui, affine, and immich SHALL NOT be
  present

#### Scenario: Remote backup .env is scoped to active services
- **WHEN** `backupServices/filedata/.env` is inspected on the `gcp` branch
- **THEN** cron schedule, Dropbox path, and retention variables SHALL exist for:
  pihole, npm, vaultwarden, and freshrss
- **AND** variables for openwebui, affine, and immich SHALL NOT be
  present

#### Scenario: freshrss_filedata volume is backed up remotely
- **WHEN** the `FRESHRSS_CRON_SCHEDULE` fires on the remote host
- **THEN** the `filedata-backup` container SHALL create a GPG-encrypted tar
  archive of `freshrss_filedata`
- **AND** upload it to Dropbox at `FRESHRSS_DROPBOX_PATH`

### REQ-021: Backup service environment example files
The backup services (filedata and postgres) SHALL use the environment-labelled
example file convention defined in `backup-env-file-standards`.

#### Scenario: filedata backup service env examples
- **GIVEN** `backupServices/filedata/` is inspected
- **WHEN** listing tracked files
- **THEN** `env.acc.example` SHALL be present with `/App_acc/` Dropbox paths
- **AND** `env.prd.example` SHALL be present with `/Apps/` Dropbox paths
- **AND** `.env.example` SHALL NOT be present (removed)
- **AND** `.env.backup` SHALL NOT be present (removed)

#### Scenario: filedata env examples cover all services
- **GIVEN** `backupServices/filedata/env.acc.example` and `env.prd.example` are inspected
- **WHEN** checking the set of variable names
- **THEN** both files SHALL declare variables for: pihole, npm, vaultwarden,
  openwebui, affine, freshrss, immich (library, profile, upload)
- **AND** neither file SHALL omit AFFiNE variables that were absent from the old `.env.example`

#### Scenario: postgres backup service env examples
- **GIVEN** `backupServices/postgres/` is inspected
- **WHEN** listing tracked files
- **THEN** `env.acc.example` SHALL be present with `/App_acc/` Dropbox paths
- **AND** `env.prd.example` SHALL be present with `/Apps/` Dropbox paths
- **AND** `.env.backup` SHALL NOT be present (removed)

#### Scenario: postgres env examples cover all services
- **GIVEN** `backupServices/postgres/env.acc.example` and `env.prd.example` are inspected
- **WHEN** checking the set of variable names
- **THEN** both files SHALL declare database credentials and backup config for:
  invidious, firefly, paperless, affine, immich, firefoxsync
- **AND** both files SHALL declare one cron schedule variable per service (`{SERVICE}_CRON_SCHEDULE`)
- **AND** both files SHALL declare shared credentials: `DROPBOX_AUTH_TOKEN`,
  `DROPBOX_REFRESH_TOKEN`, `GPG_PASSPHRASE`, `DISCORD_WEBHOOK_URL`, `TZ`

### REQ-022: Firefox Volume Registered in Filedata Backup
The `firefox_filedata` Docker volume SHALL be registered in `backupServices/filedata/` so that the Firefox browser profile is included in the standard GPG-encrypted, multi-cloud backup pipeline.

#### Scenario: Volume mount present in backup service
- **WHEN** `backupServices/filedata/docker-compose.yml` is inspected
- **THEN** the `filedata-backup` service's `volumes:` list SHALL contain `firefox_filedata:/backup-sources/firefox:ro`
- **AND** the top-level `volumes:` block SHALL declare `firefox_filedata` with `external: true`

#### Scenario: Cron entry present
- **WHEN** the `filedata-backup` container startup command is inspected
- **THEN** an `echo` line adding `${FIREFOX_CRON_SCHEDULE} /bin/bash /usr/local/bin/backup-script.sh firefox` to `/etc/crontabs/root` SHALL be present

#### Scenario: Per-service environment variables declared
- **WHEN** `backupServices/filedata/.env` is inspected
- **THEN** `FIREFOX_CRON_SCHEDULE`, `FIREFOX_DROPBOX_PATH`, and `FIREFOX_RETENTION_DAYS` SHALL be present
- **AND** `FIREFOX_CRON_SCHEDULE` SHALL NOT share its cron expression with any other service's schedule variable

#### Scenario: env.prd.example and env.acc.example updated
- **WHEN** `backupServices/filedata/env.prd.example` and `env.acc.example` are inspected
- **THEN** a `# Firefox` section SHALL be present in both files containing `FIREFOX_DROPBOX_PATH`, `FIREFOX_RETENTION_DAYS`, and `FIREFOX_CRON_SCHEDULE`
- **AND** `FIREFOX_CRON_SCHEDULE` SHALL be `10 4 * * *` (staggered at least 5 minutes after FreshRSS at `0 4 * * *`)

### REQ-023: Backup Profiles Preserve The Shared Ordering Contract
All default, Local, and Remote backup compose profiles SHALL follow the category,
service, volume-suffix, network, and crontab-comment ordering contract defined
in `backup-services` REQ-030 and the repository's backup Compose instructions.

#### Scenario: New service backup integration preserves ordering
- **GIVEN** a stateful service is being added to an applicable backup profile
- **WHEN** mounts, volume declarations, network entries, and cron jobs are added
- **THEN** each entry SHALL be inserted into its sorted position rather than
  appended after unrelated services or shared resources
- **AND** disabled entries SHALL retain their sorted positions and disabled state
- **AND** the profile SHALL retain its deployment-specific backup coverage

### REQ-024: Filedata Profiles Use Environment-Configured Backup Modes
Filedata backup profiles SHALL follow `backup-services` REQ-031 by loading modes
from `env_file: .env` without startup exports. The script SHALL default unset or
empty modes to `archive`; sync-crypt volumes SHALL have explicit mode settings.

#### Scenario: Compose startup does not override mode configuration
- **GIVEN** the filedata container receives per-volume modes from its environment
- **WHEN** a backup profile's startup command is inspected
- **THEN** the command SHALL NOT export `{SERVICE}_BACKUP_MODE` defaults
- **AND** Immich and Paperless sync-crypt mode settings SHALL be documented as
  explicit environment configuration
