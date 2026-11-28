## Purpose

Define service registration, deployment-profile, migration, and ordering constraints for the standard backup services. Common encryption, scheduling, retention, destination, and notification behavior is specified in `backup-services/spec.md`; this specification SHALL NOT redefine that common behavior.

## Requirements

### REQ-011: Filedata backups run on per-service cron schedules
The filedata backup service SHALL schedule each selected service independently
using its registered cron schedule.

#### Scenario: Per-service schedule variables declared
- **GIVEN** the relevant backup configuration and deployment state are available for inspection
- **WHEN** `backup-volumes.conf`, the generated startup command, and environment examples are inspected
- **THEN** each service (pihole, npm, vaultwarden) SHALL reference its own schedule variable (`PIHOLE_CRON_SCHEDULE`, `NPM_CRON_SCHEDULE`, `VAULTWARDEN_CRON_SCHEDULE`)
- **AND** the generated startup command SHALL rewrite `/etc/crontabs/root` with `>` so container starts remain idempotent
- **AND** the variables SHALL NOT share a single `CRON_SCHEDULE` value

#### Scenario: Default filedata backup schedule staggering
- **GIVEN** the relevant backup configuration and deployment state are available for inspection
- **WHEN** the filedata backup service is deployed with default schedule values
- **THEN** pihole backs up every 10 days at 2:00 AM (`0 2 */10 * *`)
- **AND** npm backs up every 7 days at 2:10 AM (`10 2 */7 * *`)
- **AND** vaultwarden backs up at 2:15 AM (`15 2 * * *`)

#### Scenario: Vaultwarden schedule remains independent
- **GIVEN** the relevant backup configuration and deployment state are available for inspection
- **WHEN** the filedata backup service is deployed
- **THEN** vaultwarden backup schedule is controlled by `VAULTWARDEN_CRON_SCHEDULE` independently of the other service schedule variables

### REQ-012: Postgres database backups run on staggered cron schedules
PostgreSQL profiles SHALL pass each database's registry schedule via one
per-service `*_CRON_SCHEDULE` variable.

#### Scenario: Generated jobs reference per-service cron variables
- **GIVEN** `backupServices/postgres/start-backup.sh` and `backup-databases.conf` are inspected
- **WHEN** reviewing the generated `db-backup` cron jobs
- **THEN** each scheduled database SHALL reference a per-service variable named `{SERVICE}_CRON_SCHEDULE`
- **AND** the first cron `echo` in the generated command SHALL rewrite `/etc/crontabs/root` with `>` so container starts remain idempotent
- **AND** profile-specific variables such as `*_REMOTE_CRON_SCHEDULE` and `*_LOCAL_CRON_SCHEDULE` SHALL NOT be used

#### Scenario: Registry provides independent postgres schedules
- **GIVEN** `backupServices/postgres/backup-databases.conf` is inspected
- **WHEN** checking PostgreSQL database entries
- **THEN** each entry SHALL include its own cron schedule
- **AND** the generated schedule SHALL override any legacy environment value

### REQ-013: Service-Specific Backup Schedules
The backup system SHALL use per-service configurable cron schedules that reflect each service's data change frequency and acceptable backup intervals.

#### Scenario: Pi-hole backup schedule
- **GIVEN** the relevant backup configuration and deployment state are available for inspection
- **WHEN** the filedata backup system is configured
- **THEN** Pi-hole backups SHALL run every 10 days (`0 2 */10 * *`)
- **AND** Pi-hole backup retention SHALL be set to 61 days

#### Scenario: NPM backup schedule
- **GIVEN** the relevant backup configuration and deployment state are available for inspection
- **WHEN** the filedata backup system is configured
- **THEN** NPM (Nginx Proxy Manager) backups SHALL run every 7 days (`0 2 */7 * *`)
- **AND** NPM backup retention SHALL be set to 57 days

#### Scenario: Invidious backup schedule
- **GIVEN** the relevant backup configuration and deployment state are available for inspection
- **WHEN** the PostgreSQL backup system is configured
- **THEN** Invidious database backups SHALL run every 2 days (`0 3 */2 * *`)
- **AND** Invidious backup retention SHALL be set to 30 days

#### Scenario: Unchanged services
- **GIVEN** the relevant backup configuration and deployment state are available for inspection
- **WHEN** backup schedules are updated
- **THEN** Vaultwarden and Firefly backup schedules and retention SHALL remain unchanged

### REQ-014: Every service SHALL be covered by backup before deployment is considered complete
When a service is newly added or standardized, it SHALL have backup integration configured as part of the standardization work. A service without backup coverage SHALL be considered incompletely standardized.

The backup mechanism is determined by the type of persistent data:

| Data type | Backup service | Configuration location |
|---|---|---|
| PostgreSQL database | `backupServices/postgres/` (`db-backup` service) | Register the database profile and add a case block to `db-backup-script.sh` |
| Docker volume / filesystem data | `backupServices/filedata/` (`filedata-backup` service) | Register the volume and host profiles in `backup-volumes.conf`; generated mounts and jobs are merged with `docker-compose.yml` by `start-backup.sh` |

