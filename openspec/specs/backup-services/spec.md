## Purpose
Define backup coverage, encryption, retention, scheduling, and notification requirements for homelab database and filedata backup services.
## Requirements

### REQ-001: Two dedicated backup services cover all persistent data
The homelab SHALL maintain exactly two backup services: `filedata-backup` at
`backupServices/filedata/` for Docker named volumes, and `db-backup` at
`backupServices/postgres/` for PostgreSQL databases. Every stateful service in the
homelab SHALL be covered by one or both of these services.

#### Scenario: Stateful service has backup coverage
- **GIVEN** a service with at least one persistent Docker volume or PostgreSQL database
- **WHEN** the service's standardization is considered complete
- **THEN** the service SHALL be registered in `filedata-backup`, `db-backup`, or both
- **AND** the service's `SERVICE_DOCUMENTATION.md` SHALL state whether backup is
  configured or explicitly deferred with a rationale

#### Scenario: Backup deferred is documented and tracked
- **GIVEN** backup integration for a service is explicitly deferred
- **WHEN** reading the service's `SERVICE_DOCUMENTATION.md`
- **THEN** a "Backup Coverage" section SHALL explain the deferral rationale
- **AND** a tracking task SHALL exist in the relevant OpenSpec change

### REQ-002: All backups are GPG AES256 encrypted before leaving the container
Every backup archive produced by `filedata-backup` or `db-backup` SHALL be encrypted
with GPG symmetric encryption using the AES256 cipher before any upload or retention
operation. The encryption passphrase SHALL be loaded from `/run/secrets/gpg-passphrase`.
The unencrypted intermediate file SHALL be deleted immediately after encryption.

#### Scenario: Backup file at rest is encrypted
- **GIVEN** a backup run completes for any service
 - **WHEN** the local backup directory is inspected
 - **THEN** only `.sql.zst.gpg` (postgres zstd-compressed) or `.tar.zst.gpg` (filedata zstd-compressed) files SHALL exist
 - **AND** no unencrypted `.sql` or `.tar.zst` intermediates SHALL remain

### REQ-003: Encrypted backups are uploaded via mode-specific rclone destinations
After encryption or sync preparation, each backup run SHALL upload or synchronize data through rclone using destination variables defined for that service and selected mode. Database backups SHALL remain Dropbox-targeted. Filedata backups SHALL be permitted to target provider-specific remotes (for example Dropbox or MEGA) based on per-service mode configuration.

#### Scenario: Dropbox archive mode does not use rclone crypt
- **GIVEN** a filedata service is configured with mode `archive` and Dropbox destination
- **WHEN** the archive-mode backup runs
- **THEN** the backup artifact SHALL be encrypted by GPG before upload
- **AND** upload SHALL use the plain `dropbox` remote (not a crypt-wrapped Dropbox remote)

#### Scenario: Database backup uploads to Dropbox
- **GIVEN** a successful database dump encryption step
- **WHEN** the rclone upload runs for `db-backup`
- **THEN** the output file SHALL be uploaded to Dropbox using the configured database Dropbox path variable
- **AND** the rclone exit code SHALL be checked and logged

#### Scenario: Filedata service syncs to configured remote
- **GIVEN** a filedata service is configured for `sync-crypt` mode
- **WHEN** its scheduled backup runs
- **THEN** rclone SHALL target the service's configured remote destination path
- **AND** the job outcome SHALL be logged with success/failure status

#### Scenario: Filedata service uses a pure crypt mirror
- **GIVEN** a filedata service is configured with `sync-crypt` mode and retention `0`
- **WHEN** its scheduled backup runs
- **THEN** rclone SHALL synchronize the source tree directly into the configured `current/`
  namespace
- **AND** the job SHALL NOT create a GPG archive or a deleted-file retention namespace

### REQ-004: Retention is enforced per service
Each filedata service SHALL have a retention value in the registry, passed to the
backup container through its dedicated `{SERVICE}_RETENTION_DAYS` environment
variable. Database retention SHALL remain environment-configured. Old local backup files SHALL be
deleted after this many days using `find ... -mtime +{days} -delete`.

#### Scenario: Old local backups are pruned
- **GIVEN** backup files older than `{SERVICE}_RETENTION_DAYS` exist in the local backup directory
- **WHEN** a new backup run completes
- **THEN** files older than the retention threshold SHALL be deleted
- **AND** newer files SHALL be preserved

### REQ-005: Discord webhook notification is sent only on backup failure
Every backup run SHALL send a Discord webhook notification when any step fails.
Successful backup runs SHALL NOT send a Discord notification.
The notification SHALL include the service name, outcome, timestamp, and originating
hostname.

