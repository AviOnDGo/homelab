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

### REQ-004: Retention is enforced per service via configurable environment variable
Each service registered with a backup service SHALL have a dedicated
`{SERVICE}_RETENTION_DAYS` environment variable. Old local backup files SHALL be
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
shared across all services. Each service SHALL have its own
`{SERVICE}_CRON_SCHEDULE` environment variable.

#### Scenario: Per-service schedule variables are declared
- **GIVEN** a `docker-compose.yml` command block for a backup service is inspected
- **WHEN** checking cron entries
- **THEN** each registered service SHALL reference its own schedule variable
  (e.g., `PIHOLE_CRON_SCHEDULE`, `NPM_CRON_SCHEDULE`, `VAULTWARDEN_CRON_SCHEDULE`)
- **AND** a single `CRON_SCHEDULE` shared across services SHALL NOT exist

### REQ-007: Backup schedules are staggered — filedata starts 02:00, postgres starts 03:00
Filedata backup cron entries SHALL start no earlier than 02:00 and be staggered at
minimum 5-minute intervals. Postgres backup cron entries SHALL start no earlier than
03:00 and be staggered at minimum 5 minutes apart.

#### Scenario: Default filedata schedules are staggered from 02:00
- **GIVEN** the filedata backup service is deployed with default schedule values
- **WHEN** all per-service cron schedules are read from `env.acc.example`
- **THEN** no two services SHALL share the same cron time
- **AND** the earliest entry SHALL be at 02:00 or later

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
container at `/backup-sources/vaultwarden`. A `VAULTWARDEN_CRON_SCHEDULE` and
`VAULTWARDEN_RETENTION_DAYS` SHALL be declared in `env.acc.example` and `env.prd.example`.

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
The three Immich photo volumes (`immich_library`, `immich_profile`, `immich_upload`) SHALL each be mounted read-only in `filedata-backup` at `/backup-sources/immich-library`, `/backup-sources/immich-profile`, and `/backup-sources/immich-upload` respectively. Each volume SHALL define its own cron schedule, backup mode, destination, and retention variables. The ML model cache volume is ephemeral and SHALL NOT be included.

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

### REQ-016: Both backup services have env.acc.example and env.prd.example
Both `backupServices/filedata/` and `backupServices/postgres/` SHALL provide `env.acc.example` and `env.prd.example`. Both files SHALL declare exactly the same variable names per service domain. Provider-specific path values SHALL be permitted to differ by environment and mode, and are not restricted to Dropbox for filedata services.

#### Scenario: env examples cover all registered services
- **GIVEN** `env.acc.example` and `env.prd.example` are compared for a backup service
- **WHEN** checking variable names
- **THEN** both files SHALL declare identical variable names for that backup service
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
`backupServices/filedata/docker-compose.prod.yml` for filedata.

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
- **THEN** the command SHALL be `docker compose -f docker-compose.prod.yml up -d`
- **AND** only `pihole_filedata`, `npm_filedata`, `vaultwarden_filedata`, and
  `freshrss_filedata` volumes SHALL be mounted

### REQ-019: Scoped compose files SHALL be self-contained and tracked on main
The remote PostgreSQL and prod filedata Compose files SHALL be fully valid, standalone
Docker Compose files that do not use `extends:` or `include:` to reference `docker-compose.yml`.
Both files SHALL remain versioned on the `main` branch.

#### Scenario: Remote compose files exist on main
- **GIVEN** the `main` branch
- **WHEN** the paths `backupServices/postgres/docker-compose.remote.yml` and
  `backupServices/filedata/docker-compose.prod.yml` are checked
- **THEN** both files SHALL exist and be valid Docker Compose Specification
  documents
- **AND** neither file SHALL reference `extends:` or `include:` directives

### REQ-020: Scoped backup profiles SHALL validate independently
Each remote PostgreSQL and prod filedata backup profile SHALL render successfully with `docker compose
config` without requiring the canonical default profile.

#### Scenario: Scoped compose configuration is independently valid
- **GIVEN** the operator is in the applicable backup service directory
- **WHEN** `docker compose -f docker-compose.remote.yml config` is run for PostgreSQL
  or `docker compose -f docker-compose.prod.yml config` is run for filedata
- **THEN** the command SHALL produce a valid Compose model
- **AND** it SHALL NOT require `docker-compose.yml` to be present or included

