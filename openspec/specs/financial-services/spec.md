## Requirements

### REQ-001: Financial management service deployment
The system SHALL deploy Firefly III as the personal finance management application under `financialServices/firefly/`, joined to `finance_network`.

#### Scenario: Service is deployed from its canonical directory
- **GIVEN** the Firefly III stack is being deployed
- **WHEN** `docker compose up -d` is run in `financialServices/firefly/`
- **THEN** the firefly, firefly-db, and firefly-cron containers SHALL start
- **AND** all containers SHALL join `finance_network`

#### Scenario: NPM routes external traffic to Firefly
- **GIVEN** Firefly III is running
- **WHEN** a user accesses the Firefly domain via Nginx Proxy Manager
- **THEN** NPM SHALL proxy the request to `http://firefly:8080`
- **AND** the Firefly III web interface SHALL be displayed

### REQ-002: Three-service composition
The Firefly III stack SHALL consist of exactly three services: `firefly` (application), `firefly-db` (PostgreSQL database), and `firefly-cron` (scheduled task runner). All three SHALL be defined in `financialServices/firefly/docker-compose.yml`.

#### Scenario: firefly service naming
- **GIVEN** the Firefly III compose file is inspected
- **WHEN** reviewing the services block
- **THEN** the primary application service SHALL be named `firefly`
- **AND** the `container_name` SHALL be `firefly`

#### Scenario: firefly-db service naming
- **GIVEN** the Firefly III compose file is inspected
- **WHEN** reviewing the database service
- **THEN** the PostgreSQL service SHALL be named `firefly-db`
- **AND** the `container_name` SHALL be `firefly-db`

#### Scenario: firefly-cron service naming
- **GIVEN** the Firefly III compose file is inspected
- **WHEN** reviewing the cron service
- **THEN** the cron service SHALL be named `firefly-cron`
- **AND** the `container_name` SHALL be `firefly-cron`
- **AND** it SHALL declare `depends_on: [firefly, firefly-db]`

### REQ-003: Finance network isolation
All three Firefly services SHALL join `finance_network` via the default network shorthand. No service SHALL be reachable from outside `finance_network` except through NPM.

#### Scenario: Services communicate within finance_network
- **GIVEN** the firefly-cron service needs to send HTTP requests to the firefly service
- **WHEN** the cron job executes
- **THEN** it SHALL reference the application as `http://firefly:8080`
- **AND** no IP address SHALL be hardcoded

#### Scenario: Default network shorthand used
- **GIVEN** `financialServices/firefly/docker-compose.yml` is inspected
- **WHEN** reviewing the top-level networks block
- **THEN** it SHALL declare `default: name: finance_network  external: true`
- **AND** no service SHALL contain an explicit `networks:` key

### REQ-004: No direct host port exposure
The Firefly III application port SHALL NOT be mapped to the host interface. All external access SHALL be via NPM.

#### Scenario: Port 8080 is not exposed on the host
- **GIVEN** `financialServices/firefly/docker-compose.yml` is inspected
- **WHEN** reviewing port mappings
- **THEN** port 8080 of the firefly container SHALL NOT have an active host port mapping
- **AND** any `ports:` entry for port 8080 SHALL be commented out

### REQ-005: Credentials externalized via .env files
No plaintext secrets, passwords, or API keys SHALL appear in `docker-compose.yml`. Firefly application variables SHALL be sourced from `financialServices/firefly/.env` and database credentials SHALL be sourced from `financialServices/firefly/.db.env`.

#### Scenario: Firefly app credentials use env_file
- **GIVEN** `financialServices/firefly/docker-compose.yml` is inspected
- **WHEN** reviewing the firefly service definition
- **THEN** it SHALL declare `env_file: .env`
- **AND** no plaintext `APP_KEY`, `DB_PASSWORD`, or `STATIC_CRON_TOKEN` value SHALL appear in the compose file

