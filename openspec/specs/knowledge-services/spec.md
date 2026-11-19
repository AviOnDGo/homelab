## Requirements

### REQ-005: FreshRSS Feed Aggregation
The knowledge services stack SHALL provide a self-hosted RSS/Atom feed aggregator through a FreshRSS container named `freshrss` at `knowledgeServices/freshrss/`.

#### Scenario: FreshRSS serves feed reader interface
- **GIVEN** the `freshrss` container is running and connected to `knowledge_network`
- **WHEN** a user accesses the FreshRSS service
- **THEN** the FreshRSS web interface SHALL be presented
- **AND** users SHALL be able to subscribe to, read, and manage RSS/Atom feeds

#### Scenario: FreshRSS has no direct host port exposure
- **GIVEN** the `freshrss` container is running
- **WHEN** the compose file is inspected
- **THEN** port 80 SHALL NOT be directly mapped to the host interface
- **AND** all external access SHALL be routed via Nginx Proxy Manager

### REQ-006: Knowledge Network Isolation
All knowledge services SHALL connect exclusively to the `knowledge_network` Docker network,
except the Paperless webserver, which SHALL additionally join `ai_network` for AI integrations.
Paperless supporting services SHALL connect only to `knowledge_network`.

#### Scenario: Knowledge services communicate within knowledge_network
- **GIVEN** two knowledge service containers are running
- **WHEN** a service-to-service request is made
- **THEN** the communication SHALL occur within `knowledge_network`
- **AND** no cross-network leakage to other category networks SHALL occur

#### Scenario: Paperless AI access is limited to the webserver
- **GIVEN** the Paperless stack is deployed
- **WHEN** its network attachments are inspected
- **THEN** only `paperless` SHALL additionally join `ai_network`
- **AND** no Paperless stack container SHALL join `media_network`

### REQ-007: Named External Volume Persistence
All knowledge services with persistent state SHALL store data in named external Docker volumes,
except explicitly specified internally managed named volumes. Paperless SHALL retain its
internally managed `paperless_postgresdata`, `paperless_data`, `paperless_export`, and
`paperless_consume` volumes and its external `paperless_filedata` volume. Host bind-mounts
using environment variable paths SHALL NOT be used.

#### Scenario: Volumes survive compose down
- **GIVEN** a knowledge service has data in its named external volume
- **WHEN** `docker compose down` is run
- **THEN** the external volume SHALL be preserved
- **AND** all user data SHALL remain intact for the next `docker compose up`

### REQ-008: Knowledge Services Backup Integration
Each knowledge service with persistent data SHALL have its storage volume registered with
`backupServices/filedata` before the deployment is considered production-ready. Paperless SHALL
register its retained document volume with filedata backups and its PostgreSQL database with
database backups; its rebuildable and operational volumes SHALL follow the exclusions in
`paperless-restore-workflow`.

#### Scenario: Unregistered volume makes deployment incomplete
- **GIVEN** a knowledge service is deployed but its volume is not registered in `backupServices/filedata`
- **WHEN** the deployment is assessed
- **THEN** it SHALL be considered incomplete
- **AND** the operator SHALL add backup configuration before the service is production-ready

### REQ-013: AFFiNE Stack Service Composition
The AFFiNE stack SHALL deploy four containers: `affine_server` (primary), `affine_migration_job` (one-shot migration), `affine-cache`, and `affine-db`, all connected to `knowledge_network`.

#### Scenario: All AFFiNE containers are running
- **GIVEN** `docker compose up -d` is run in `knowledgeServices/affine/`
- **WHEN** `docker compose ps` is checked
- **THEN** `affine_server`, `affine_migration_job`, `affine-cache`, and `affine-db` SHALL be present
- **AND** all SHALL be connected to `knowledge_network`

### REQ-014: AFFiNE Port Exposure via NPM Only
The AFFiNE server port (`3010`) SHALL NOT be directly bound on the host; access SHALL be routed exclusively through Nginx Proxy Manager.

#### Scenario: Port 3010 is not bound on the host
- **GIVEN** the AFFiNE stack is running
- **WHEN** host port bindings are inspected
- **THEN** no process SHALL be listening on port 3010 directly
- **AND** AFFiNE SHALL be accessible exclusively via the NPM proxy host

### REQ-015: AFFiNE Redis Pinned Image
The `affine-cache` service SHALL use a pinned, versioned image tag (e.g., `redis:7.2-alpine`) rather than the untagged `redis` image.

