## Purpose
Define the canonical Paperless restore workflow for recovering the Google Drive crypt document
mirror and PostgreSQL state from backup.

## Requirements

### REQ-008: Successful recovery resumes the backup container
After successful recovery, the restore script SHALL start an existing stopped `filedata-backup`
container regardless of whether recovery stopped it. It SHALL leave an already-running container
untouched and SHALL report status-check or startup failures with a nonzero exit.

#### Scenario: Successful restore resumes scheduled backups
- **GIVEN** recovery has completed successfully and `filedata-backup` is stopped
- **WHEN** restore cleanup runs
- **THEN** the script SHALL start `filedata-backup`
- **AND** it SHALL verify that the container is running

#### Scenario: Failed restore does not restart backups
- **GIVEN** recovery failed or was cancelled
- **WHEN** restore cleanup runs
- **THEN** it SHALL NOT start `filedata-backup`
- **AND** it SHALL preserve any original failure exit status

### REQ-001: Paperless restore script is the operator entrypoint
The Paperless service SHALL provide an executable `restore.sh` beside `knowledgeServices/paperless/docker-compose.yml`, and the script SHALL be the primary operator entrypoint for restore operations.

#### Scenario: Restore entrypoint exists
- **GIVEN** the Paperless service directory is inspected
- **WHEN** the restore entrypoint is checked
- **THEN** `knowledgeServices/paperless/restore.sh` SHALL exist and be executable
- **AND** it SHALL live beside `docker-compose.yml`

### REQ-002: Paperless restore selects the database dump and protects destructive actions
The Paperless restore script SHALL restore filedata from the configured Google Drive crypt
`current/` tree and SHALL discover the latest `paperless` PostgreSQL dump by timestamped filename
order. If `paperless_filedata` or `paperless_postgresdata` already exists, the script SHALL prompt
before destructive recreation and SHALL NOT proceed without explicit confirmation.

#### Scenario: Latest backups are selected by timestamp
- **GIVEN** multiple timestamped backups exist in the configured Dropbox restore path
- **WHEN** the restore script scans available Paperless backups
- **THEN** the Google Drive crypt `current/` tree SHALL be selected for filedata
- **AND** the newest `paperless` SQL dump SHALL be selected from Dropbox

#### Scenario: Destructive actions require confirmation
- **GIVEN** `paperless_filedata` or `paperless_postgresdata` already exist
- **WHEN** restore preparation reaches volume recreation
- **THEN** the script SHALL prompt before removing or recreating them
- **AND** it SHALL exit without changes if the operator declines

### REQ-003: Paperless restore order is filedata first, database second, stack last
The restore script SHALL restore `paperless_filedata` before starting the database container. After filedata recovery, it SHALL start only `paperless-db`, wait for TCP readiness and a local SQL connection to the maintenance database, create the target database if absent, restore the SQL dump into `paperless_postgresdata`, verify a SQL connection to the restored database, and then bring up the remaining services while leaving `paperless_data`, `paperless_export`, and `paperless_consume` to be recreated by Docker Compose.

#### Scenario: Database initialization finishes before import
- **GIVEN** PostgreSQL is initializing a fresh data volume
- **WHEN** the temporary initialization server accepts Unix-socket connections
- **THEN** the restore SHALL continue waiting for TCP readiness and a successful local SQL query
- **AND** it SHALL check the target database through the `postgres` maintenance database
- **AND** it SHALL create the target database with the restore user as owner if absent
- **AND** it SHALL leave an existing target database intact before import

#### Scenario: SQL import errors stop recovery
- **GIVEN** the selected dump contains a SQL statement that fails
- **WHEN** the restore imports the dump
- **THEN** psql SHALL exit with a failure status
- **AND** the application stack SHALL NOT be started as a successful recovery

#### Scenario: Filedata precedes database restore
- **GIVEN** a full Paperless restore is executed
- **WHEN** restore steps begin
- **THEN** `paperless_filedata` SHALL be restored before PostgreSQL import begins
- **AND** `paperless-db` SHALL be the only container started for the database restore step
- **AND** the remaining services SHALL start only after the database restore succeeds

#### Scenario: Operational volumes are recreated by Compose
- **GIVEN** the restore script finishes the database recovery step
- **WHEN** the stack is brought back up
- **THEN** `paperless_data`, `paperless_export`, and `paperless_consume` SHALL be left for Docker Compose to recreate
- **AND** the script SHALL NOT attempt to restore those volumes from backup

### REQ-004: Paperless restore documents split recovery points
The restore guide SHALL state that filedata represents the latest successful Google Drive sync,
while PostgreSQL represents the selected dated Dropbox dump. It SHALL document re-consumption or
manual recovery for changes between those recovery points.

#### Scenario: Filedata mirror is restored before database import
- **GIVEN** the configured crypt remote contains Paperless data under `current/`
- **WHEN** the full restore workflow runs
- **THEN** the expanded tree SHALL be copied into `paperless_filedata` without a tar archive
- **AND** PostgreSQL import SHALL begin only after filedata restoration completes

### REQ-005: Paperless restore verifies filedata mirror content before any destructive action
The restore script SHALL verify that the configured Google Drive crypt `current/` path resolves
and contains at least one file before stopping the Paperless stack, prompting for destructive
volume recreation, or restoring the PostgreSQL dump. If the path is unresolvable or contains zero
files, the script SHALL abort immediately with an error identifying the checked path and SHALL
NOT modify any existing volume.