#### Scenario: Failure notification sent
- **GIVEN** a backup step fails (encryption, upload, or pg_dump error)
- **WHEN** the failure is detected
- **THEN** a Discord embed SHALL be posted with "FAILURE" status and the error detail

#### Scenario: No notification sent on success
- **GIVEN** a backup run completes without error
- **WHEN** the backup script exits
- **THEN** no Discord webhook request SHALL be made

### REQ-006: Backup schedules use per-service cron variables, not a single shared schedule
Neither `filedata-backup` nor `db-backup` SHALL use a single `CRON_SCHEDULE` variable
shared across all services. Each filedata schedule SHALL be configured in its
registry entry and passed as a dedicated `{SERVICE}_CRON_SCHEDULE` environment
variable; database schedules SHALL remain environment-configured.

#### Scenario: Per-service schedule variables are declared
- **GIVEN** a `docker-compose.yml` command block for a backup service is inspected
- **WHEN** checking cron entries
- **THEN** each registered service SHALL reference its own schedule variable
  (e.g., `PIHOLE_CRON_SCHEDULE`, `NPM_CRON_SCHEDULE`, `VAULTWARDEN_CRON_SCHEDULE`)
- **AND** a single `CRON_SCHEDULE` shared across services SHALL NOT exist

### REQ-007: Backup schedule timing
Filedata backup cron entries SHALL use their registered schedules without a global
earliest start time or uniqueness requirement. Postgres backup cron entries SHALL
start no earlier than 03:00 and be staggered at minimum 5 minutes apart.

#### Scenario: Filedata schedules follow the registry
- **GIVEN** `backup-volumes.conf` contains the registered filedata schedules
- **WHEN** the default filedata schedules are inspected
- **THEN** Syncthing SHALL be scheduled at 01:15 and Jellyfin at 01:20
- **AND** Radicale and Immich library SHALL both be scheduled at 03:00

#### Scenario: Default postgres schedules are staggered from 03:00
- **GIVEN** the postgres backup service is deployed with default schedule values
- **WHEN** all per-database cron schedules are read
- **THEN** no two databases SHALL share the same cron time
- **AND** the earliest entry SHALL be at 03:00 or later

### REQ-008: filedata-backup mounts source volumes read-only at /backup-sources/<service>
Each volume registered with `filedata-backup` SHALL be mounted read-only in the
`filedata-backup` container at `/backup-sources/<service-name>`.

#### Scenario: Volume is mounted read-only
- **GIVEN** a service volume is registered with filedata-backup
- **WHEN** the `docker-compose.yml` volumes block is inspected
- **THEN** the volume SHALL appear with `:ro` suffix
- **AND** the mount path SHALL be `/backup-sources/<service-name>`

### REQ-009: db-backup uses pg_dump per database with a case block in the backup script
The `db-backup-script.sh` SHALL contain a `case` block with one entry per registered
database. Each entry shall set the host, user, password, database name, Dropbox path,
local backup directory, and retention days for that database.

#### Scenario: Unknown database argument is rejected
- **GIVEN** `db-backup-script.sh` is invoked with an unrecognized database name
- **WHEN** the case block is evaluated
- **THEN** the script SHALL exit with a non-zero code and log "Unknown database"

#### Scenario: Known database produces a named backup file
- **GIVEN** `db-backup-script.sh` is invoked with a registered database name
- **WHEN** the backup completes
 - **THEN** a file matching `<database>_YYYYMMDD_HHMMSS.sql.zst.gpg` SHALL exist in
  `/backups/<database>/`

### REQ-010: db-backup joins every network needed to reach its registered databases
The `db-backup` service SHALL be connected to the Docker network of every service
whose database it backs up. It SHALL NOT rely on host-mode or IP addresses.

#### Scenario: db-backup can reach each database container by hostname
- **GIVEN** db-backup is configured to back up the `firefly-db` container
- **WHEN** `docker network inspect finance_network` is run
- **THEN** `db-backup` SHALL appear in the `Containers` section
- **AND** the `firefly-db` container SHALL also be on the same network

### REQ-011: Vaultwarden volume is registered with filedata-backup
The `vaultwarden_filedata` volume SHALL be mounted read-only in the `filedata-backup`
container at `/backup-sources/vaultwarden`. The registry SHALL declare its
schedule and retention.