#### Scenario: Redis image tag is explicit and versioned
- **GIVEN** `knowledgeServices/affine/docker-compose.yml` is inspected
- **WHEN** the `affine-cache` service image is reviewed
- **THEN** the image SHALL specify a version tag
- **AND** SHALL NOT use the bare `redis` image without a tag

### REQ-016: AFFiNE PostgreSQL Password-Only Authentication
The `affine-db` service SHALL NOT include `POSTGRES_HOST_AUTH_METHOD: trust`; all database access SHALL be authenticated via password.

#### Scenario: Trust authentication is absent
- **GIVEN** `knowledgeServices/affine/docker-compose.yml` is inspected
- **WHEN** the `affine-db` service environment is reviewed
- **THEN** `POSTGRES_HOST_AUTH_METHOD: trust` SHALL NOT be present
- **AND** all connections SHALL require password authentication

### REQ-017: AFFiNE Named Volumes
The AFFiNE stack SHALL store all persistent data in named Docker volumes following the `affine_<purpose>` naming convention. The application data volume (`affine_filedata`) SHALL be declared as `external: true`. The PostgreSQL data volume (`affine_postgresdata`) SHALL be declared as an internal named volume without `external: true`, following repository-conventions REQ-020.

#### Scenario: AFFiNE application volumes are external and named
- **GIVEN** the AFFiNE stack is deployed
- **WHEN** `docker volume ls` is run
- **THEN** the volume named `affine_filedata` SHALL exist
- **AND** it SHALL be declared with `external: true` in the compose file

#### Scenario: AFFiNE postgres volume is an internal named volume
- **GIVEN** the AFFiNE stack is deployed
- **WHEN** the top-level `volumes:` block is inspected
- **THEN** `affine_postgresdata` SHALL be declared without `external: true`
- **AND** `docker compose up` SHALL create the volume automatically if it does not exist

### REQ-018: AFFiNE TZ Environment Variable
Every service in the AFFiNE stack SHALL include `TZ: UTC` in its `environment:` block.

#### Scenario: TZ is set on all AFFiNE services
- **GIVEN** `knowledgeServices/affine/docker-compose.yml` is inspected
- **WHEN** the environment sections of all services are reviewed
- **THEN** every service entry SHALL contain `TZ: UTC`

### REQ-019: AFFiNE setup_affine.sh Setup Script Pattern
The `setup_affine.sh` script SHALL create the `affine_filedata` and `affine_postgresdata` external Docker volumes before invoking `docker compose up -d`, and SHALL NOT reference podman.

#### Scenario: Script creates volumes before starting services
- **GIVEN** `setup_affine.sh` is executed
- **WHEN** the script runs
- **THEN** `affine_filedata` and `affine_postgresdata` SHALL be created via `docker volume create` before `docker compose up -d` is called

#### Scenario: Script uses Docker, not Podman
- **GIVEN** `setup_affine.sh` is inspected
- **WHEN** the script contents are reviewed
- **THEN** no `podman` commands SHALL appear

### REQ-020: AFFiNE filedata backup registration
The AFFiNE filedata volume SHALL be mounted read-only in `backupServices/filedata/docker-compose.local.yml` at `/backup-sources/affine`, and the corresponding `AFFINE_*` environment variables SHALL be declared in both `env.acc.example` and `env.prd.example`.

#### Scenario: Local backup profile includes AFFiNE filedata
- **GIVEN** `backupServices/filedata/docker-compose.local.yml` is inspected
- **WHEN** the `filedata-backup` service volumes and cron entries are reviewed
- **THEN** `affine_filedata` SHALL be mounted read-only at `/backup-sources/affine`
- **AND** a cron entry using `AFFINE_CRON_SCHEDULE` SHALL be present

#### Scenario: AFFiNE filedata env examples are complete
- **GIVEN** `backupServices/filedata/env.acc.example` and `backupServices/filedata/env.prd.example` are inspected
- **WHEN** the AFFiNE variables are reviewed
- **THEN** both files SHALL declare `AFFINE_DROPBOX_PATH`, `AFFINE_RETENTION_DAYS`, and `AFFINE_CRON_SCHEDULE`

### REQ-021: AFFiNE Service Documentation
The `knowledgeServices/affine/` directory SHALL contain both `SERVICE_DOCUMENTATION.md` and `RESTORE_GUIDE.md`.

