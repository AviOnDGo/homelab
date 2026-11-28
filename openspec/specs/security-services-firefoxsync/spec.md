## Purpose
Define Firefox Sync-specific service topology, runtime behavior, persistence, and recovery references.

## Requirements

### REQ-001: Firefox Sync uses a two-container topology with startup gating
Firefox Sync SHALL run as `syncserver` plus `firefoxsync-db`, and `syncserver` SHALL depend on a healthy `firefoxsync-db` using `depends_on` with `condition: service_healthy`.

#### Scenario: Database starts before syncserver
- **GIVEN** Firefox Sync compose deployment is started
- **WHEN** Docker resolves service startup order
- **THEN** `firefoxsync-db` SHALL pass healthcheck before `syncserver` starts
- **AND** syncserver SHALL not start against an unready database

### REQ-002: Firefox Sync containers do not set TZ in compose
Neither `syncserver` nor `firefoxsync-db` SHALL set `TZ` in their compose environment blocks.

#### Scenario: Timezone is host-derived
- **GIVEN** `securityServices/firefoxsync/docker-compose.yml` is inspected
- **WHEN** environment blocks are reviewed
- **THEN** no `TZ` key SHALL be present for these services
- **AND** timezone behavior SHALL be inherited from host runtime settings

### REQ-003: Firefox Sync persistence and exposure model is fixed
The database SHALL use named volume `firefoxsync_postgresdata` without `external: true`, and syncserver port 8000 SHALL NOT be directly exposed on the host.

#### Scenario: Volume and port contract is met
- **GIVEN** the Firefox Sync compose file is inspected
- **WHEN** volumes and ports are reviewed
- **THEN** `firefoxsync_postgresdata` SHALL be internally managed by compose
- **AND** external access SHALL occur via NPM rather than host-published 8000

### REQ-004: Firefox Sync sync behavior persists user data
Firefox Sync SHALL provide synchronization for supported Firefox data and SHALL preserve synced data across container restarts.

#### Scenario: Synced data persists
- **GIVEN** a browser has synchronized data to the self-hosted endpoint
- **WHEN** Firefox Sync containers are restarted
- **THEN** previously synced data SHALL remain available
- **AND** user sync continuity SHALL be preserved

### REQ-005: Firefox Sync restore procedure is externally defined
Firefox Sync SHALL provide `restore.sh`, and the canonical PostgreSQL restore workflow details SHALL be defined in `openspec/specs/security-services-restore-scripts/spec.md`.

#### Scenario: Restore reference is available
- **GIVEN** an operator needs to recover Firefox Sync state
- **WHEN** they consult security service specifications
- **THEN** `securityServices/firefoxsync/restore.sh` SHALL exist
- **AND** the authoritative restore flow SHALL be documented in the security restore scripts spec

### REQ-006: Firefox Sync database uses the service identifier
Firefox Sync SHALL use the `firefoxsync` database on `firefoxsync-db`.

#### Scenario: Application and backup target the same database
- **GIVEN** Firefox Sync and its PostgreSQL backup are configured
- **WHEN** their database connections are reviewed
- **THEN** both SHALL target the `firefoxsync` database on `firefoxsync-db`
- **AND** restore procedures SHALL restore into `firefoxsync`
