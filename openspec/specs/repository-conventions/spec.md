## Purpose

Define repository-wide conventions for service structure, compose patterns,
environment template handling, documentation standards, and operational guardrails.

## Requirements

### REQ-001: Environment file management in opsx changes
OpenSpec changes SHALL never create or modify `.env` files. Live `.env` files are
operator-managed runtime configuration outside version control.

#### Scenario: opsx change targets environment configuration
- **GIVEN** an opsx change or task involves environment variable configuration
- **WHEN** the change is implemented
- **THEN** tasks for filedata backups SHALL only create or modify `.env.local.example` and `.env.prod.example`
- **AND** tasks for other backup services SHALL only create or modify `.env.acc.example` and `.env.prd.example`
- **AND** tasks for all other services SHALL only create or modify `.env.example`
- **AND** tasks SHALL NOT create, overwrite, or patch `.env` files
- **AND** tasks SHALL NOT include shell commands that write to `.env`

#### Scenario: New service added via an opsx change
- **GIVEN** an opsx change adds a backup service with configurable environment variables
- **WHEN** creating environment variable documentation
- **THEN** the change SHALL add the new variables to both example files required for that backup service by REQ-002
- **AND** the operator is responsible for running `cp .env.acc.example .env` or
  `cp .env.prd.example .env` for PostgreSQL, or the corresponding `.env.local.example`
  or `.env.prod.example` for filedata backups, to apply configuration

#### Scenario: New non-backup service added via an opsx change
- **GIVEN** an opsx change adds a non-backup service with configurable environment variables
- **WHEN** creating environment variable documentation
- **THEN** the change SHALL add the new variables to `.env.example`
- **AND** the operator is responsible for running `cp .env.example .env` to apply configuration

### REQ-002: Environment example file naming convention
Filedata backup SHALL provide `.env.local.example` and `.env.prod.example`.
Other backup services (under `backupServices/`) that require operator-supplied
environment variables SHALL provide two tracked example files
(`.env.acc.example` and `.env.prd.example`). All other services with
operator-supplied environment variables SHALL provide a single `.env.example`
file. Every tracked template file name SHALL start with a dot and end in
`.example`.

#### Scenario: Filedata backup has local and production templates
- **GIVEN** `backupServices/filedata/` is inspected
- **WHEN** listing tracked files
- **THEN** the directory SHALL contain `.env.local.example` for the Local profile
- **AND** the directory SHALL contain `.env.prod.example` for the Prod profile
- **AND** the directory SHALL NOT contain a plain `.env.example`
- **AND** the directory SHALL NOT contain `.env.backup`

#### Scenario: Other backup service has two env example files
- **GIVEN** a backup service other than filedata with configurable environment variables is inspected
- **WHEN** listing tracked files
- **THEN** the directory SHALL contain `.env.acc.example` and `.env.prd.example`
- **AND** the directory SHALL NOT contain a plain `.env.example` or `.env.backup`

#### Scenario: Non-backup service has a single env example file
- **GIVEN** a service directory outside `backupServices/` with configurable environment variables is inspected
- **WHEN** listing tracked files
- **THEN** the directory SHALL contain `.env.example`
- **AND** the directory SHALL NOT contain `.env.acc.example` or `.env.prd.example`
- **AND** the directory SHALL NOT contain `.env.backup`

#### Scenario: Operator copies example to configure environment
- **GIVEN** an operator wants to configure a non-backup service
- **WHEN** they run `cp .env.example .env`
- **THEN** all environment-specific values SHALL be pre-populated
- **AND** the operator only needs to fill in secret credentials to complete setup

#### Scenario: Both backup examples have identical variable sets
- **GIVEN** the two environment examples for a backup service are compared
- **WHEN** checking which variable names are defined
- **THEN** both files SHALL declare exactly the same set of variable names
- **AND** the only permitted differences are environment-specific values (e.g., Dropbox path prefix)
  and header comments identifying the environment

### REQ-003: UTC timezone convention
The repository SHALL use UTC as its generic timezone default. Any explicit `TZ`
value in a Compose file or tracked environment example SHALL be `UTC`. The Docker
host OS SHALL use UTC for services that inherit the host timezone.