#### Scenario: AFFiNE documentation files are present
- **GIVEN** the AFFiNE service directory is inspected
- **WHEN** `ls knowledgeServices/affine/` is run
- **THEN** both `SERVICE_DOCUMENTATION.md` and `RESTORE_GUIDE.md` SHALL be listed

### REQ-022: FreshRSS Named External Volume
The FreshRSS service SHALL store all persistent data in the named external Docker volume `freshrss_filedata` mounted at `/var/www/FreshRSS` inside the container.

#### Scenario: FreshRSS volume is external and follows naming convention
- **GIVEN** the FreshRSS service is deployed
- **WHEN** `docker volume ls` is run
- **THEN** `freshrss_filedata` SHALL exist and be mounted by the `freshrss` container

#### Scenario: Data survives container recreation
- **GIVEN** user feeds and read state exist in `freshrss_filedata`
- **WHEN** the container is recreated with `docker compose up -d --force-recreate`
- **THEN** all subscribed feeds and read/unread state SHALL be preserved

### REQ-023: FreshRSS Environment Configuration Inlined
The FreshRSS service SHALL define all required environment variables directly in `docker-compose.yml`; no `env_file` directive SHALL be present.

#### Scenario: TZ and CRON_MIN are inlined in compose
- **GIVEN** `knowledgeServices/freshrss/docker-compose.yml` is inspected
- **WHEN** the `freshrss` service environment section is reviewed
- **THEN** `TZ: UTC` and `CRON_MIN` SHALL be declared inline
- **AND** no `env_file:` directive SHALL be present

### REQ-024: FreshRSS Service Documentation
The `knowledgeServices/freshrss/` directory SHALL contain both `SERVICE_DOCUMENTATION.md` and `RESTORE_GUIDE.md`.

#### Scenario: FreshRSS documentation files are present
- **GIVEN** the FreshRSS service directory is inspected
- **WHEN** `ls knowledgeServices/freshrss/` is run
- **THEN** both `SERVICE_DOCUMENTATION.md` and `RESTORE_GUIDE.md` SHALL be listed

### REQ-025: FreshRSS Restart Policy
The FreshRSS container SHALL use `restart: unless-stopped`.

#### Scenario: FreshRSS restart policy is set
- **GIVEN** the `freshrss` container is inspected
- **WHEN** the `RestartPolicy.Name` field is checked
- **THEN** it SHALL equal `unless-stopped`

### REQ-026: FreshRSS Backup Registration
The `freshrss_filedata` volume SHALL be registered with `backupServices/filedata` before the FreshRSS deployment is considered production-ready.

#### Scenario: Backup registration is present
- **GIVEN** `backupServices/filedata/docker-compose.yml` is inspected
- **WHEN** the volumes and cron configuration are reviewed
- **THEN** `freshrss_filedata` SHALL be listed as an external volume mounted at `/backup-sources/freshrss:ro`
- **AND** a cron entry for FreshRSS backup SHALL be present

### REQ-027: Radicale CalDAV/CardDAV Synchronization Service
The knowledge services stack SHALL provide a self-hosted CalDAV and CardDAV calendar and contact synchronization server through a Radicale container named `radicale` deployed at `knowledgeServices/radicale/`.

#### Scenario: Radicale serves CalDAV and CardDAV interface
- **GIVEN** the `radicale` container is running and connected to `knowledge_network`
- **WHEN** a client accesses the Radicale service endpoint
- **THEN** Radicale SHALL respond with standard WebDAV/CalDAV/CardDAV capabilities
- **AND** users SHALL be able to synchronize calendars, tasks, and contact collections

#### Scenario: Radicale uses external named volume persistence
- **GIVEN** Radicale stores calendars, contacts, user authentication, and configuration
- **WHEN** inspect commands or compose files are reviewed
- **THEN** all data SHALL be stored in the named external Docker volume `radicale_filedata`
- **AND** host bind-mounts using raw environment variable paths SHALL NOT be used

#### Scenario: Radicale has no direct host port exposure
- **GIVEN** the `radicale` container is running
- **WHEN** `knowledgeServices/radicale/docker-compose.yml` is inspected
- **THEN** port 5232 SHALL NOT be directly mapped to host network interfaces
- **AND** all external access SHALL be routed through Nginx Proxy Manager over `knowledge_network`