A service with both PostgreSQL and filedata persistence SHALL use both
mechanisms.

#### Scenario: Service standardized without backup
- **GIVEN** the relevant backup configuration and deployment state are available for inspection
- **WHEN** a service's docker-compose.yml is updated to follow homelab standards (network, volumes, etc.)
- **THEN** a backup task for that service SHALL also be present in the same change's task list
- **AND** the service's `SERVICE_DOCUMENTATION.md` SHALL explicitly state whether backup is configured or explicitly deferred with a rationale

#### Scenario: PostgreSQL-backed service backup integration
- **GIVEN** the relevant backup configuration and deployment state are available for inspection
- **WHEN** a service uses a PostgreSQL database
- **THEN** the service's postgres volume SHALL be registered in `backupServices/postgres/backup-databases.conf`
- **AND** the selected profile SHALL mount that volume into `db-backup`
- **AND** a cron entry SHALL be present in the `db-backup` command for that service
- **AND** a case block SHALL exist in `backupServices/postgres/db-backup-script.sh` for that service's database

#### Scenario: Filesystem/volume-backed service backup integration
- **GIVEN** the relevant backup configuration and deployment state are available for inspection
- **WHEN** a service uses persistent Docker volumes (non-database storage)
- **THEN** those volumes SHALL be registered in `backupServices/filedata/backup-volumes.conf`
- **AND** their mounts and cron jobs SHALL be generated by `start-backup.sh`
- **AND** the volume name and retention period SHALL be defined in the registry
- **AND** the destination SHALL be configured in `backupServices/filedata/path.local` and `path.prod`
- **AND** a cron entry SHALL be present in the `filedata-backup` container command for each registered volume
- **NOTE** `filedata-backup-script.sh` is fully generic and resolves configuration via env var indirection — no per-service block is required in the script itself

#### Scenario: Backup deferred with documented rationale
- **GIVEN** the relevant backup configuration and deployment state are available for inspection
- **WHEN** backup integration is explicitly deferred (e.g., service not yet production-ready)
- **THEN** the deferral SHALL be documented in the service's `SERVICE_DOCUMENTATION.md` under the "Backup Coverage" section
- **AND** a tracking task SHALL be created in the relevant OpenSpec change or a follow-up change
- **AND** the deferral SHALL NOT be treated as a permanent state

### REQ-015: Legacy Immich backup scripts removed
The system SHALL NOT contain Duplicity- or MEGA-based backup scripts in the `mediaServices/immich/` directory. These scripts are superseded by the homelab standard backup infrastructure.

#### Scenario: Legacy files absent from the repository
- **GIVEN** the relevant backup configuration and deployment state are available for inspection
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
The system SHALL define Immich filedata destinations in `backupServices/filedata/path.local` and `path.prod` and select each volume's mode, schedule, and retention in the backup registry. This SHALL include 30-day deleted/replaced-file retention for sync-crypt operation.

#### Scenario: Backup service starts without missing variable errors
- **GIVEN** Immich modes are registered and destination variables are present in `path.local`
- **WHEN** `start-backup.sh local` generates the Compose configuration
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

### REQ-020: Prod Backup Profile — Scoped Volume Set
When started with the `prod` host profile, the filedata startup script SHALL select
only the four prod-profile source volumes from `backup-volumes.conf`.

#### Scenario: Prod backup volumes are exactly the active service set
- **GIVEN** the Prod filedata backup profile is selected
- **WHEN** `backup-volumes.conf` and the generated Prod Compose model are inspected
- **THEN** the source selection SHALL contain `freshrss_filedata`,
  `npm_filedata`, `pihole_filedata`, and `vaultwarden_filedata`
- **AND** volumes for openwebui and immich SHALL NOT be
  present

#### Scenario: Prod backup jobs are scoped to active services
- **GIVEN** the relevant backup configuration and deployment state are available for inspection
- **WHEN** the generated remote filedata backup configuration is inspected
- **THEN** cron jobs SHALL exist for pihole, npm, vaultwarden, and freshrss
- **AND** jobs for openwebui and immich SHALL NOT be present

#### Scenario: freshrss_filedata volume is backed up on Prod
- **GIVEN** the relevant backup configuration and deployment state are available for inspection
- **WHEN** the `FRESHRSS_CRON_SCHEDULE` fires on the remote host
- **THEN** the `filedata-backup` container SHALL create a GPG-encrypted tar
  archive of `freshrss_filedata`
- **AND** upload it to Dropbox at `FRESHRSS_DROPBOX_PATH`

### REQ-021: Backup service environment example files
Filedata and PostgreSQL backup services SHALL use the configuration conventions
defined in `repository-conventions`.

#### Scenario: filedata backup service configuration files
- **GIVEN** `backupServices/filedata/` is inspected
- **WHEN** listing tracked files
- **THEN** `path.local` SHALL be present with `/App_acc/` Dropbox paths
- **AND** `path.prod` SHALL be present with `/Apps/` Dropbox paths
- **AND** `.env.example` SHALL contain credentials without destination paths
- **AND** `.env.backup` SHALL NOT be present (removed)