#### Scenario: Vaultwarden backup runs on its own schedule
- **GIVEN** `VAULTWARDEN_CRON_SCHEDULE` fires
- **WHEN** the backup script runs with argument `vaultwarden`
 - **THEN** a `.tar.zst.gpg` archive of `vaultwarden_filedata` SHALL be created
 - **AND** uploaded to Dropbox at `VAULTWARDEN_DROPBOX_PATH`

### REQ-012: Paperless database is registered with db-backup
The `paperless_postgresdata` volume SHALL be mounted read-only in `db-backup`. A
`paperless` case block SHALL exist in `db-backup-script.sh`. `db-backup` SHALL join
`knowledge_network` to reach the `paperless-db` container by hostname.

#### Scenario: Paperless backup produces a correctly named file
- **GIVEN** the paperless cron entry fires
- **WHEN** `db-backup-script.sh paperless` runs
  - **THEN** a file matching `paperless_YYYYMMDD_HHMMSS.sql.zst.gpg` SHALL exist in
  `/backups/paperless/`
- **AND** a Discord notification SHALL be sent only if the backup fails only if the backup fails

#### Scenario: Local backup retains authenticated database access after migration
- **GIVEN** Paperless has moved to `knowledge_network`
- **WHEN** Local `db-backup` connects to `paperless-db` on `knowledge_network`
- **THEN** it SHALL authenticate using the existing database credentials

### REQ-013: Immich photo volumes are registered with filedata-backup
The three Immich photo volumes (`immich_library`, `immich_profile`, `immich_upload`) SHALL each be mounted read-only in `filedata-backup` at `/backup-sources/immich-library`, `/backup-sources/immich-profile`, and `/backup-sources/immich-upload` respectively. Each volume SHALL define its own destination variable and its mode, schedule, and retention in the registry. The ML model cache volume is ephemeral and SHALL NOT be included.

#### Scenario: Each Immich photo volume is backed up independently
- **GIVEN** each Immich volume cron schedule fires
- **WHEN** filedata-backup executes that volume's job
- **THEN** only that volume's backup job SHALL run
- **AND** no other Immich volume backup SHALL be triggered by that cron entry

#### Scenario: Immich volumes run in sync-crypt mode
- **GIVEN** Immich file volumes are configured with mode `sync-crypt`
- **WHEN** the scheduled run executes
- **THEN** each volume SHALL sync into its configured `current/` namespace
- **AND** replaced/deleted files SHALL be moved to dated retention paths before pruning

#### Scenario: Hyphenated job names resolve underscore env variables
- **GIVEN** a scheduled backup job invokes `filedata-backup-script.sh` with a hyphenated identifier such as `immich-library`
- **WHEN** the script resolves mode, retention, and destination environment variables
- **THEN** the script SHALL normalize the identifier to underscore uppercase form for env-key lookup
- **AND** `IMMICH_LIBRARY_BACKUP_MODE` and `IMMICH_LIBRARY_SYNC_CRYPT_REMOTE` SHALL be resolved correctly

### REQ-014: Immich PostgreSQL database is registered with db-backup
The `immich_postgresdata` volume SHALL be mounted read-only in `db-backup`. An
`immich` case block SHALL exist in `db-backup-script.sh`. The backup file SHALL use
 the naming convention `backup_immich_{timestamp}.sql.zst.gpg`. `db-backup` SHALL join
`media_network` to reach the `immich-db` container.

#### Scenario: Immich database backup produces correctly named file
- **GIVEN** the `immich` cron entry fires in `db-backup`
- **WHEN** `db-backup-script.sh immich` runs
 - **THEN** a file matching `backup_immich_YYYYMMDD_HHMMSS.sql.zst.gpg` SHALL exist
- **AND** a Discord notification SHALL be sent only if the backup fails

### REQ-015: Both backup services have SERVICE_DOCUMENTATION.md and RESTORE_GUIDE.md
Both `backupServices/filedata/` and `backupServices/postgres/` SHALL have a
`SERVICE_DOCUMENTATION.md` and a `RESTORE_GUIDE.md`. Non-standard documentation files
(e.g., `IMPLEMENTATION_DETAILS.md`, `QUICKSTART_GUIDE.md`) SHALL be migrated into
these two standard files and removed.

#### Scenario: Standard documentation files are present
- **GIVEN** either backup service directory is inspected
- **WHEN** listing tracked files
- **THEN** both `SERVICE_DOCUMENTATION.md` and `RESTORE_GUIDE.md` SHALL be present
- **AND** `IMPLEMENTATION_DETAILS.md` and `QUICKSTART_GUIDE.md` SHALL NOT exist