#### Scenario: Radicale volume registered with backup services
- **GIVEN** Radicale holds persistent state in `radicale_filedata`
- **WHEN** `backupServices/filedata/docker-compose.yml` is inspected
- **THEN** `radicale_filedata` SHALL be mounted at `/backup-sources/radicale:ro`
- **AND** a dedicated `${RADICALE_CRON_SCHEDULE}` cron job SHALL execute automated backups

### REQ-028: Paperless Credentials via env_file
The Paperless webserver and database SHALL load credentials and sensitive configuration
from `env_file: .env`; the Compose file SHALL NOT contain plaintext secrets.

#### Scenario: Compose configuration keeps credentials external
- **GIVEN** `knowledgeServices/paperless/docker-compose.yml` is inspected
- **WHEN** webserver and database configuration is reviewed
- **THEN** both services SHALL declare `env_file: .env`
- **AND** plaintext credentials SHALL NOT appear in the Compose file

### REQ-029: Paperless Named Volume Continuity
The Paperless stack SHALL retain the Compose project name `paperless` and the existing
volumes `paperless_postgresdata`, `paperless_filedata`, `paperless_data`,
`paperless_export`, and `paperless_consume`. The database volume SHALL be internally
managed with `name: paperless_postgresdata` and SHALL NOT use `external: true`.

#### Scenario: Moving the service directory preserves all data volumes
- **GIVEN** Paperless has existing named volumes on the same Docker host
- **WHEN** the stack is deployed from `knowledgeServices/paperless/`
- **THEN** the containers SHALL mount the same five volumes at their existing paths
- **AND** container names, credentials, and document count SHALL remain unchanged
- **AND** a directory move SHALL NOT require a restore or a new database volume

### REQ-030: Paperless Database Watchtower Exclusion
The `paperless-db` service SHALL carry `com.centurylinklabs.watchtower.enable=false`
to prevent automatic PostgreSQL major-version upgrades.

#### Scenario: Watchtower leaves the database unchanged
- **GIVEN** a Watchtower update cycle runs
- **WHEN** it evaluates `paperless-db`
- **THEN** it SHALL NOT restart or update the database container

### REQ-031: Paperless Knowledge Network Placement
All five Paperless stack services SHALL explicitly join external `knowledge_network`.
Only the webserver SHALL additionally join external `ai_network`. Paperless SHALL NOT
join `media_network` or expose port 8000 directly on the host.

#### Scenario: Paperless is reachable through the Knowledge gateway
- **GIVEN** Paperless and Nginx Proxy Manager are running
- **WHEN** Nginx Proxy Manager forwards a request to `paperless:8000`
- **THEN** Paperless SHALL respond through `knowledge_network`
- **AND** all five Paperless containers SHALL be absent from `media_network`

### REQ-032: Paperless Documentation Files
The `knowledgeServices/paperless/` directory SHALL contain `SERVICE_DOCUMENTATION.md`,
`RESTORE_GUIDE.md`, and an executable `restore.sh`.

#### Scenario: Documentation and restore entrypoint move with the service
- **GIVEN** the Paperless service directory is inspected
- **WHEN** its documentation and scripts are checked
- **THEN** both documentation files and executable `restore.sh` SHALL be present

### REQ-033: Paperless Script-First Recovery
The Paperless restore guide SHALL direct operators to `restore.sh` as the primary path
and SHALL document manual fallback steps. It SHALL describe filedata-first then
database-second recovery and the recreation of `paperless_data`, `paperless_export`,
and `paperless_consume` rather than their restoration.

#### Scenario: Recovery starts from the new service directory
- **GIVEN** `knowledgeServices/paperless/RESTORE_GUIDE.md` is read
- **WHEN** an operator follows recovery instructions
- **THEN** the guide SHALL start in `knowledgeServices/paperless/`
- **AND** it SHALL describe the scripted restore order and non-restored volumes

### REQ-034: Paperless OCR Language Coverage
Paperless SHALL use `PAPERLESS_OCR_LANGUAGE=eng` and SHALL include `nld` and `hin`
in `PAPERLESS_OCR_LANGUAGES`.

#### Scenario: OCR language example preserves existing coverage
- **GIVEN** `knowledgeServices/paperless/.env.example` is inspected
- **WHEN** OCR language configuration is reviewed
- **THEN** the primary language SHALL be `eng`
- **AND** additional installed languages SHALL include `nld` and `hin`
