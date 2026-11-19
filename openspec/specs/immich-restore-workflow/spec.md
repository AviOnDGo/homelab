## Requirements

### REQ-001: Dual-lane Immich recovery
The executable Immich restore script SHALL restore the three original-file
volumes from Mega crypt mirrors and the PostgreSQL dump from Dropbox.

#### Scenario: Operator restores Immich
- **GIVEN** the configured mirrors and encrypted database dump are available
- **WHEN** the operator runs `mediaServices/immich/restore.sh`
- **THEN** the script SHALL restore `immich_library`, `immich_profile`, and `immich_upload`
- **AND** it SHALL restore the database into `immich-db` before starting Immich

### REQ-002: Runtime database configuration
The restore SHALL obtain the database user and name from the database container
and SHALL NOT parse the service environment file.

#### Scenario: Nondefault database identity
- **GIVEN** the database container has a configured user and database name
- **WHEN** the script restores the dump
- **THEN** it SHALL use those runtime values

### REQ-003: Backup-container rclone
The restore SHALL use the existing running `filedata-backup` container's rclone
configuration for both file and database downloads.

#### Scenario: Recovery without host rclone
- **GIVEN** the backup container has working Mega, Mega crypt, and Dropbox remotes
- **WHEN** an operator restores Immich
- **THEN** host-installed rclone SHALL NOT be required

### REQ-004: Latest database artifact
The restore SHALL select the latest timestamped `immich_YYYY-MM-DD_HH-MM-SS.sql.zst.gpg` file.

#### Scenario: Mixed files in Dropbox
- **GIVEN** the database directory contains multiple files
- **WHEN** the script selects a dump
- **THEN** only matching encrypted dumps SHALL be considered
- **AND** the latest matching filename SHALL be selected

### REQ-005: Destructive action confirmation
The restore SHALL ask for explicit confirmation before replacing existing
target volumes and SHALL default to aborting.

#### Scenario: Existing targets
- **GIVEN** an Immich target volume exists
- **WHEN** the script requests confirmation
- **THEN** an empty or negative answer SHALL leave volume contents unchanged

### REQ-006: GPG passphrase
The restore SHALL prompt securely for the GPG passphrase when it is not supplied
in the environment.

#### Scenario: Missing passphrase
- **GIVEN** the preflight succeeds and `PASSPHRASE` is unset
- **WHEN** recovery starts
- **THEN** the script SHALL prompt for the passphrase without echoing it

### REQ-007: Backup containers and mounted volumes
The restore SHALL preserve the backup containers and mounted volume identities,
and SHALL refuse to modify volumes used by unrelated containers.

#### Scenario: Recovery fails after backup containers stop
- **GIVEN** the restore stopped one or both backup containers
- **WHEN** a later recovery step fails
- **THEN** the stopped containers SHALL remain stopped
- **AND** the remote mirrors SHALL NOT be updated by those containers

#### Scenario: Recovery succeeds
- **GIVEN** the restore stopped running backup containers
- **WHEN** the full stack starts successfully
- **THEN** the script SHALL restart those containers

### REQ-008: Immich integrity markers
The restore SHALL preserve restored markers and create missing markers for the
three recovered volumes and regenerated Immich directories.

#### Scenario: Generated data is absent
- **GIVEN** the original-file mirrors are restored
- **WHEN** the containers are created
- **THEN** marker files SHALL exist for library, profile, upload, thumbs,
  encoded-video, and backups before Immich starts

### REQ-009: Restore verification
The restore SHALL verify SQL connectivity and show Compose status.

#### Scenario: Database restore finishes
- **GIVEN** the SQL restore succeeded
- **WHEN** the script starts Immich
- **THEN** the database SHALL accept a SQL connection
- **AND** the script SHALL show Compose status

### REQ-010: Read-only preflight and staging
The restore SHALL check all mirror paths and select a database dump before
destructive operations. It SHALL refuse empty or unresolvable mirrors unless
the operator explicitly allows empty mirrors. It SHALL download all lanes and
verify dump decryption and compression before replacing volume contents.

#### Scenario: Preflight only
- **GIVEN** the backup container is running
- **WHEN** the operator runs `restore.sh --check-only`
- **THEN** the script SHALL check remote connectivity, mirror counts, and dump availability
- **AND** it SHALL NOT download backup data or change volumes

#### Scenario: Empty or missing mirror
- **GIVEN** a mirror resolves to zero objects
- **WHEN** recovery is attempted without an explicit empty-mirror override
- **THEN** the script SHALL fail before changing volumes

### REQ-011: Newer-client dump compatibility
The restore SHALL remove the `SET transaction_timeout = 0;` statement from the
dump header before the first `CREATE` or `COPY` statement. It SHALL NOT alter
table data and SHALL keep all other SQL errors fatal.

#### Scenario: PostgreSQL 18 dump restored into PostgreSQL 14
- **GIVEN** a dump created by a PostgreSQL 18 `pg_dump` client
- **AND** the Immich database server runs PostgreSQL 14
- **WHEN** the restore pipes the dump to `psql`
- **THEN** the header `SET transaction_timeout = 0;` statement SHALL be removed
- **AND** all subsequent schema and data lines SHALL reach `psql` unchanged

### REQ-012: Optional read-only host view of Immich uploads
The Immich restore guide SHALL document an optional persistent, read-only host bind mount of
`immich_upload` at `/mnt/immich_upload`, using the source path reported by
`docker volume inspect`. It SHALL state that the restore script does not create this host mount
and that Immich retains write access through its container mount.

#### Scenario: Operator configures a persistent host view
- **GIVEN** the Immich volume exists on the Docker host
- **WHEN** an operator follows the optional host-access instructions
- **THEN** `/etc/fstab` SHALL bind the volume mountpoint to `/mnt/immich_upload` as read-only
- **AND** the guide SHALL provide a command to verify the mount is read-only
- **AND** the host view SHALL reflect the restored volume contents without a restore-script step