#### Scenario: Unresolvable or empty mirror aborts before any destructive action
- **GIVEN** the configured Google Drive crypt path for Paperless does not resolve, or resolves but
  contains zero files
- **WHEN** the restore script runs
- **THEN** the script SHALL abort with an error naming the checked path
- **AND** it SHALL exit before the Paperless stack is stopped
- **AND** it SHALL exit before `paperless_filedata` or `paperless_postgresdata` are removed or
  recreated
- **AND** it SHALL exit before the PostgreSQL dump is downloaded or restored

#### Scenario: Downloaded filedata mirror is re-verified before writing to the volume
- **GIVEN** the preflight mirror check passed
- **WHEN** the filedata restore step downloads the mirror into a local staging directory
- **THEN** the script SHALL verify the staging directory contains at least one file before
  copying it into `paperless_filedata`
- **AND** it SHALL fail the restore if the staging directory is empty

#### Scenario: Partial mirror download aborts recovery
- **GIVEN** some files have downloaded into the staging directory
- **WHEN** rclone reports a failed mirror transfer
- **THEN** the script SHALL abort before stopping the stack or modifying volumes
- **AND** it SHALL NOT treat a nonempty staging directory as a successful download

### REQ-006: Paperless rclone remotes are identified for disaster recovery
The Paperless restore guide SHALL identify `dropbox` as the PostgreSQL backup remote, `gdrive` as
the Google Drive backend, and `gdrive-crypt` as the crypt remote backed by `gdrive:`. The
filedata backup destination SHALL be `gdrive-crypt:paperless`, with the backup job writing the mirror
under `paperless/current/`. The restore script SHALL use `paperless` as the default relative path
within `gdrive-crypt`. The guide SHALL document the default Dropbox path and commands to verify the
configured remotes and backup paths without exposing credentials.

#### Scenario: Operator verifies Paperless backup remotes
- **GIVEN** an operator is preparing a Paperless disaster recovery
- **WHEN** the operator checks the restore guide and rclone configuration
- **THEN** the guide SHALL identify the `dropbox`, `gdrive`, and `gdrive-crypt` remote names
- **AND** it SHALL state that `gdrive-crypt` is backed by `gdrive:`
- **AND** it SHALL identify `gdrive-crypt:paperless/current/` as the filedata mirror path
- **AND** it SHALL identify `dropbox:/App_acc/paperless/` as the default PostgreSQL dump path
- **AND** it SHALL provide verification steps that do not require sharing credentials

### REQ-007: Paperless restore uses isolated backup credentials
The restore script SHALL default to executing rclone in the running `filedata-backup` container
without reading host credential files or copying the container configuration.
When `RCLONE_SOURCE=env` is explicitly selected, it SHALL load the required credentials from
`backupServices/filedata/.env`, with a `BACKUP_ENV_FILE` override. It SHALL generate a temporary
rclone configuration using the shared backup configuration helper and SHALL use it for all
restore rclone operations in that mode. It SHALL NOT read or modify the host rclone configuration, execute
the credential file as shell code, or fall back to interactive host configuration.

#### Scenario: Restore generates temporary remotes
- **GIVEN** `RCLONE_SOURCE=env` and the credential file contains the required original credentials
- **WHEN** restore preflight runs
- **THEN** the generated configuration SHALL contain Dropbox, Google Drive, and crypt remotes
- **AND** the crypt remote SHALL use the same password and optional salt as the backup
- **AND** the configuration SHALL be readable and writable only by its owner
- **AND** the temporary configuration SHALL be deleted when the restore exits

#### Scenario: Missing credentials fail without host fallback
- **GIVEN** `RCLONE_SOURCE=env` and the credential file is unreadable or lacks a required credential
- **WHEN** restore preflight runs
- **THEN** the script SHALL report the missing file or credential name without printing its value
- **AND** it SHALL abort before modifying volumes
- **AND** it SHALL NOT use host remotes as a substitute

#### Scenario: Container-backed downloads finish before services stop
- **GIVEN** the backup container has working remotes and is running
- **WHEN** the default restore downloads backups
- **THEN** filedata SHALL be staged in a unique temporary container directory and copied to the host
- **AND** the container staging directory SHALL be removed before the backup container is stopped
- **AND** database dumps SHALL be streamed to the host without exposing configuration

#### Scenario: Read-only preflight verifies the mirror without recovery
- **GIVEN** the operator invokes `./restore.sh --check-only`
- **WHEN** preflight checks complete
- **THEN** remote connectivity and a nonempty decrypted mirror SHALL have been verified
- **AND** the script SHALL exit without downloading backups, stopping services, or modifying volumes

### REQ-009: Optional read-only host view of Paperless media
The Paperless restore guide SHALL document an optional persistent, read-only host bind mount of
`paperless_filedata` at `/mnt/paperless_filedata`, using the source path reported by
`docker volume inspect`. It SHALL state that the restore script does not create this host mount,
that the volume contains media rather than the separate operational volumes, and that Paperless
retains write access through its container mount.

#### Scenario: Operator configures a persistent host view
- **GIVEN** the Paperless filedata volume exists on the Docker host
- **WHEN** an operator follows the optional host-access instructions
- **THEN** `/etc/fstab` SHALL bind the volume mountpoint to `/mnt/paperless_filedata` as read-only
- **AND** the guide SHALL provide a command to verify the mount is read-only
- **AND** the host view SHALL reflect the restored volume contents without a restore-script step