#### Scenario: Tracked timezone values are generic
- **GIVEN** Compose files and tracked environment examples are inspected
- **WHEN** timezone configuration is reviewed
- **THEN** any explicit `TZ` value SHALL be `UTC`
- **AND** files SHALL NOT contain a disabled timezone configuration

#### Scenario: Host OS uses UTC
- **GIVEN** the Docker host OS is configured for UTC
- **WHEN** a service inherits the host timezone
- **THEN** the service SHALL use UTC

#### Scenario: Operator sets up a new Docker host
- **GIVEN** a new machine is being configured to run homelab services
- **WHEN** the operator completes host OS setup
- **THEN** the operator SHALL verify `timedatectl show | grep Timezone` returns `Etc/UTC`
- **AND** services that inherit the host timezone SHALL use UTC

### REQ-004: Docker Compose network block declaration
Every `docker-compose.yml` SHALL include a top-level `networks:` block declaring
all referenced networks as `external: true`.

#### Scenario: Network block present
- **GIVEN** a `docker-compose.yml` references one or more Docker networks
- **WHEN** the file is inspected
- **THEN** a top-level `networks:` block SHALL exist
- **AND** each network SHALL be declared as `external: true` with its full `name:`
- **AND** implicit network creation SHALL NOT be relied upon

### REQ-005: .env file policy — inline vs. .env
A service SHALL use a `.env` file (and `env_file: .env` reference) only when it
has multiple secret or user-specific variables, or when a variable is referenced
in several places within `docker-compose.yml`.

#### Scenario: Service with few non-secret variables
- **GIVEN** a service needs only one or two non-secret, rarely-changing values
- **WHEN** the `docker-compose.yml` is written
- **THEN** those values SHALL be inlined directly in the `environment:` block
- **AND** a `.env` file SHALL NOT be created solely for those values

### REQ-006: No PUID or PGID in compose files
No `docker-compose.yml` in the repository SHALL include `PUID` or `PGID`
environment variables. UID/GID mapping is not managed at the compose level
for this homelab.

#### Scenario: Compose file has no PUID or PGID entry
- **GIVEN** any `docker-compose.yml` is inspected
- **WHEN** searching for user identity mapping
- **THEN** the file SHALL NOT contain `PUID` or `PGID` keys under any service's `environment` block

### REQ-007: All services use restart: unless-stopped
Every service in a `docker-compose.yml` SHALL declare `restart: unless-stopped`.
The value `always` is not permitted as it prevents intentional stops from
persisting across daemon restarts.

#### Scenario: Restart policy is correct
- **GIVEN** a `docker-compose.yml` is inspected
- **WHEN** reviewing each service definition
- **THEN** every service SHALL have `restart: unless-stopped`
- **AND** no service SHALL have `restart: always`, `restart: on-failure`, or any other value

### REQ-008: Single filedata volume follows the external named-volume pattern
Any service that uses exactly one persistent volume SHALL declare it as an external
named volume with the pattern `<service_name>_filedata`.

#### Scenario: Single-volume service declares filedata correctly
- **GIVEN** a service has one persistent volume
- **WHEN** the volumes block is inspected
- **THEN** the volumes block SHALL contain:
  ```yaml
  volumes:
    filedata:
      name: <service_name>_filedata
      external: true
  ```
- **AND** the volume SHALL exist as a Docker named volume before the service is started

#### Scenario: Volume is not created implicitly by compose
- **GIVEN** a service using the filedata pattern is started
- **WHEN** the named external volume does not exist
- **THEN** `docker compose up` SHALL fail with a clear error
- **AND** Docker SHALL NOT silently create the volume with a different name

### REQ-009: Non-NPM services use the default network shorthand
Any service that participates in exactly one Docker category network SHALL declare it
using the `default` network key rather than a named network block. NPM is the sole
exception as it owns and creates all category networks.

#### Scenario: Single-network service uses default pattern
- **GIVEN** a service belongs to exactly one category network
- **WHEN** its compose file is inspected
- **THEN** the top-level `networks:` block SHALL declare:
  ```yaml
  networks:
    default:
      name: <category>_network
      external: true
  ```