### REQ-021: Scoped backup profile changes SHALL remain deployment-scoped
Changes to a remote PostgreSQL or prod filedata backup profile SHALL affect only
services deployed to that profile and SHALL NOT enable default or Local profile jobs.

#### Scenario: Scoped profile addition preserves default and Local scope
- **GIVEN** a backup job is added to the remote PostgreSQL or prod filedata profile
- **WHEN** all backup profile Compose files are inspected
- **THEN** the changed profile SHALL contain only that profile's deployed jobs
- **AND** the default and Local profiles SHALL retain their documented service sets

### REQ-022: Paperless retained documents are registered with filedata-backup
The `paperless_filedata` volume SHALL be mounted read-only in `filedata-backup` at `/backup-sources/paperless`. The filedata backup service SHALL declare Paperless-specific schedule, Dropbox path, and retention variables in both `env.acc.example` and `env.prd.example`.

#### Scenario: Backup profiles preserve configuration during the category move
- **GIVEN** Paperless backup configuration exists before the move to Knowledge Services
- **WHEN** the default, Local, Remote PostgreSQL, and Prod filedata profiles are reviewed after the move
- **THEN** the default and Local profiles SHALL group Paperless entries under Knowledge Services
- **AND** existing Paperless backup modes, schedules, and remote destinations SHALL remain unchanged
- **AND** the Remote PostgreSQL and Prod filedata profiles SHALL NOT enable Paperless jobs

#### Scenario: Paperless media volume is mounted in filedata-backup
- **GIVEN** `backupServices/filedata/docker-compose.yml` is inspected
- **WHEN** the `filedata-backup` service volume mounts are reviewed
- **THEN** `paperless_filedata:/backup-sources/paperless:ro` SHALL be present
- **AND** the top-level `volumes:` block SHALL declare `paperless_filedata` with the standard named-volume pattern

#### Scenario: Paperless backup schedule variables are documented
- **GIVEN** `backupServices/filedata/env.acc.example` and `env.prd.example` are inspected
- **WHEN** Paperless entries are reviewed
- **THEN** `PAPERLESS_CRON_SCHEDULE`, `PAPERLESS_DROPBOX_PATH`, and `PAPERLESS_RETENTION_DAYS` SHALL be present in both files
- **AND** the Dropbox paths SHALL follow the account-specific example-file convention used by the repo

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
`docker-compose.local.yml` instead of `docker-compose.yml` for both
`backupServices/postgres/` and `backupServices/filedata/`.

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
- **THEN** the command SHALL be `docker compose -f docker-compose.local.yml up -d`
- **AND** the source volumes SHALL be `openwebui_filedata`, `romm_filedata`,
  `paperless_filedata`, `radicale_filedata`, `immich_library`, `immich_profile`,
  `immich_upload`, `jackett_filedata`, `radarr_filedata`, `sonarr_filedata`,
  `transmission_filedata`, and `npm_filedata`, in that order
- **AND** commented n8n and Syncthing mounts SHALL remain disabled
- **AND** the RomM source volume SHALL be read-only and its schedule SHALL use
  `ROMM_CRON_SCHEDULE`

#### Scenario: Local compose files exist and are self-contained
- **GIVEN** the `main` branch is inspected
- **WHEN** the paths `backupServices/postgres/docker-compose.local.yml` and
  `backupServices/filedata/docker-compose.local.yml` are checked
- **THEN** both files SHALL exist as valid standalone Docker Compose documents
- **AND** neither file SHALL reference `extends:` or `include:` directives

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
The filedata backup service SHALL register a single Syncthing archive backup lane for the `syncthing_filedata` configuration volume.

#### Scenario: Filedata compose includes Syncthing config lane
- **GIVEN** `backupServices/filedata/docker-compose.yml` is inspected
- **WHEN** the filedata-backup service volume mounts and cron command are reviewed
- **THEN** `syncthing_filedata` SHALL be mounted read-only at `/backup-sources/syncthing`
- **AND** a cron invocation for `/usr/local/bin/backup-script.sh syncthing` SHALL exist
- **AND** no `secondbrain` backup source or cron invocation SHALL be registered

### REQ-028: Syncthing Backup Uses Archive Mode With Daily Retention
The Syncthing filedata backup lane SHALL use `archive` backup mode, run daily, and retain backups for 7 days.

