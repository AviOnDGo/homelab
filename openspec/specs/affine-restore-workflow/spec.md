## Requirements

### REQ-001: AFFiNE restore script is the operator entrypoint
The AFFiNE service SHALL provide an executable `restore.sh` beside `knowledgeServices/affine/docker-compose.yml`, and the script SHALL be the primary operator entrypoint for restore operations.

#### Scenario: Restore entrypoint exists
- **GIVEN** the AFFiNE service directory is inspected
- **WHEN** the restore entrypoint is checked
- **THEN** `knowledgeServices/affine/restore.sh` SHALL exist and be executable
- **AND** it SHALL live beside `docker-compose.yml`

### REQ-002: AFFiNE restore selects the latest backups and protects destructive actions
The AFFiNE restore script SHALL discover the latest `affine_*.tar.zst.gpg` file for filedata and the latest `affine_*.sql.zst.gpg` file for PostgreSQL from a configurable Dropbox remote and path. If `affine_filedata` or `affine_postgresdata` already exists, the script SHALL prompt before destructive recreation and SHALL NOT proceed without explicit confirmation.

#### Scenario: Latest backups are selected by timestamp
- **GIVEN** multiple timestamped backups exist in the configured Dropbox restore path
- **WHEN** the restore script scans available AFFiNE backups
- **THEN** the newest `affine` filedata archive SHALL be selected
- **AND** the newest `affine` SQL dump SHALL be selected

#### Scenario: Destructive actions require confirmation
- **GIVEN** `affine_filedata` or `affine_postgresdata` already exist
- **WHEN** restore preparation reaches volume recreation
- **THEN** the script SHALL prompt before removing or recreating them
- **AND** it SHALL exit without changes if the operator declines

### REQ-003: AFFiNE restore order is filedata first, database second, stack last
The restore script SHALL restore `affine_filedata` before starting `affine-db`. After filedata recovery, it SHALL start only `affine-db`, wait for PostgreSQL readiness with `pg_isready`, restore the SQL dump into `affine_postgresdata`, and then bring up the remaining services with `docker compose up -d`.

#### Scenario: Filedata precedes database restore
- **GIVEN** a full AFFiNE restore is executed
- **WHEN** restore steps begin
- **THEN** `affine_filedata` SHALL be restored before PostgreSQL import begins
- **AND** `affine-db` SHALL be the only container started for the database restore step
- **AND** the remaining services SHALL start only after the database restore succeeds

#### Scenario: Database readiness is verified before import
- **GIVEN** `affine-db` has been started for restore
- **WHEN** the restore script waits for PostgreSQL readiness
- **THEN** it SHALL use `pg_isready` against `affine-db`
- **AND** it SHALL not attempt the SQL restore until readiness succeeds

### REQ-004: AFFiNE restore guide is script-first with manual fallback
The `knowledgeServices/affine/RESTORE_GUIDE.md` file SHALL direct operators to use `restore.sh` as the primary restore path and SHALL retain a manual fallback section for situations where the scripted path is unavailable.

#### Scenario: Restore guide prefers the script
- **GIVEN** an operator opens the AFFiNE restore guide
- **WHEN** they look for the normal recovery flow
- **THEN** the guide SHALL point to `restore.sh` as the primary restore method
- **AND** the manual path SHALL be clearly marked as fallback only

### REQ-005: AFFiNE service documentation matches compose names
The `knowledgeServices/affine/SERVICE_DOCUMENTATION.md` file SHALL use the runtime container names and commands defined in `knowledgeServices/affine/docker-compose.yml`, including `affine`, `affine_migration`, `affine-cache`, and `affine-db`.

#### Scenario: Documentation matches compose file names
- **GIVEN** the AFFiNE compose file is inspected
- **WHEN** the service documentation is reviewed
- **THEN** the documented container names SHALL match the compose file
- **AND** the start, stop, log, and restore commands SHALL refer to the actual runtime names