- **AND** the service definition SHALL NOT contain a `networks:` key
- **AND** there SHALL be no additional named network entries

#### Scenario: Network is not created by a non-NPM service
- **GIVEN** a non-NPM service's compose file is inspected
- **WHEN** checking the networks block
- **THEN** every network SHALL have `external: true`
- **AND** the compose file SHALL NOT create any network that NPM owns

### REQ-010: Spec format standard — REQ-NNN with GIVEN/WHEN/THEN
All spec files in `openspec/specs/` SHALL follow the REQ-NNN requirement identifier
format with GIVEN/WHEN/THEN scenarios. This standard applies to all new specs and
to specs being rewritten or updated.

#### Scenario: New spec file is created
- **GIVEN** an agent or operator is creating a new `spec.md` in `openspec/specs/<capability>/`
- **WHEN** writing requirements
- **THEN** each requirement SHALL have a stable identifier in the form `REQ-NNN`
- **AND** each requirement SHALL use `SHALL` or `SHALL NOT` as the normative verb
- **AND** every requirement SHALL have at least one scenario

#### Scenario: Scenario uses GIVEN/WHEN/THEN structure
- **GIVEN** a spec scenario is being written
- **WHEN** the scenario is inspected
- **THEN** it SHALL include a `GIVEN` line establishing preconditions
- **AND** it SHALL include a `WHEN` line describing the triggering action
- **AND** it SHALL include a `THEN` line describing the expected outcome

#### Scenario: Spec file uses no changelog headers
- **GIVEN** a spec file in `openspec/specs/` is inspected
- **WHEN** reading the file structure
- **THEN** the file SHALL NOT contain `## ADDED Requirements`, `## MODIFIED Requirements`, or similar changelog headers
- **AND** requirements SHALL appear as a flat list under `## Requirements`

### REQ-011: Service operational documentation is required for all services
Every service deployed in the homelab SHALL have a `SERVICE_DOCUMENTATION.md` file in its
service directory covering architecture, configuration, operational procedures, and troubleshooting.

#### Scenario: Service documentation present
- **GIVEN** a service directory is inspected
- **WHEN** listing tracked files
- **THEN** the directory SHALL contain `SERVICE_DOCUMENTATION.md`
- **AND** the file SHALL document all containers, volumes, networks, and configuration

#### Scenario: Service documentation covers operational procedures
- **GIVEN** `SERVICE_DOCUMENTATION.md` exists for a service
- **WHEN** an operator needs to start, stop, update, or inspect the service
- **THEN** the file SHALL provide explicit commands and steps for each operation

### REQ-012: Restore documentation is required for stateful services
Any service that uses persistent Docker volumes or a database SHALL have a `RESTORE_GUIDE.md`
file in its service directory. Backup infrastructure services that document restore
procedures in the services they back up SHALL be permitted to omit this file.

#### Scenario: Stateful service has restore guide
- **GIVEN** a service mounts at least one external Docker named volume
- **WHEN** the service directory is listed
- **THEN** a `RESTORE_GUIDE.md` file SHALL be present
- **AND** it SHALL document volume names, backup sources, restore commands, and verification steps

#### Scenario: Restore guide covers database services
- **GIVEN** a service uses a PostgreSQL or SQLite database
- **WHEN** reading the restore guide
- **THEN** it SHALL include database-specific restore procedures
- **AND** it SHALL include verification queries to confirm restore success

### REQ-013: Service directory name matches the primary service name
Service directories SHALL use the short, lowercase, common application name. The directory
name SHALL match the primary service name defined in `docker-compose.yml`. Multi-word
names SHALL use kebab-case. Verbose or expanded names SHALL NOT be used.

#### Scenario: Directory name uses short app name
- **GIVEN** a service is being added to the repository
- **WHEN** creating the service directory
- **THEN** the directory name SHALL match the service name (e.g., `npm` for Nginx Proxy Manager,
  `firefly` for Firefly III)
