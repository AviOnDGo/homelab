## Requirements

### REQ-001: RomM service deployment
The system SHALL deploy RomM as the gaming library service under `gamingServices/romm/`, joined to `games_network`.

#### Scenario: RomM application container is configured
- **GIVEN** `gamingServices/romm/docker-compose.yml` is inspected
- **WHEN** reviewing the `romm` service definition
- **THEN** the service SHALL use the `rommapp/romm:latest` image
- **AND** the service key and `container_name` SHALL both be `romm`
- **AND** the restart policy SHALL be `unless-stopped`

#### Scenario: RomM joins the gaming network
- **GIVEN** `gamingServices/romm/docker-compose.yml` is inspected
- **WHEN** reviewing the top-level networks block
- **THEN** the default network SHALL be named `games_network`
- **AND** it SHALL be declared as `external: true`

### REQ-009: RomM PostgreSQL database
RomM SHALL use a companion PostgreSQL database container named `romm-db` with database connectivity configured through environment variables.

#### Scenario: RomM application targets PostgreSQL
- **GIVEN** `gamingServices/romm/docker-compose.yml` is inspected
- **WHEN** reviewing the `romm` service environment
- **THEN** `ROMM_DB_DRIVER` SHALL be set to `postgresql`
- **AND** `DB_HOST` SHALL be set to `romm-db`
- **AND** `DB_PORT` SHALL default to `5432`

#### Scenario: PostgreSQL database container is configured
- **GIVEN** `gamingServices/romm/docker-compose.yml` is inspected
- **WHEN** reviewing the `romm-db` service definition
- **THEN** the service SHALL use the `postgres:16` image
- **AND** `container_name` SHALL be set to `romm-db`
- **AND** `POSTGRES_DB`, `POSTGRES_USER`, and `POSTGRES_PASSWORD` SHALL be populated from the RomM database environment variables

#### Scenario: RomM waits for database readiness
- **GIVEN** `gamingServices/romm/docker-compose.yml` is inspected
- **WHEN** reviewing service dependencies and health checks
- **THEN** the `romm` service SHALL depend on `romm-db` with `condition: service_healthy`
- **AND** the `romm-db` service SHALL define a `pg_isready` health check using the configured database user and name

### REQ-010: RomM persistent storage
RomM SHALL persist application database state in PostgreSQL and store its library and assets in the external `romm_filedata` Docker volume.

#### Scenario: RomM library and assets use the filedata volume
- **GIVEN** `gamingServices/romm/docker-compose.yml` is inspected
- **WHEN** reviewing the `romm` service volumes list
- **THEN** `romm_filedata` SHALL be mounted at `/romm`
- **AND** the volume SHALL be declared external with the name `romm_filedata`
- **AND** `library/` and `assets/` SHALL be stored inside that volume

#### Scenario: RomM PostgreSQL volume is internally managed
- **GIVEN** `gamingServices/romm/docker-compose.yml` is inspected
- **WHEN** reviewing the top-level volumes block and `romm-db` service volumes
- **THEN** `romm_postgresdata` SHALL be declared with `name: romm_postgresdata`
- **AND** it SHALL NOT be declared as `external: true`
- **AND** it SHALL be mounted at `/var/lib/postgresql` in the `romm-db` container

### REQ-011: RomM metadata provider configuration
RomM SHALL expose environment variable hooks for IGDB, ScreenScraper, RetroAchievements, SteamGridDB, Hasheous, and application authentication configuration.

#### Scenario: Metadata provider variables are present
- **GIVEN** `gamingServices/romm/docker-compose.yml` is inspected
- **WHEN** reviewing the `romm` service environment
- **THEN** `IGDB_CLIENT_ID`, `IGDB_CLIENT_SECRET`, `SCREENSCRAPER_USER`, `SCREENSCRAPER_PASSWORD`, `RETROACHIEVEMENTS_API_KEY`, `STEAMGRIDDB_API_KEY`, and `HASHEOUS_API_ENABLED` SHALL be configurable
- **AND** `ROMM_AUTH_SECRET_KEY` SHALL be configurable for application authentication signing

### REQ-012: No direct host port exposure for RomM
The RomM application SHALL NOT map its web interface port to the host network interface. All external access SHALL be routed through Nginx Proxy Manager.

#### Scenario: RomM port mapping is not exposed to the host
- **GIVEN** `gamingServices/romm/docker-compose.yml` is inspected
- **WHEN** reviewing the `romm` service ports list
- **THEN** no active `ports:` entry SHALL map container port `8080` to a host port
- **AND** any such mapping SHALL be commented out with a note that access is via NPM