### REQ-016: Backup services provide credential and destination configuration
`backupServices/filedata/` SHALL provide a credentials-only `.env.example` and
destination files `path.local` and `path.prod`; `backupServices/postgres/` SHALL
provide `.env.acc.example` and `.env.prd.example`. The filedata path files and
the PostgreSQL examples SHALL each declare matching variable names per pair.
Filedata destinations SHALL be permitted to differ by environment and mode.

#### Scenario: Filedata path files cover all registered services
- **GIVEN** `path.local` and `path.prod` are compared
- **WHEN** checking variable names
- **THEN** both files SHALL declare identical destination variable names
- **AND** `.env.example` SHALL contain credentials rather than destination paths

#### Scenario: PostgreSQL examples cover all registered services
- **GIVEN** `.env.acc.example` and `.env.prd.example` are compared for PostgreSQL backups
- **WHEN** checking variable names
- **THEN** both files SHALL declare identical variable names
- **AND** value differences SHALL be limited to environment-specific paths, schedules, or provider targets

### REQ-017: Backup health is verified on a three-tier schedule
Operators SHALL follow a three-tier verification schedule: daily (check container logs
for errors and absence of unexpected Discord alerts), weekly (`rclone ls <remote>:/Apps/<service>/`
to verify files exist), monthly (full test-restore to a non-production environment).

#### Scenario: Daily verification confirms last night's backup
- **GIVEN** an operator checks backup status as part of a morning health check
- **WHEN** they review backup container logs
- **THEN** logs SHALL show a successful completion message for each scheduled database
- **AND** no Discord failure notification SHALL have been received for the previous night's run

#### Scenario: Monthly test-restore confirms recoverability
- **GIVEN** a monthly test-restore is performed
- **WHEN** the restored data is validated
- **THEN** database row counts SHALL match known baselines
- **AND** Vaultwarden vault SHALL unlock successfully from the restored data

### REQ-018: Remote backup services SHALL be deployed from dedicated scoped compose files
When deploying backup services to a remote host, the operator SHALL use
`backupServices/postgres/docker-compose.remote.yml` for PostgreSQL and
`backupServices/filedata/start-backup.sh prod` for filedata.

#### Scenario: Remote postgres backup deployed with correct scope
- **GIVEN** a remote host is configured for the remote PostgreSQL backup profile
- **WHEN** the operator starts the postgres backup service
- **THEN** the command SHALL be `docker compose -f docker-compose.remote.yml up -d`
- **AND** only `firefly_postgresdata` and `firefoxsync_postgresdata` volumes SHALL be mounted
- **AND** only `finance_network` and `security_network` SHALL be joined
- **AND** `firefly` and `firefoxsync` SHALL each have a scheduled backup job

#### Scenario: Prod filedata backup deployed with correct scope
- **GIVEN** a remote host is configured for the prod filedata backup profile
- **WHEN** the operator starts the filedata backup service
- **THEN** the command SHALL be `./start-backup.sh prod`
- **AND** only `pihole_filedata`, `npm_filedata`, `vaultwarden_filedata`, and
  `freshrss_filedata` volumes SHALL be mounted

### REQ-019: Filedata Backup Uses One Generated Compose Configuration
The filedata backup service SHALL use one canonical `docker-compose.yml` together
with `backup-volumes.conf` and `start-backup.sh`. The startup script SHALL generate
a temporary override for the selected host profile and SHALL remove it on exit.

#### Scenario: Filedata profile renders from the canonical base
- **GIVEN** a host profile and its required schedule variables are configured
- **WHEN** `start-backup.sh` starts the filedata service
- **THEN** the generated override SHALL be merged with the canonical `docker-compose.yml`
- **AND** the service SHALL receive only the source volumes selected by that profile
- **AND** no persistent Local or Prod filedata Compose profile SHALL be required

### REQ-020: Generated Filedata Profiles SHALL Validate Independently
Each generated filedata profile SHALL render successfully with Docker Compose
without requiring a separate profile Compose file.

#### Scenario: Generated filedata configuration is valid
- **GIVEN** Docker volumes and schedules are configured for a supported host profile
- **WHEN** the startup script generates and renders the Compose configuration
- **THEN** the command SHALL produce a valid Compose model

### REQ-021: Scoped backup profile changes SHALL remain deployment-scoped
Changes to a remote PostgreSQL profile or a filedata host selection SHALL affect
only services deployed to that profile and SHALL NOT enable unrelated jobs.

#### Scenario: Scoped profile addition preserves default and Local scope
- **GIVEN** a backup job is added to the remote PostgreSQL profile or filedata registry
- **WHEN** the relevant backup configuration is inspected
- **THEN** the changed profile SHALL contain only that profile's deployed jobs
- **AND** other host profiles SHALL retain their configured service sets