#### Scenario: Database credentials use .db.env
- **GIVEN** `financialServices/firefly/docker-compose.yml` is inspected
- **WHEN** reviewing the firefly-db service definition
- **THEN** it SHALL declare `env_file: .db.env`
- **AND** no plaintext `POSTGRES_PASSWORD` value SHALL appear in the compose file

### REQ-006: PostgreSQL data persistence with non-external volume
The `firefly_postgresdata` named volume SHALL store all PostgreSQL data. This volume SHALL be declared without `external: true` to allow `docker compose create` to initialise it with correct permissions before the database starts.

#### Scenario: Volume is declared without external flag
- **GIVEN** `financialServices/firefly/docker-compose.yml` is inspected
- **WHEN** reviewing the top-level volumes block
- **THEN** `firefly_postgresdata` SHALL be declared with only its `name:` key
- **AND** `external: true` SHALL NOT be present on this volume

#### Scenario: Volume is mounted in firefly-db
- **GIVEN** the firefly-db service definition is inspected
- **WHEN** reviewing its volumes entry
- **THEN** `firefly_postgresdata` SHALL be mounted at `/var/lib/postgresql`

### REQ-007: Health checks on application and database
Both the `firefly` and `firefly-db` containers SHALL declare Docker health checks to enable dependent container start ordering and automated restart recovery.

#### Scenario: Firefly application health check
- **GIVEN** the firefly service definition is inspected
- **WHEN** reviewing the healthcheck block
- **THEN** it SHALL use `wget --quiet --tries=1 --spider http://localhost:8080/health` as the test command
- **AND** it SHALL define an `interval`, `timeout`, `retries`, and `start_period`

#### Scenario: Firefly database health check
- **GIVEN** the firefly-db service definition is inspected
- **WHEN** reviewing the healthcheck block
- **THEN** it SHALL use `pg_isready -U firefly` as the test command
- **AND** it SHALL define an `interval`, `timeout`, `retries`, and `start_period`

### REQ-008: Cron automation for scheduled financial tasks
The `firefly-cron` service SHALL run a daily cron job at 03:00 to trigger Firefly's scheduled task endpoint. The cron token SHALL be sourced from the `.env` file and SHALL NOT be hardcoded in the compose file command.

#### Scenario: Cron references firefly service by name
- **GIVEN** the firefly-cron service command is inspected
- **WHEN** reviewing the wget call
- **THEN** it SHALL target `http://firefly:8080/api/v1/cron/` using the service DNS name
- **AND** no IP address SHALL be used

#### Scenario: Cron schedule is daily at 03:00
- **GIVEN** the firefly-cron service is running
- **WHEN** the cron schedule is inspected inside the container
- **THEN** it SHALL execute at `0 3 * * *`

### REQ-009: Watchtower opt-out for database and cron containers
The `firefly-db` and `firefly-cron` containers SHALL opt out of Watchtower automatic updates via the `com.centurylinklabs.watchtower.enable=false` label to prevent unsupervised database or cron image changes.

#### Scenario: firefly-db has Watchtower exclusion label
- **GIVEN** `financialServices/firefly/docker-compose.yml` is inspected
- **WHEN** reviewing the firefly-db service labels
- **THEN** `com.centurylinklabs.watchtower.enable: "false"` SHALL be present
- **AND** Watchtower SHALL skip this container during automated update cycles

#### Scenario: firefly-cron has Watchtower exclusion label
- **GIVEN** `financialServices/firefly/docker-compose.yml` is inspected
- **WHEN** reviewing the firefly-cron service labels
- **THEN** `com.centurylinklabs.watchtower.enable: "false"` SHALL be present

### REQ-010: Backup integration with postgres backup service
The `firefly_postgresdata` volume SHALL be registered with `backupServices/postgres/` to ensure financial transaction data is backed up on schedule.

