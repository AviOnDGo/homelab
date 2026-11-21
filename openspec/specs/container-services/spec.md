## Requirements

### REQ-001: Container services network isolation
The Firefox and Syncthing services under `containerServices/` SHALL join
`container_network`, a dedicated external Docker network. Each service SHALL be
deployed independently from its own directory, without a parent-level aggregate
Compose file or setup script.

#### Scenario: container_network is declared as external
- **GIVEN** any `docker-compose.yml` under `containerServices/` (except a future NPM integration) is inspected
- **WHEN** reviewing the top-level networks block
- **THEN** it SHALL declare `container_network` as `external: true`
- **AND** no containerServices compose file SHALL create the network without `external: true`

#### Scenario: container_network exists before services start
- **GIVEN** the Docker host is being set up for the first time
- **WHEN** `docker network ls` is executed after host setup
- **THEN** a network named `container_network` SHALL exist
- **AND** it SHALL have been created with `docker network create container_network` before any containerServices stack is started

#### Scenario: Service directories are self-contained
- **GIVEN** `containerServices/` contains the Firefox and Syncthing services
- **WHEN** the directory structure is reviewed
- **THEN** Firefox SHALL be managed through `containerServices/firefox/docker-compose.yml`
- **AND** Syncthing SHALL be managed through `containerServices/syncthing/docker-compose.yml`
- **AND** no parent-level aggregate Compose file, setup script, or backup scripts SHALL be present

### REQ-008: Firefox Browser Service
The system SHALL deploy a Firefox container at `containerServices/firefox/docker-compose.yml` on `container_network` (via compose `default` alias), serving a noVNC web UI accessible directly on host port 3000 and via Nginx Proxy Manager.

#### Scenario: Service location
- **WHEN** Firefox is deployed or managed
- **THEN** its compose file SHALL reside at `containerServices/firefox/docker-compose.yml`
- **AND** the container SHALL be named `firefox`

#### Scenario: External container network via default alias
- **GIVEN** `containerServices/firefox/docker-compose.yml` is inspected
- **WHEN** its network configuration is reviewed
- **THEN** the `default` network alias SHALL reference `container_network`
- **AND** that network SHALL be declared with `external: true`
- **AND** the running Firefox container SHALL be attached to `container_network`

#### Scenario: Port 3000 exposed on host (noVNC)
- **GIVEN** Firefox is deployed
- **WHEN** Firefox is running
- **THEN** host port 3000 SHALL be mapped to container port 5800 (noVNC HTTP web UI)
- **AND** NPM access SHALL use the internal `http://firefox:5800` upstream

### REQ-009: Named External Volume for Persistence
The Firefox service SHALL store all persistent data (browser profile, bookmarks, extensions, preferences) in the named external Docker volume `firefox_filedata`.

#### Scenario: Volume naming convention
- **WHEN** `docker volume ls` is executed
- **THEN** a volume named `firefox_filedata` SHALL exist

#### Scenario: Volume declared as external in compose with alias
- **WHEN** `containerServices/firefox/docker-compose.yml` is inspected
- **THEN** a top-level `volumes:` block SHALL declare a `filedata:` key with `external: true` and `name: firefox_filedata`
- **AND** the volume SHALL be mounted as `filedata:/config` inside the container

#### Scenario: Data survives container recreation
- **WHEN** the Firefox container is stopped and recreated with `docker compose up -d --force-recreate`
- **THEN** all previously configured bookmarks, extensions, and browser preferences SHALL be preserved

### REQ-010: Minimal Configuration
The Firefox service SHALL use only the `WEB_AUDIO` environment value needed for
audio support and SHALL NOT use an `env_file:` directive.

#### Scenario: Environment configuration
- **GIVEN** `containerServices/firefox/docker-compose.yml` is inspected
- **WHEN** its service environment is reviewed
- **THEN** `WEB_AUDIO` SHALL be configured
- **AND** no `env_file:` directive SHALL be present

#### Scenario: SHM size configured
- **WHEN** `containerServices/firefox/docker-compose.yml` is inspected
- **THEN** `shm_size: "4gb"` SHALL be present as a top-level service key
- **AND** this prevents browser crashes due to insufficient shared memory

### REQ-011: Backup Integration
The `firefox_filedata` volume SHALL be registered in the `backupServices/filedata` backup pipeline to ensure the Firefox browser profile is protected.

#### Scenario: Volume mounted in backup service
- **WHEN** `backupServices/filedata/docker-compose.yml` is inspected
- **THEN** `firefox_filedata` SHALL appear in the `filedata-backup` service's `volumes:` list as `/backup-sources/firefox:ro`
- **AND** `firefox_filedata` SHALL appear in the top-level `volumes:` block as an external volume

#### Scenario: Cron entry present
- **WHEN** the `filedata-backup` container's cron schedule is inspected
- **THEN** an entry matching `${FIREFOX_CRON_SCHEDULE} /bin/bash /usr/local/bin/backup-script.sh firefox` SHALL be present

#### Scenario: Backup environment variables defined
- **WHEN** `backupServices/filedata/.env` is inspected
- **THEN** `FIREFOX_CRON_SCHEDULE`, `FIREFOX_DROPBOX_PATH`, and `FIREFOX_RETENTION_DAYS` SHALL be present

### REQ-012: Service Documentation
The Firefox service directory SHALL contain `SERVICE_DOCUMENTATION.md` and `RESTORE_GUIDE.md`.

#### Scenario: Documentation files present
- **WHEN** `containerServices/firefox/` is listed
- **THEN** both `SERVICE_DOCUMENTATION.md` and `RESTORE_GUIDE.md` SHALL be present

### REQ-013: NPM Proxy with WebSocket Support
Firefox SHALL be accessible via Nginx Proxy Manager with WebSocket support enabled, as required for noVNC browser streaming.

#### Scenario: WebSocket support required
- **WHEN** the NPM proxy host for Firefox is configured
- **THEN** the "WebSockets Support" toggle SHALL be enabled
- **AND** the upstream SHALL point to `http://firefox:5800`

### REQ-014: Resource Limits
The Firefox service SHALL have CPU and memory limits to prevent host resource exhaustion and protect co-located containers.

#### Scenario: Deploy resource limits declared
- **WHEN** `containerServices/firefox/docker-compose.yml` is inspected
- **THEN** a `deploy.resources.limits` block SHALL be present under the `firefox` service
- **AND** `cpus` SHALL be set to `'4.0'`
- **AND** `memory` SHALL be set to `4G`

#### Scenario: Container respects CPU cap at runtime
- **WHEN** `docker inspect firefox` is executed
- **THEN** `HostConfig.NanoCpus` SHALL equal `4000000000` (4 CPUs)
- **AND** `HostConfig.Memory` SHALL equal `4294967296` (4 GiB)