### REQ-022: Paperless retained documents are registered with filedata-backup
The `paperless_filedata` volume SHALL be registered in `backup-volumes.conf` for every deployed host profile, with its schedule and retention. The filedata backup service SHALL declare Paperless destination variables in both `path.local` and `path.prod`.

#### Scenario: Backup profiles preserve configuration during the category move
- **GIVEN** Paperless backup configuration exists before the move to Knowledge Services
- **WHEN** the default, Local, Remote PostgreSQL, and Prod filedata profiles are reviewed after the move
- **THEN** the default and Local profiles SHALL group Paperless entries under Knowledge Services
- **AND** existing Paperless backup modes, schedules, and remote destinations SHALL remain unchanged
- **AND** the Remote PostgreSQL and Prod filedata profiles SHALL NOT enable Paperless jobs

#### Scenario: Paperless media volume is mounted in filedata-backup
- **GIVEN** `backupServices/filedata/backup-volumes.conf` is inspected
- **WHEN** Paperless host-profile entries are reviewed
- **THEN** `paperless_filedata` SHALL map to the `paperless` backup name
- **AND** every configured Paperless host profile SHALL include `default`

#### Scenario: Paperless backup configuration is documented
- **GIVEN** `backupServices/filedata/path.local` and `path.prod` are inspected
- **WHEN** Paperless entries are reviewed
- **THEN** `PAPERLESS_DROPBOX_PATH` and `PAPERLESS_SYNC_CRYPT_REMOTE` SHALL be present in both files
- **AND** the Paperless schedule and retention SHALL be present in the registry
- **AND** the paths SHALL follow the selected destination-file convention

### REQ-023: Paperless retained-file backups exclude derived media artifacts
The `filedata-backup` pipeline SHALL back up only the canonical retained Paperless document paths from `paperless_filedata`. It SHALL include `documents/originals/**` and `documents/archive/**`, and it SHALL exclude `documents/thumbnails/**` plus runtime lock artifacts.

#### Scenario: Paperless backup includes canonical retained documents
- **GIVEN** the Paperless file backup runs for `paperless`
- **WHEN** the backup archive is created
- **THEN** files under `documents/originals/` SHALL be included
- **AND** files under `documents/archive/` SHALL be included

#### Scenario: Paperless backup excludes thumbnails and runtime artifacts
- **GIVEN** the Paperless file backup runs for `paperless`
- **WHEN** the backup archive is created
- **THEN** files under `documents/thumbnails/` SHALL NOT be included
- **AND** runtime lock artifacts such as `media.lock` SHALL NOT be included

### REQ-024: Local backup services SHALL be deployed from dedicated local-scoped compose files
When deploying backup services to the Local environment, the operator SHALL use
`docker-compose.local.yml` for PostgreSQL and `start-backup.sh local` for filedata.

#### Scenario: Local postgres backup deployed with correct scope
- **GIVEN** the Local environment is configured
- **WHEN** the operator starts the postgres backup service
- **THEN** the command SHALL be `docker compose -f docker-compose.local.yml up -d`
- **AND** the database source volumes SHALL be `romm_postgresdata`,
  `paperless_postgresdata`, and `invidious_postgresdata`, in that order
- **AND** only `games_network`, `knowledge_network`, and `media_network` SHALL be joined

#### Scenario: Local filedata backup deployed with correct scope
- **GIVEN** the Local environment is configured
- **WHEN** the operator starts the filedata backup service
- **THEN** the command SHALL be `./start-backup.sh local`
- **AND** its active source volumes SHALL be determined by `backup-volumes.conf`
- **AND** the RomM source volume SHALL be read-only and its schedule SHALL use
  `ROMM_CRON_SCHEDULE`

#### Scenario: Local filedata profile uses the canonical compose base
- **GIVEN** the Local filedata backup profile is selected
- **WHEN** its Compose configuration is generated
- **THEN** the generated override SHALL use the canonical `docker-compose.yml`
- **AND** the Local selection SHALL be defined in `backup-volumes.conf`

### REQ-025: OpenWebUI Tier C Selective Filedata Backup
The `backupServices/filedata/filedata-backup-script.sh` workflow SHALL apply an OpenWebUI-specific selective backup policy that preserves SQLite state files and uploads while excluding rebuildable cache and vector index paths.