#### Scenario: firefly database is backed up
- **GIVEN** the postgres backup service is running
- **WHEN** the scheduled backup cron job runs for the firefly database
- **THEN** a GPG-encrypted `pg_dump` backup of the firefly database SHALL be created
- **AND** uploaded to the configured cloud storage target

#### Scenario: backup service mounts the firefly volume
- **GIVEN** `backupServices/postgres/docker-compose.yml` is inspected
- **WHEN** reviewing the db-backup service volumes
- **THEN** `firefly_postgresdata` SHALL be mounted read-only for backup access

### REQ-011: Service documentation requirements
The `financialServices/firefly/` directory SHALL contain `SERVICE_DOCUMENTATION.md` and `RESTORE_GUIDE.md`.

#### Scenario: SERVICE_DOCUMENTATION.md is present
- **GIVEN** `financialServices/firefly/` is listed
- **WHEN** checking for documentation files
- **THEN** `SERVICE_DOCUMENTATION.md` SHALL exist
- **AND** it SHALL document architecture, configuration, operational commands, and troubleshooting

#### Scenario: RESTORE_GUIDE.md is present
- **GIVEN** `financialServices/firefly/` is listed
- **WHEN** checking for restore documentation
- **THEN** `RESTORE_GUIDE.md` SHALL exist
- **AND** it SHALL document the PostgreSQL restore procedure and cron verification steps

### REQ-012: Compose standards audit covers security controls
The homelab audit procedure SHALL verify that all `docker-compose.yml` files externalize secrets. No plaintext passwords, API keys, or tokens SHALL appear as literal string values in any compose file.

#### Scenario: Hardcoded secret is flagged as critical
- **GIVEN** a compose file audit is performed across all service directories
- **WHEN** a plaintext credential is found in an `environment:` block
- **THEN** the finding SHALL be classified as critical severity
- **AND** it SHALL require immediate remediation before the service is considered production-ready

#### Scenario: Externalized credentials pass audit
- **GIVEN** a compose file uses `${VAR_NAME}` substitution or `env_file: .env` for all credentials
- **WHEN** the security audit check is performed
- **THEN** the check SHALL pass with no credential findings

### REQ-013: Compose standards audit covers network isolation
The audit SHALL verify that every service joins its category network with `external: true`, no service exposes ports directly to the host for externally accessible endpoints, and NPM acts as the sole ingress gateway.

#### Scenario: Direct host port exposure is flagged
- **GIVEN** a compose file has an active `ports:` mapping for an externally accessible service
- **WHEN** the network audit check is performed
- **THEN** the finding SHALL be classified as high severity
- **AND** the recommended remediation SHALL be to comment out the port mapping and configure an NPM proxy host

#### Scenario: Network declared as external passes audit
- **GIVEN** a compose file declares its category network with `external: true`
- **WHEN** the network isolation check is performed
- **THEN** the check SHALL pass for that service

### REQ-014: Compose standards audit covers data persistence
The audit SHALL verify that all stateful data paths use external named Docker volumes, not anonymous volumes or bind mounts to uncontrolled host paths.

#### Scenario: Named external volume passes audit
- **GIVEN** a service mounts a named external volume for its stateful data
- **WHEN** the persistence audit is performed
- **THEN** the check SHALL pass for that service

#### Scenario: Anonymous or implicit volume is flagged
- **GIVEN** a service's compose file relies on an anonymous volume or does not declare the volume as external
- **WHEN** the persistence audit is performed
- **THEN** the finding SHALL be classified as medium severity (backup scope is non-deterministic)

### REQ-015: Compose standards audit covers restart policy
The audit SHALL verify that all services declare `restart: unless-stopped`. No service SHALL use `restart: always` (which prevents intentional stops from persisting across daemon restarts) without documented justification.

#### Scenario: Service uses restart: unless-stopped passes audit
- **GIVEN** a service declares `restart: unless-stopped`
- **WHEN** the restart policy audit is performed
- **THEN** the check SHALL pass for that service

