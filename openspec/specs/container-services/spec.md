## Requirements

### REQ-001: Container services network isolation
All services under `containerServices/` SHALL join `container_network`, a dedicated external Docker network. This network isolates container-management tooling from other service categories.

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

### REQ-002: Kasm browser-streaming service deployment
The system SHALL deploy Kasm Workspaces as the browser-streaming isolated workspace service under `containerServices/kasm/`, joined to `container_network`.

#### Scenario: Kasm is deployed from its canonical directory
- **GIVEN** the Kasm stack is being deployed
- **WHEN** `docker compose up -d` is run in `containerServices/kasm/`
- **THEN** the kasm container SHALL start and join `container_network`

#### Scenario: Container name matches service name
- **GIVEN** `containerServices/kasm/docker-compose.yml` is inspected
- **WHEN** reviewing the container_name field
- **THEN** it SHALL be set to `kasm`
- **AND** the service key SHALL also be `kasm`

#### Scenario: No direct host port exposure
- **GIVEN** Kasm is running
- **WHEN** reviewing port mappings in `containerServices/kasm/docker-compose.yml`
- **THEN** no active `ports:` entry SHALL map a container port directly to the host
- **AND** all external access SHALL be routed via Nginx Proxy Manager

### REQ-003: Kasm privileged mode for workspace launching
The Kasm container SHALL run with `privileged: true` to enable the cgroup and namespace operations required for Docker-in-Docker workspace launching. This is a documented operational necessity, not a security misconfiguration.

#### Scenario: Kasm has privileged mode enabled
- **GIVEN** `containerServices/kasm/docker-compose.yml` is inspected
- **WHEN** reviewing the kasm service definition
- **THEN** `privileged: true` SHALL be present
- **AND** it SHALL NOT be replaced with individual `cap_add` entries, as insufficient capabilities cause workspace launch failures

#### Scenario: SHM size is configured for workspaces
- **GIVEN** `containerServices/kasm/docker-compose.yml` is inspected
- **WHEN** reviewing the kasm service definition
- **THEN** `shm_size: "1gb"` (or equivalent) SHALL be set
- **AND** this allocation ensures browser-streaming workspaces have sufficient shared memory

### REQ-004: Kasm persistent data in external named volume
Kasm SHALL store all workspace configuration, user accounts, and session state in the external named Docker volume `kasm_filedata`, mounted at `/opt/kasm` inside the container.

#### Scenario: kasm_filedata is declared external
- **GIVEN** `containerServices/kasm/docker-compose.yml` is inspected
- **WHEN** reviewing the top-level volumes block
- **THEN** `kasm_filedata` SHALL be declared with `external: true` and `name: kasm_filedata`
- **AND** it SHALL be mounted at `/opt/kasm` in the kasm service

#### Scenario: Workspace data survives container recreation
- **GIVEN** the kasm container is stopped and recreated with `docker compose up -d --force-recreate`
- **WHEN** the container starts
- **THEN** all previously configured workspaces and user accounts SHALL be accessible
- **AND** no configuration loss SHALL occur

### REQ-005: NPM proxy with WebSocket support
Kasm SHALL be accessible exclusively via Nginx Proxy Manager, with WebSocket support enabled in the NPM proxy host configuration. WebSocket support is required for the browser-streaming protocol used by Kasm workspaces.

#### Scenario: NPM proxy host has WebSocket support enabled
- **GIVEN** the NPM proxy host for Kasm is configured
- **WHEN** reviewing the proxy host settings
- **THEN** the "WebSockets Support" toggle SHALL be enabled
- **AND** the upstream shall point to the kasm container's HTTPS port

#### Scenario: Kasm is reachable over HTTPS via NPM
- **GIVEN** a user accesses the Kasm domain
- **WHEN** the request is processed by NPM
- **THEN** NPM SHALL terminate the HTTPS connection and proxy the request to Kasm
- **AND** the Kasm Workspaces interface SHALL be displayed

### REQ-006: Backup integration for Kasm configuration
The `kasm_filedata` volume SHALL be registered with `backupServices/filedata/` to protect Kasm workspace configuration and user accounts.

#### Scenario: kasm_filedata appears in filedata backup
- **GIVEN** `backupServices/filedata/docker-compose.yml` is inspected
- **WHEN** reviewing the filedata-backup service volumes list
- **THEN** `kasm_filedata` SHALL be mounted as a read-only backup source
- **AND** a cron entry for the kasm backup SHALL exist in the backup service configuration

### REQ-007: Service documentation requirements
The `containerServices/kasm/` directory SHALL contain `SERVICE_DOCUMENTATION.md` and `RESTORE_GUIDE.md`.

#### Scenario: SERVICE_DOCUMENTATION.md is present
- **GIVEN** `containerServices/kasm/` is listed
- **WHEN** checking for documentation
- **THEN** `SERVICE_DOCUMENTATION.md` SHALL exist
- **AND** it SHALL document architecture, NPM WebSocket proxy setup, privileged mode rationale, and operational commands

#### Scenario: RESTORE_GUIDE.md is present
- **GIVEN** `containerServices/kasm/` is listed
- **WHEN** checking for restore documentation
- **THEN** `RESTORE_GUIDE.md` SHALL exist
- **AND** it SHALL document how to restore the kasm_filedata volume and verify workspace accessibility


### REQ-008: Firefox Browser Service
The system SHALL deploy a Firefox container at `containerServices/firefox/docker-compose.yml` on `container_network` (via compose `default` alias), serving a noVNC web UI accessible directly on host port 3000 and via Nginx Proxy Manager.

#### Scenario: Service location
- **WHEN** Firefox is deployed or managed
- **THEN** its compose file SHALL reside at `containerServices/firefox/docker-compose.yml`
- **AND** the container SHALL be named `firefox`

#### Scenario: Default bridge network
- **WHEN** `docker inspect firefox` is executed
- **THEN** the container SHALL be attached to the default bridge network
- **AND** no custom `networks:` block SHALL be present in `containerServices/firefox/docker-compose.yml`

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

### REQ-010: Minimal Configuration — shm_size Only
The Firefox service SHALL have no `environment:` block and no `env_file:` directive. Only `shm_size` is required.

#### Scenario: No environment variables
- **WHEN** `containerServices/firefox/docker-compose.yml` is inspected
- **THEN** no `environment:` block SHALL be present
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