#### Scenario: OpenWebUI backup includes Tier C essential artifacts
- **GIVEN** `filedata-backup` runs with argument `openwebui`
- **WHEN** the archive is created
- **THEN** `webui.db`, `webui.db-wal`, `webui.db-shm`, and `uploads/` content SHALL be included
- **AND** the resulting backup SHALL remain compatible with standard restore tooling

#### Scenario: OpenWebUI backup excludes rebuildable artifacts
- **GIVEN** `filedata-backup` runs with argument `openwebui`
- **WHEN** tar include/exclude rules are applied
- **THEN** `cache/` and `vector_db/` content SHALL NOT be included in the encrypted backup artifact
- **AND** backup completion SHALL continue to follow existing encryption, upload, and retention behavior

### REQ-026: OpenWebUI Selective Backup Policy Uniformity
Any compose profile that schedules OpenWebUI filedata backups SHALL apply the same Tier C policy behavior.

#### Scenario: Environment profile differences do not change OpenWebUI backup scope
- **GIVEN** OpenWebUI backup is run in any environment where the service is configured
- **WHEN** backup rules are evaluated
- **THEN** the same include/exclude policy SHALL be applied
- **AND** operators SHALL not need per-environment policy exceptions for OpenWebUI Tier C backup

### REQ-027: Syncthing Config Is Registered In Filedata Archive Backups
The default filedata host profile SHALL register a single Syncthing archive
backup lane for the `syncthing_filedata` configuration volume.

#### Scenario: Default filedata registry includes Syncthing config lane
- **GIVEN** `backup-volumes.conf` is inspected
- **WHEN** the Syncthing registration is reviewed
- **THEN** `syncthing_filedata` SHALL be selected by the default host profile
- **AND** the generated mount SHALL be read-only at `/backup-sources/syncthing`
- **AND** the generated cron invocation SHALL run `/usr/local/bin/backup-script.sh syncthing`
- **AND** no `secondbrain` backup source or cron invocation SHALL be registered

### REQ-028: Syncthing Backup Uses Archive Mode With Daily Retention
The Syncthing filedata backup lane SHALL use `archive` backup mode, run daily, and retain backups for 7 days.

#### Scenario: Configuration enforces Syncthing archive policy
- **GIVEN** the filedata backup registry and path files are inspected
- **WHEN** Syncthing backup configuration is reviewed
- **THEN** Syncthing's registered backup mode SHALL be `archive`
- **AND** the registered Syncthing schedule SHALL be daily
- **AND** its registered retention SHALL be `7` days
- **AND** no `SECONDBRAIN_*` backup variables SHALL be present

### REQ-029: Syncthing Backup Scope Is Default And Local Only
Syncthing backup registration SHALL be enabled in the default filedata profile
and SHALL NOT be selected by Local or Prod.

#### Scenario: Profile scope matches Syncthing backup deployment
- **GIVEN** the filedata volume registry is inspected
- **WHEN** the Syncthing entry in `backup-volumes.conf` is reviewed
- **THEN** its selected profiles SHALL include `default`
- **AND** its selected profiles SHALL exclude `local` and `prod`

### REQ-030: Backup Compose Entries Follow Category And Service Order
Backup services SHALL group source-volume mounts, top-level source-volume
declarations, and cron jobs alphabetically by service category, then by service
name. Multiple volumes of one service SHALL be sorted by purpose suffix. The
filedata registry and its generated override SHALL preserve this ordering.
PostgreSQL Compose profiles SHALL preserve the ordering in their source files.
Network references and declarations SHALL be sorted by network name. Shared
secrets mounts SHALL follow grouped source volumes.

#### Scenario: Generated filedata mounts and crontab use matching categories
- **GIVEN** a filedata host profile selects source-volume mounts and jobs
- **WHEN** its generated override and crontab are inspected
- **THEN** volume sections SHALL use category comments
- **AND** cron jobs SHALL use matching `# <Category> Services` comment lines
- **AND** category labels SHALL match the owning service directory
- **AND** the crontab SHALL begin with `# Crontab for database backups` or
  `# Crontab for filedata backups`, written with `>`
- **AND** all category comments and jobs SHALL be appended with `>>`
- **AND** `gpg-secrets` SHALL follow top-level source-volume declarations

#### Scenario: New service is inserted into every applicable backup profile
- **GIVEN** a newly added stateful service requires database or filedata backups
- **WHEN** its backup integration is added
- **THEN** its mounts, volume declarations, and cron jobs SHALL be inserted at
  the category and service-name position in every profile that deploys it
- **AND** required networks SHALL be inserted in network-name order
- **AND** destination files, credential examples, scripts where required, specs, and operator
  documentation SHALL be updated together