### REQ-013: RomM PostgreSQL backup integration (Local profile only)
The `romm_postgresdata` volume SHALL be registered for the Local PostgreSQL backup
profile only in `backupServices/postgres/backup-databases.conf`.

#### Scenario: romm_postgresdata appears in the Local Postgres backup
- **GIVEN** the Local PostgreSQL backup profile is generated
- **WHEN** reviewing the db-backup service volumes, networks, and cron entries
- **THEN** `romm_postgresdata` SHALL be mounted as a read-only backup source
- **AND** `db-backup` SHALL join `games_network`
- **AND** a dedicated `ROMM_CRON_SCHEDULE` cron entry SHALL exist

#### Scenario: RomM filedata backup is selected for default and Local
- **GIVEN** `backupServices/filedata/backup-volumes.conf` is inspected
- **WHEN** reviewing RomM's host selections
- **THEN** `romm_filedata` SHALL be selected for `default` and `local`
- **AND** its generated Gaming Services cron job SHALL run the `romm` backup job

#### Scenario: RomM PostgreSQL backup script supports RomM
- **GIVEN** `backupServices/postgres/backup-databases.conf`, the environment examples, and `db-backup-script.sh` are inspected
- **WHEN** reviewing the registered profiles and script cases
- **THEN** the Local profile SHALL reference `romm_postgresdata` and `games_network`
- **AND** the environment examples SHALL use `romm-db` as the database host
- **AND** the default and Prod profiles SHALL NOT reference `romm_postgresdata`
- **AND** `db-backup-script.sh` SHALL contain a `romm` case block

### REQ-014: RomM filedata synchronization to Filen
The Local filedata backup profile SHALL synchronize `romm_filedata` to Filen using the standard `sync-crypt` backup mode with dated deletion retention.

#### Scenario: RomM filedata is synced to Filen
- **GIVEN** Filen credentials and the shared rclone crypt password are configured
- **WHEN** the Local RomM filedata cron job executes
- **THEN** the standard filedata backup script SHALL sync the volume to `filen-crypt:/Romm/current/`
- **AND** replaced and deleted files SHALL be retained under `filen-crypt:/Romm/deleted-archive/YYYY-MM-DD/`
- **AND** retention SHALL be controlled by the RomM registry entry

#### Scenario: RomM sync requires populated library and assets
- **GIVEN** the Local RomM filedata backup job is configured with `sync-crypt`
- **WHEN** either `library/` or `assets/` is missing or contains no regular files
- **THEN** the backup script SHALL report a source-validation failure and exit non-zero
- **AND** it SHALL NOT run `rclone sync`

### REQ-015: Script-first RomM recovery
RomM SHALL provide an executable `gamingServices/romm/restore.sh` that restores filedata from Filen and the latest encrypted PostgreSQL dump from Dropbox before starting the application.

#### Scenario: Restore coordinates filedata and database recovery
- **GIVEN** the Filen backup, Dropbox PostgreSQL backup, credentials, and GPG passphrase are available
- **WHEN** the operator runs `./restore.sh` and confirms replacement of existing data
- **THEN** the script SHALL stop RomM and any running Local filedata backup container before synchronizing `romm_filedata` from the configured Filen `current/` tree
- **AND** it SHALL load the Local path file after the filedata credentials file
- **AND** it SHALL recreate `romm_postgresdata`, create the RomM containers, and start only `romm-db` before importing the dump
- **AND** it SHALL start RomM and the Local filedata backup service after successful recovery

#### Scenario: Restore waits for the final PostgreSQL server
- **GIVEN** PostgreSQL initialization starts a temporary Unix-socket-only server
- **WHEN** the restore script checks database readiness
- **THEN** it SHALL wait for `pg_isready` to succeed over TCP at `127.0.0.1` using the `postgres` maintenance database
- **AND** it SHALL NOT treat the temporary initialization server as ready for restore
- **AND** it SHALL exit non-zero if readiness is not reached within 60 attempts

#### Scenario: Restore prepares the configured target database
- **GIVEN** the final PostgreSQL server is ready
- **WHEN** the script prepares the database for SQL import
- **THEN** it SHALL query `pg_database` through the `postgres` maintenance database using the configured `DB_USER`
- **AND** it SHALL pass the database name as a safely quoted psql variable in SQL supplied through stdin
- **AND** it SHALL create the configured `DB_NAME` through the maintenance database if absent
- **AND** it SHALL preserve an existing target database during this preparation step

#### Scenario: Database preparation errors stop recovery
- **GIVEN** the database lookup or database creation fails
- **WHEN** the script prepares the target database
- **THEN** it SHALL report the failure and exit non-zero
- **AND** it SHALL NOT import the SQL dump or start the RomM application