- **AND** verbose names such as `nginx-proxy-manager` SHALL NOT be used

#### Scenario: Backup service directory naming
- **GIVEN** a backup service is created
- **WHEN** naming the directory
- **THEN** the name SHALL reflect the data type being backed up (e.g., `filedata`, `postgres`)
- **AND** the directory SHALL reside under `backupServices/`

### REQ-014: container_name SHALL exactly match the service name
For every service defined in a `docker-compose.yml`, the `container_name` field SHALL
exactly match the service name key. There SHALL be no deviation between service and
container naming.

#### Scenario: Container name matches service key
- **GIVEN** a service block is defined in `docker-compose.yml`
- **WHEN** inspecting the `container_name` field
- **THEN** the value SHALL be identical to the service name key

### REQ-015: Database companion services use the `<service>-db` naming pattern
When a service requires a dedicated PostgreSQL (or other relational database) container,
the database service SHALL be named `<primary-service>-db` using a hyphen separator.

#### Scenario: PostgreSQL companion service is named correctly
- **GIVEN** a service named `firefly` requires a PostgreSQL database
- **WHEN** the companion service is added to `docker-compose.yml`
- **THEN** the service name SHALL be `firefly-db`
- **AND** the `container_name` SHALL also be `firefly-db`

### REQ-016: Inter-service references use service names, not IP addresses
When one service references another (in environment variables, config files, or cron
jobs), it SHALL use the Docker service name as the hostname. IP addresses SHALL NOT be
hardcoded for inter-container communication.

#### Scenario: Service references companion database by name
- **GIVEN** a web application container needs to connect to its database
- **WHEN** the database URL is configured
- **THEN** the hostname component SHALL be the database service name (e.g., `firefly-db`)
- **AND** no IP address SHALL be hardcoded

#### Scenario: Cron job references a service by name
- **GIVEN** a cron job script needs to communicate with a container
- **WHEN** the endpoint is constructed
- **THEN** it SHALL use the service name as the hostname (e.g., `http://firefly:8080`)

### REQ-017: Volume subpath mount structure for file storage
When a service mounts persistent file storage, it SHALL use a subpath structure within
the named volume. Primary application data SHALL mount under the `data` subpath. Each
logically distinct data directory SHALL use a separate, hierarchically named subpath.

#### Scenario: Single-purpose data volume uses data subpath
- **GIVEN** a service mounts one persistent directory for application data
- **WHEN** the volume entry is written
- **THEN** the source subpath SHALL be `filedata/data` and it SHALL map to the container mount point

#### Scenario: Multiple mount points share one volume
- **GIVEN** a service requires separate directories for data and configuration
- **WHEN** the compose volumes block is written
- **THEN** each directory SHALL use a distinct subpath within the same `filedata` volume
  (e.g., `filedata/data`, `filedata/etc/letsencrypt`)
- **AND** a separate named volume SHALL NOT be created solely for organizational purposes

### REQ-018: NPM is the sole creator of all category Docker networks
Nginx Proxy Manager's `docker-compose.yml` SHALL define and create all shared homelab
Docker networks (`media_network`, `ai_network`, `finance_network`, `security_network`,
`games_network`, `knowledge_network`) without the `external: true` flag. All other
service compose files SHALL reference these networks with `external: true`.

#### Scenario: Networks are created when NPM stack starts
- **GIVEN** no category networks exist on the Docker host
- **WHEN** `docker compose up -d` is run in `securityServices/npm/`
- **THEN** Docker creates all category networks
- **AND** the NPM container starts and joins all networks

#### Scenario: Non-NPM service does not create any network
- **GIVEN** a compose file outside `securityServices/npm/` is inspected
- **WHEN** checking every network declaration
- **THEN** every network SHALL have `external: true`
- **AND** the compose file SHALL NOT provision any network

### REQ-019: Docker healthchecks for long-running services
Every long-running service that exposes an HTTP health endpoint or a database readiness check SHALL declare a `healthcheck` block in its `docker-compose.yml`. The healthcheck enables Docker's dependency ordering (`depends_on: condition: service_healthy`) and automatic container restart recovery.