#### Scenario: Environment configuration enforces Syncthing archive policy
- **GIVEN** the tracked filedata backup environment examples are inspected
- **WHEN** Syncthing backup variables are reviewed
- **THEN** `SYNCTHING_BACKUP_MODE` SHALL be `archive`
- **AND** `SYNCTHING_CRON_SCHEDULE` SHALL declare a daily schedule
- **AND** `SYNCTHING_RETENTION_DAYS` SHALL be `7`
- **AND** no `SECONDBRAIN_*` backup variables SHALL be present

### REQ-029: Syncthing Backup Scope Is Default And Local Only
Syncthing backup registration SHALL be enabled in the default filedata profile,
retained as commented configuration in the Local profile, and absent from Prod.

#### Scenario: Profile scope matches Syncthing backup deployment
- **GIVEN** filedata compose profile files are compared
- **WHEN** Syncthing backup registration is reviewed
- **THEN** the Syncthing config lane SHALL be enabled in `docker-compose.yml`
- **AND** the Local Syncthing mount and volume declaration SHALL remain commented
- **AND** the Local profile SHALL NOT schedule Syncthing while its registration is disabled
- **AND** the Syncthing config lane SHALL be absent from `docker-compose.prod.yml`

### REQ-030: Backup Compose Entries Follow Category And Service Order
Both backup services SHALL group source-volume mounts, top-level source-volume
declarations, and cron jobs alphabetically by service category, then by service
name. Multiple volumes of one service SHALL be sorted by purpose suffix. This
layout SHALL apply to default, Local, Remote PostgreSQL, and Prod filedata compose files, including disabled
entries. Network references and declarations SHALL be sorted by network name.
Shared secrets mounts SHALL follow the grouped source volumes.

#### Scenario: Compose groups and generated crontab use matching categories
- **GIVEN** a backup compose profile contains enabled source-volume mounts and jobs
- **WHEN** its volume sections and generated crontab are inspected
- **THEN** volume sections SHALL use `## <Category> Services` comments
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
- **AND** environment examples, scripts where required, specs, and operator
  documentation SHALL be updated together
- **AND** adding the service SHALL NOT enable unrelated commented entries
- **AND** declaration order SHALL NOT change configured cron execution times

### REQ-031: Filedata Backup Modes Come From The Container Environment
Filedata compose profiles SHALL load per-volume backup modes through
`env_file: .env` and SHALL NOT duplicate them with startup `export` commands.
The backup script SHALL use `archive` when a mode is unset or empty.
Volumes requiring `sync-crypt`, including Immich and Paperless, SHALL have that
mode explicitly configured in the environment.

#### Scenario: Explicit mode is resolved by volume identifier
- **GIVEN** `IMMICH_LIBRARY_BACKUP_MODE=sync-crypt` is supplied to the container
- **WHEN** the backup script runs for `immich-library`
- **THEN** the script SHALL resolve the normalized environment key and select
  `sync-crypt` without a Compose startup export

#### Scenario: Missing mode uses the script fallback
- **GIVEN** a volume's backup mode is unset or empty
- **WHEN** its filedata backup job runs
- **THEN** the script SHALL select `archive`
- **AND** the Compose command SHALL NOT supply an implicit `sync-crypt` default

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
The default and Local filedata backup profiles SHALL mount `jackett_filedata` and `transmission_filedata` read-only and SHALL schedule separate encrypted archive jobs for each volume. The Prod profile SHALL NOT register either volume.

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
The default filedata backup profile SHALL register `jellyfin_filedata` as a read-only source at `/backup-sources/jellyfin` and SHALL back it up using the existing encrypted archive workflow. The profile SHALL NOT back up Jellyfin media-library bind mounts, downloads, transcodes, or cache. Jellyfin SHALL NOT be registered in Local or Prod filedata backup profiles unless those profiles deploy Jellyfin.

#### Scenario: Default filedata profile backs up Jellyfin configuration
- **GIVEN** the default filedata backup compose file and production environment example are inspected
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
Filedata backup profiles SHALL NOT register or schedule backups for OpenCode.
The OpenCode service SHALL NOT require OpenCode-specific backup settings in
the filedata environment examples.

#### Scenario: OpenCode has no filedata backup entry
- **GIVEN** the default, Local, and Prod filedata backup profiles are inspected
- **WHEN** their AI Services entries and environment examples are reviewed
- **THEN** no profile SHALL mount or schedule an OpenCode data backup
- **AND** the environment examples SHALL NOT define OpenCode backup settings