- **AND** adding the service SHALL NOT enable unrelated commented entries
- **AND** declaration order SHALL NOT change configured cron execution times

### REQ-031: Filedata Backup Modes Come From The Registry
Each filedata registry entry SHALL specify `archive` or `sync-crypt`. The startup
script SHALL reject missing or invalid modes and pass selected modes to the
container in the generated Compose override, taking precedence over `env_file`.
Volumes requiring `sync-crypt`, including Immich and Paperless, SHALL have that
mode explicitly configured in the registry.

#### Scenario: Explicit mode is resolved by volume identifier
- **GIVEN** `immich-library` is registered with `sync-crypt` mode
- **WHEN** the backup script runs for `immich-library`
- **THEN** the script SHALL resolve the normalized environment key and select
  `sync-crypt` from the generated Compose environment

#### Scenario: Missing or invalid registry mode prevents startup
- **GIVEN** a volume's registry entry has a missing or unsupported backup mode
- **WHEN** the startup script reads the registry
- **THEN** it SHALL report an error and SHALL NOT start the backup container

### REQ-032: Backup Containers Start Without Host Script Mounts Or Package Downloads
Both backup services SHALL build local images from digest-pinned base images in
every Compose profile. The images SHALL include their backup scripts and runtime
dependencies, including zstd. The filedata image SHALL also include
`configure-rclone.sh`. Startup commands SHALL NOT install packages, and backup
scripts SHALL NOT be bind-mounted from the host. Build contexts SHALL allow only
the Dockerfile, build ignore rules, and required scripts, excluding credentials.
Both services SHALL retain the `unless-stopped` restart policy.

#### Scenario: Docker starts backups before an encrypted home is unlocked
- **GIVEN** both backup containers were created and running before shutdown
- **AND** their images and named volumes are available to Docker at boot
- **WHEN** Docker starts before the operator's encrypted home is unlocked
- **THEN** both containers SHALL start their cron schedulers without access to
  host script paths or package repositories
- **AND** existing schedules, source volumes, secrets volumes, and networks
  SHALL remain unchanged

#### Scenario: Script updates require rebuilding the image
- **GIVEN** an operator updates a backup script
- **WHEN** the selected Compose profile is rebuilt and its container recreated
- **THEN** the container SHALL execute the updated image-bundled script

### REQ-033: Jackett and Transmission Configuration Are Backed Up
The default and Local filedata backup profiles SHALL mount `jackett_filedata` and `transmission_filedata` read-only and SHALL schedule separate encrypted archive jobs for each volume. The Prod profile SHALL NOT select either volume.

#### Scenario: Applicable profiles back up Jackett and Transmission
- **GIVEN** the default or Local filedata backup profile is deployed
- **WHEN** its source mounts and cron jobs are inspected
- **THEN** `jackett_filedata` SHALL be mounted at `/backup-sources/jackett` and scheduled for archive backup
- **AND** `transmission_filedata` SHALL be mounted at `/backup-sources/transmission` and scheduled for archive backup
- **AND** the profile SHALL use the corresponding production or acceptance Dropbox paths from its environment example

#### Scenario: Prod profile excludes Jackett and Transmission
- **GIVEN** the Prod filedata backup profile is inspected
- **WHEN** media volume sources and jobs are reviewed
- **THEN** neither `jackett_filedata` nor `transmission_filedata` SHALL be registered

### REQ-034: Jellyfin Backup Covers Configuration Only
The default filedata backup profile SHALL select `jellyfin_filedata` as a read-only source at `/backup-sources/jellyfin` and SHALL back it up using the existing encrypted archive workflow. The profile SHALL NOT back up Jellyfin media-library bind mounts, downloads, transcodes, or cache. Jellyfin SHALL NOT be selected in Local or Prod filedata backup profiles unless those profiles deploy Jellyfin.

#### Scenario: Default filedata profile backs up Jellyfin configuration
- **GIVEN** the default filedata registry selection and production path file are inspected
- **WHEN** Jellyfin backup configuration is reviewed
- **THEN** `jellyfin_filedata` SHALL be mounted read-only at `/backup-sources/jellyfin`
- **AND** a dedicated Jellyfin cron job and archive destination SHALL be configured
- **AND** no Jellyfin media-library source SHALL be registered

#### Scenario: Local and Prod exclude Jellyfin backups
- **GIVEN** the Local and Prod filedata backup profiles do not deploy Jellyfin
- **WHEN** their source mounts, volume declarations, and cron jobs are inspected
- **THEN** neither profile SHALL register `jellyfin_filedata`
- **AND** neither profile SHALL schedule a Jellyfin backup job
- **AND** neither profile SHALL require `JELLYFIN_CRON_SCHEDULE`