#### Scenario: Web service declares an HTTP healthcheck
- **GIVEN** a service runs continuously and exposes an HTTP endpoint (e.g., `/health`, `/__heartbeat__`)
- **WHEN** its `docker-compose.yml` is inspected
- **THEN** a `healthcheck:` block SHALL be present with `test`, `interval`, `timeout`, `retries`, and `start_period` fields
- **AND** the `test` command SHALL target the service's local health endpoint (e.g., `wget -qO- http://localhost:<port>/health`)

#### Scenario: Database service declares a readiness healthcheck
- **GIVEN** a PostgreSQL or other database service is used as a dependency by another container
- **WHEN** its `docker-compose.yml` is inspected
- **THEN** a `healthcheck:` block SHALL be present using `pg_isready` or equivalent
- **AND** the dependent service SHALL declare `depends_on.<db>: condition: service_healthy`

#### Scenario: Stateless or short-lived services are exempt from healthcheck requirement
- **GIVEN** a service is stateless, short-lived (e.g., a cron runner), or provides no health endpoint
- **WHEN** its `docker-compose.yml` is inspected
- **THEN** the absence of a `healthcheck:` block is acceptable
- **AND** the rationale SHALL be documented in a comment in the compose file

### REQ-020: PostgreSQL companion volumes are internal (not external)
When a service deploys a companion PostgreSQL container, the PostgreSQL data volume SHALL be declared as an internal named volume — without `external: true`. The `name:` field SHALL follow the pattern `<service>_postgresdata`. The `backupServices/postgres/` compose file SHALL be permitted to reference the same volume as `external: true` for backup mount purposes; this does not affect the owning service's declaration.

#### Scenario: Postgres data volume is declared internally
- **GIVEN** a `docker-compose.yml` includes a companion PostgreSQL service
- **WHEN** the top-level `volumes:` block is inspected
- **THEN** the PostgreSQL data volume SHALL be declared without `external: true`
- **AND** the volume SHALL have a `name:` following the pattern `<service>_postgresdata`
- **AND** `docker compose up` SHALL create the volume automatically if it does not exist

#### Scenario: Backup service is permitted to reference postgres volume as external
- **GIVEN** `backupServices/postgres/docker-compose.yml` mounts a service's postgres data volume
- **WHEN** the backup compose volumes block is inspected
- **THEN** the volume SHALL be permitted to reference the same volume as `external: true` in the backup compose file
- **AND** this is permitted because the backup service does not own the volume lifecycle
- **AND** the originating service's compose file SHALL still NOT declare the volume as external

### REQ-021: PostgreSQL data volume mount path
When a service mounts a companion PostgreSQL data volume, it SHALL be mounted at `/var/lib/postgresql` inside the container. The `/data` suffix SHALL NOT be appended to the mount path.

#### Scenario: Postgres volume is mounted at the standard path
- **GIVEN** a `docker-compose.yml` includes a companion PostgreSQL service
- **WHEN** the volume mount entry for the postgres data volume is inspected
- **THEN** the container-side mount path SHALL be `/var/lib/postgresql`
- **AND** the mount path SHALL NOT end with `/data`

#### Scenario: PGDATA is resolved internally by the image
- **GIVEN** a postgres container mounts its data volume at `/var/lib/postgresql`
- **WHEN** the container initialises
- **THEN** the postgres image SHALL write data into the `data/` subdirectory within the volume
- **AND** no explicit `PGDATA` environment variable override is required

### REQ-025: GitHub Actions environment targeting in deployment workflows
GitHub Actions deployment workflows SHALL support environment selection through multiple trigger modes: manual workflow_dispatch, environment-specific branch push filters, and YAML syntax validation checks.

#### Scenario: Manual dispatch with environment selection
- **GIVEN** a GitHub Actions workflow includes `workflow_dispatch` with an `environments` input
- **WHEN** an operator manually triggers the workflow via GitHub UI or CLI
- **THEN** the workflow SHALL allow selection of target environment (e.g., `acc` or `prd`)
- **AND** the selected environment SHALL be passed to downstream deployment jobs

