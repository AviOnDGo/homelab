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