#### Scenario: Jellyfin config can be restored without media data
- **GIVEN** a valid encrypted Jellyfin filedata archive is available
- **WHEN** an operator runs the Jellyfin restore workflow
- **THEN** the workflow SHALL restore `jellyfin_filedata` and start Jellyfin
- **AND** it SHALL NOT modify or restore the Movies, TVSeries, Music, or downloads host paths

### REQ-035: OpenCode Is Excluded From Filedata Backups
Filedata backup profiles SHALL NOT select or schedule backups for OpenCode.
The OpenCode service SHALL NOT require OpenCode-specific backup settings in
the filedata destination files.

#### Scenario: OpenCode has no filedata backup entry
- **GIVEN** the default, Local, and Prod filedata backup profiles are inspected
- **WHEN** their AI Services entries and destination files are reviewed
- **THEN** no profile SHALL mount or schedule an OpenCode data backup
- **AND** the destination files SHALL NOT define OpenCode backup settings

### REQ-036: Filedata Backup Verifies Its Source Mount
Each filedata backup run SHALL verify that its source directory is an actual
mount point before starting an archive or synchronizing a remote destination.

#### Scenario: An existing source directory is not mounted
- **GIVEN** the backup source directory exists but is not a mount point
- **WHEN** an archive or sync-crypt backup is started
- **THEN** the backup SHALL exit with an error before creating an archive or modifying the remote
- **AND** the backup SHALL send a source-validation failure notification when Discord is configured

#### Scenario: A mounted source is available
- **GIVEN** the backup source directory is a mount point
- **WHEN** the backup is started
- **THEN** the backup SHALL continue with the existing mode-specific validation and processing

### REQ-037: Filedata Retention And Schedules Come From The Registry
Each filedata registry entry SHALL specify non-negative retention in days and a
five-field cron schedule. The startup script SHALL reject missing or malformed
retention, schedules without five fields, and schedules containing unsafe
characters, and pass selected policies to the container in the generated Compose
override, taking precedence over `env_file`.

#### Scenario: Registered policies control scheduled backups
- **GIVEN** a selected volume has a schedule and retention in the registry
- **WHEN** the startup script generates its Compose configuration
- **THEN** the container SHALL receive the registered schedule and retention
- **AND** legacy environment-file values SHALL NOT override them

#### Scenario: Invalid policy prevents deployment
- **GIVEN** a registry entry has missing or malformed retention, a schedule without five fields, or unsafe schedule characters
- **WHEN** the startup script reads the registry
- **THEN** it SHALL report an error and SHALL NOT start the backup container

### REQ-038: Filedata destinations are selected independently of credentials
Filedata backup SHALL load destinations from the selected tracked path file
after the credentials file so that path-file values override legacy environment
entries. Local and prod host profiles SHALL select their matching path files;
the default host profile SHALL require an explicit local or prod path selection.
The startup script SHALL reject missing, duplicate, or ambiguous destination
entries before starting the container.

#### Scenario: Default profile requires an explicit destination
- **GIVEN** all registered volumes are selected with the default profile
- **WHEN** the operator omits the local or prod destination argument
- **THEN** startup SHALL fail without starting the backup container

#### Scenario: Selected path file overrides legacy destinations
- **GIVEN** an existing credentials file contains a legacy destination value
- **WHEN** a host profile starts with a configured destination in its selected path file
- **THEN** the container SHALL receive the selected path-file value
- **AND** the credentials SHALL remain supplied by the credentials file

### REQ-039: GCP filedata scheduler reports missing sources
The GCP filedata backup restore workflow SHALL report missing production source
volumes and start the scheduler with available volumes. It SHALL send a Discord
alert when a webhook is configured and SHALL report an alert delivery failure
without preventing available volumes from being scheduled. It SHALL fail without
replacing the existing container when no production source volumes are available.

#### Scenario: Some production source volumes are missing
- **GIVEN** at least one production source volume exists and another is missing
- **WHEN** the filedata backup restore workflow starts the scheduler
- **THEN** available volumes SHALL be mounted and scheduled
- **AND** missing volumes SHALL be reported in the workflow logs
- **AND** a configured Discord webhook SHALL receive their names

#### Scenario: No production source volumes are available
- **GIVEN** no production source volumes exist
- **WHEN** the filedata backup restore workflow checks source volumes
- **THEN** it SHALL fail without replacing an existing backup container