#### Scenario: Push-triggered deployment to production
- **GIVEN** a branch protection rule requires the `prd` environment for merges to `main`
- **WHEN** a commit is pushed to `main`
- **THEN** the deployment workflow SHALL automatically target the `prd` environment
- **AND** environment secrets (credentials, URLs) SHALL be retrieved from GitHub's `prd` environment settings

#### Scenario: YAML syntax validation before deployment
- **GIVEN** a deployment workflow processes Docker Compose or Terraform files
- **WHEN** the `pre-deploy` job runs
- **THEN** YAML syntax validation (e.g., `yamllint`) SHALL complete before any infrastructure changes
- **AND** the job SHALL fail if syntax errors are detected, blocking deployment to any environment

### REQ-026: Terraform lockfiles are never committed
Terraform lockfiles (`.terraform.lock.hcl`) SHALL NOT be committed in this repository and SHALL be ignored by source control at every directory level.

#### Scenario: Repository-level ignore for terraform lockfiles
- **GIVEN** git ignore rules are inspected at repository root
- **WHEN** checking Terraform artifact entries
- **THEN** `.terraform.lock.hcl` SHALL be ignored globally
- **AND** lockfiles generated in any subdirectory SHALL remain untracked

#### Scenario: Previously tracked lockfile is removed from index
- **GIVEN** a `.terraform.lock.hcl` file was committed in the past
- **WHEN** cleanup is performed
- **THEN** the file SHALL be removed from git index while remaining local for operator workflows
- **AND** subsequent commits SHALL NOT include the lockfile unless policy is explicitly changed

### REQ-027: Every service directory includes a restore.sh entrypoint
Each service directory SHALL include an executable `restore.sh` script as the operator-facing recovery entrypoint.

#### Scenario: Service directory contains restore.sh
- **GIVEN** any service directory in the repository is inspected
- **WHEN** tracked files are listed
- **THEN** `restore.sh` SHALL be present
- **AND** it SHALL be executable

#### Scenario: Restore guide references script-first flow
- **GIVEN** a service has `RESTORE_GUIDE.md`
- **WHEN** recovery instructions are reviewed
- **THEN** `./restore.sh` SHALL be documented as the primary restore path
- **AND** manual fallback steps SHALL be permitted to be included for exceptional recovery

#### Scenario: Stateless service provides no-op restore helper
- **GIVEN** a service has no persistent state to restore
- **WHEN** `restore.sh` is executed
- **THEN** the script SHALL exit successfully
- **AND** it SHALL print a clear message explaining that no restore action is required

### REQ-028: Private deployment configuration and runtime state remain outside Git
Tracked configuration SHALL use placeholders or private inputs for personal
endpoints and cloud account identifiers. Application cookies, histories and
generated user configuration SHALL NOT be tracked. Populated root-level
`.mcp.json` and `opencode.json` files SHALL be ignored by Git, while their
sanitized `.example` counterparts SHALL remain trackable.

#### Scenario: Local client settings use sanitized examples
- **GIVEN** a new checkout needs MCP or OpenCode configuration
- **WHEN** its client configuration is prepared
- **THEN** tracked examples SHALL contain no deployment-specific addresses
- **AND** root-level `.mcp.json` and `opencode.json` files SHALL be ignored by Git
- **AND** `.mcp.json.example` and `opencode.json.example` SHALL remain trackable

### REQ-029: Local secret gates detect structured credentials without disclosure
Local staged and push-range gates SHALL share credential detection for added
shell/YAML, JSON and XML lines, including example files. Findings SHALL NOT
print credential values.

#### Scenario: Structured API key is added
- **GIVEN** a staged or outgoing diff adds a literal JSON or XML API key
- **WHEN** the local secret gate runs
- **THEN** it SHALL fail with the file, line and field name
- **AND** it SHALL redact the credential value

#### Scenario: Examples contain only placeholders or references
- **GIVEN** an example file contains explicit placeholders or environment references
- **WHEN** the local secret gate runs
- **THEN** those values SHALL NOT be treated as literal credentials
- **AND** a literal credential in the same example file SHALL still fail the gate