#### Scenario: filedata path files cover all services
- **GIVEN** `backupServices/filedata/path.local` and `path.prod` are inspected
- **WHEN** checking the set of variable names
- **THEN** both files SHALL declare variables for: pihole, npm, vaultwarden,
  openwebui, freshrss, immich (library, profile, upload)

#### Scenario: postgres backup service configuration files
- **GIVEN** `backupServices/postgres/` is inspected
- **WHEN** listing tracked files
- **THEN** `.env.example` SHALL contain credentials without destination paths
- **AND** `path.local` SHALL contain `/App_acc/` Dropbox paths
- **AND** `path.prod` SHALL contain `/Apps/` Dropbox paths
- **AND** `.env.backup` SHALL NOT be present (removed)

#### Scenario: postgres env example covers all services
- **GIVEN** `backupServices/postgres/.env.example` is inspected
- **WHEN** checking the set of variable names
- **THEN** it SHALL declare database credentials for:
  invidious, firefly, paperless, immich, firefoxsync, romm
- **AND** schedules and retention SHALL be configured in `backup-databases.conf`
- **AND** it SHALL declare shared credentials: `DROPBOX_AUTH_TOKEN`,
  `DROPBOX_REFRESH_TOKEN`, `GPG_PASSPHRASE`, `DISCORD_WEBHOOK_URL`

### REQ-022: Firefox Volume Registered in Filedata Backup
The `firefox_filedata` Docker volume SHALL be selected in the default filedata
host profile so that the Firefox browser profile is included in the standard
GPG-encrypted, multi-cloud backup pipeline.

#### Scenario: Volume selected in backup service
- **GIVEN** the relevant backup configuration and deployment state are available for inspection
- **WHEN** `backupServices/filedata/backup-volumes.conf` is inspected
- **THEN** `firefox_filedata` SHALL be selected for the default profile
- **AND** its generated mount SHALL be `/backup-sources/firefox:ro`

#### Scenario: Cron entry present
- **GIVEN** the relevant backup configuration and deployment state are available for inspection
- **WHEN** the default profile's generated crontab is inspected
- **THEN** an entry using `${FIREFOX_CRON_SCHEDULE}` SHALL invoke
  `/usr/local/bin/backup-script.sh firefox`

#### Scenario: Firefox backup configuration declared
- **GIVEN** the relevant backup configuration and deployment state are available for inspection
- **WHEN** the registry and filedata path files are inspected
- **THEN** the Firefox schedule and retention SHALL be present in the registry
- **AND** `FIREFOX_DROPBOX_PATH` SHALL be present in the environment

#### Scenario: Filedata path files include Firefox
- **GIVEN** the relevant backup configuration and deployment state are available for inspection
- **WHEN** `backupServices/filedata/path.prod` and `path.local` are inspected
- **THEN** a `# Firefox` section SHALL be present in both files containing `FIREFOX_DROPBOX_PATH`
- **AND** the registry schedule SHALL be `10 4 * * *` (staggered at least 5 minutes after FreshRSS at `0 4 * * *`)

### REQ-023: Backup Profiles Preserve The Shared Ordering Contract
The filedata registry and each generated Compose override SHALL follow the
category, service, volume-suffix, and crontab-comment ordering contract defined
in `backup-services` REQ-030 and the repository's backup Compose instructions.

#### Scenario: New service backup integration preserves ordering
- **GIVEN** a stateful service is being added to an applicable backup profile
- **WHEN** registry entries, generated mounts, and cron jobs are added
- **THEN** each entry SHALL be inserted into its sorted position rather than
  appended after unrelated services or shared resources
- **AND** disabled entries SHALL retain their sorted positions and disabled state
- **AND** the profile SHALL retain its deployment-specific backup coverage

### REQ-024: Filedata Profiles Use Registry-Configured Backup Modes
Filedata backup profiles SHALL follow `backup-services` REQ-031 by loading modes
from the volume registry and passing them through the generated Compose override.

#### Scenario: Compose startup applies registered mode configuration
- **GIVEN** the filedata registry defines modes for selected volumes
- **WHEN** a backup profile's Compose override is generated
- **THEN** each selected volume's registered mode SHALL be passed to the container
- **AND** Immich and Paperless SHALL be registered in `sync-crypt` mode

### REQ-025: Immich upload data migrated from bind-mount to named volumes
The system SHALL provide a migration path for existing photo data from the legacy `${UPLOAD_LOCATION}` host path into the three named Docker volumes (`immich_library`, `immich_profile`, `immich_upload`) before the service is restarted with the new compose configuration.

#### Scenario: Existing photo data preserved after migration
- **GIVEN** the relevant backup configuration and deployment state are available for inspection
- **WHEN** the migration script or manual copy completes
- **THEN** all files previously at `${UPLOAD_LOCATION}/library`, `${UPLOAD_LOCATION}/profile`, and `${UPLOAD_LOCATION}/upload` SHALL be present inside their respective named volumes
- **AND** the `immich` container SHALL start without reporting missing library data