#### Scenario: Service uses restart: always is flagged
- **GIVEN** a service declares `restart: always` without a documented justification comment
- **WHEN** the restart policy audit is performed
- **THEN** the finding SHALL be classified as low severity with a recommendation to switch to `unless-stopped`

### REQ-016: Compose standards audit covers backup registration
The audit SHALL verify that all services with named external volumes are registered in the appropriate backup pipeline (`backupServices/postgres/` for databases, `backupServices/filedata/` for application data).

#### Scenario: Volume registered in backup pipeline passes audit
- **GIVEN** a named external volume is mounted in a backup service's volumes list
- **WHEN** the backup registration audit is performed
- **THEN** the check SHALL pass for that volume

#### Scenario: Unregistered stateful volume is flagged as critical
- **GIVEN** a service uses a named external volume that does not appear in any backup pipeline configuration
- **WHEN** the backup registration audit is performed
- **THEN** the finding SHALL be classified as critical severity
- **AND** backup registration SHALL be required before the service is considered production-ready

### REQ-017: Firefly automated restore script workflow
The Firefly service SHALL provide a restore script that restores the PostgreSQL database from the latest Dropbox backup and enforces an operator-confirmed volume handling flow.

#### Scenario: Latest backup is selected from Dropbox
- **GIVEN** the restore script starts with Dropbox credentials and backup path configured
- **WHEN** the restore script begins backup discovery
- **THEN** it SHALL discover backup files only from the configured Dropbox Firefly backup path
- **AND** it SHALL select the latest matching backup file automatically

#### Scenario: Empty Dropbox backup set fails fast
- **GIVEN** the configured Dropbox Firefly backup path contains no matching backup files
- **WHEN** the restore script evaluates available backups
- **THEN** the restore script SHALL exit with a non-zero status immediately
- **AND** it SHALL print an actionable error message

#### Scenario: Existing volume prompts for operator decision
- **GIVEN** `firefly_postgresdata` already exists
- **WHEN** restore preparation reaches volume handling
- **THEN** the restore script SHALL prompt the operator to choose between remove-and-recreate or keep existing volume
- **AND** the default choice SHALL be remove-and-recreate

#### Scenario: Volume absent skips choice prompt
- **GIVEN** `firefly_postgresdata` does not exist
- **WHEN** restore preparation reaches volume handling
- **THEN** the restore script SHALL NOT ask the keep-vs-recreate question
- **AND** it SHALL proceed with restore preparation

#### Scenario: Keep existing volume means skip-restore
- **GIVEN** the operator chooses to keep the existing volume
- **WHEN** the restore script evaluates the selected volume action
- **THEN** the restore script SHALL skip database import
- **AND** it SHALL start the full Firefly stack

#### Scenario: Recreate volume performs restore
- **GIVEN** the operator chooses remove-and-recreate
- **WHEN** the restore script executes the restore path
- **THEN** the restore script SHALL recreate `firefly_postgresdata`, create containers, and start only `firefly-db` before import
- **AND** it SHALL decrypt and decompress the selected backup and import it into the Firefly database

#### Scenario: Canonical restore target uses firefly-db
- **GIVEN** the restore script performs database operations
- **WHEN** it runs restore or readiness commands
- **THEN** it SHALL target the `firefly-db` container name for restore and readiness checks
- **AND** it SHALL NOT rely on legacy container aliases

#### Scenario: Readiness verification uses pg_isready
- **GIVEN** restore import completes successfully
- **WHEN** post-import validation runs
- **THEN** the restore script SHALL verify database readiness using `pg_isready`
- **AND** successful readiness SHALL be treated as restore verification completion

#### Scenario: Full stack starts after restore path success
- **GIVEN** the selected restore path completes successfully
- **WHEN** the restore script reaches finalization
- **THEN** the restore script SHALL start the full Firefly stack with `docker compose up -d`
- **AND** it SHALL leave the service in running state
