## Purpose

Define baseline infrastructure conventions for Docker Compose behavior, network
isolation, gateway routing, local host provisioning, and core operational
standards across the homelab.

## Requirements

### REQ-001: Docker Compose V2 format — no version field
All `docker-compose.yml` files in the repository SHALL omit the top-level `version:` field. Docker Compose V2 uses the version-agnostic Compose Specification and treats `version` as a deprecated no-op.

#### Scenario: Compose file has no version field
- **GIVEN** any `docker-compose.yml` in the repository is inspected
- **WHEN** searching for a top-level `version:` key
- **THEN** no `version:` entry SHALL be present
- **AND** the absence does not affect compose behaviour under Docker Compose V2

#### Scenario: Operator verifies Docker version before deploying
- **GIVEN** a new host is being set up to run homelab services
- **WHEN** the operator checks the installed tooling
- **THEN** `docker --version` SHALL report Docker Engine 20.10 or later
- **AND** `docker compose version` SHALL report Docker Compose v2.0 or later

### REQ-002: Multi-architecture image selection
Container images SHALL use multi-architecture manifests or architecture-specific tags compatible with both x86_64 and ARM64 where the service is intended to run on both architectures.

#### Scenario: x86_64 deployment succeeds
- **GIVEN** the Docker host is running on x86_64 architecture
- **WHEN** `docker compose up -d` is run for any service
- **THEN** Docker SHALL pull an x86_64-compatible image for each service
- **AND** all containers SHALL start successfully

#### Scenario: ARM64-specific images use the correct tag
- **GIVEN** a compose file specifies an architecture-specific image tag (e.g., `amd64-<version>`)
- **WHEN** the service is deployed on an ARM64 host
- **THEN** the operator SHALL supply an ARM64-compatible tag override
- **AND** the default tag in compose SHALL be documented as x86_64-specific

### REQ-003: NVIDIA GPU passthrough for AI workloads
Services that require GPU acceleration SHALL declare the NVIDIA runtime and device reservation in their `docker-compose.yml`. GPU passthrough SHALL only be configured for services that genuinely use the GPU (e.g., Ollama).

#### Scenario: GPU-enabled service declares NVIDIA resources
- **GIVEN** an AI service requires GPU acceleration
- **WHEN** `docker compose up -d` is run on a host with an NVIDIA GPU
- **THEN** the container SHALL have access to the GPU via the NVIDIA container runtime
- **AND** the compose file SHALL declare `deploy.resources.reservations.devices` with `driver: nvidia` and `capabilities: [gpu]`

#### Scenario: GPU passthrough is absent for non-GPU services
- **GIVEN** a service that does not need GPU acceleration
- **WHEN** its compose file is inspected
- **THEN** no `deploy.resources.reservations.devices` block SHALL be present
- **AND** no NVIDIA runtime settings SHALL appear

### REQ-004: NPM SSL certificate policy — Let's Encrypt only
Nginx Proxy Manager SHALL provision SSL certificates exclusively via Let's Encrypt for all externally accessible proxy hosts. HTTP-only proxy hosts are not permitted for services exposed outside the homelab network.

#### Scenario: New proxy host requires SSL
- **GIVEN** an operator creates a new NPM proxy host for an externally accessible service
- **WHEN** configuring the SSL settings
- **THEN** the operator SHALL enable SSL, select "Request a new SSL certificate" via Let's Encrypt, and enable "Force SSL"
- **AND** no HTTP-only proxy host SHALL be created for externally accessible services

#### Scenario: Certificate auto-renewal is handled by NPM
- **GIVEN** a Let's Encrypt certificate issued by NPM approaches expiry (within 30 days)
- **WHEN** NPM's renewal check runs
- **THEN** NPM SHALL automatically renew the certificate without operator intervention
- **AND** the renewed certificate SHALL be applied to all proxy hosts using that certificate

### REQ-005: Network isolation — one dedicated network per service category
Each service category SHALL use exactly one named external Docker network for inter-service communication. Services SHALL NOT communicate across category networks directly. NPM is the sole exception as it joins all category networks to serve as the gateway.

#### Scenario: Category services communicate within their network
- **GIVEN** two services in the same category (e.g., Jellyfin and Sonarr in media_network)
- **WHEN** they communicate with each other
- **THEN** all traffic SHALL flow within that category's network
- **AND** neither service SHALL be reachable directly from a different category's network

#### Scenario: NPM joins all category networks
- **GIVEN** `securityServices/npm/docker-compose.yml` is inspected
- **WHEN** reviewing the networks block
- **THEN** NPM SHALL declare membership in all category networks
- **AND** NPM SHALL be the sole service joining more than one category network (other than backup services that mount cross-category volumes)

### REQ-006: Automated container image updates via Watchtower
The homelab SHALL use Watchtower to automatically pull updated container images and recreate containers on a defined schedule. Database and sensitive service containers SHALL opt out of auto-updates.

#### Scenario: Containers are updated on schedule
- **GIVEN** Watchtower is running with a configured schedule
- **WHEN** new image versions are available for monitored containers
- **THEN** Watchtower SHALL pull the new images and recreate the containers
- **AND** volumes, networks, and environment remain unchanged after recreation

#### Scenario: Critical containers opt out
- **GIVEN** a container managing persistent data (e.g., a PostgreSQL database)
- **WHEN** Watchtower performs its scheduled check
- **THEN** the container SHALL be skipped if it carries the `com.centurylinklabs.watchtower.enable=false` label

### REQ-007: All external services routed exclusively through NPM
Every service that is accessible from outside the Docker host SHALL be routed through Nginx Proxy Manager. Direct host port exposure (`ports:` directives) for externally accessible services SHALL be commented out in `docker-compose.yml`.

#### Scenario: New service made externally accessible
- **GIVEN** an operator wants to expose a service externally
- **WHEN** they configure access
- **THEN** they SHALL add the service's network to NPM, comment out the service's `ports:` directive, and create an NPM proxy host
- **AND** no direct host port mapping SHALL remain active for that service

#### Scenario: Port exposure audit finds no violations
- **GIVEN** a repository audit is performed
- **WHEN** all `docker-compose.yml` files are scanned for active `ports:` mappings
- **THEN** no service intended for external access SHALL have an uncommented `ports:` entry

### REQ-008: Service documentation standard applies to all services
Every service deployed in the homelab SHALL comply with the service documentation standard defined in `openspec/specs/repository-conventions/spec.md`. `SERVICE_DOCUMENTATION.md` is required for all services; `RESTORE_GUIDE.md` is required for all stateful services.

#### Scenario: Infrastructure service has documentation
- **GIVEN** any service directory in the homelab repository is inspected
- **WHEN** listing tracked files
- **THEN** `SERVICE_DOCUMENTATION.md` SHALL be present
- **AND** the file SHALL document architecture, operational commands, and troubleshooting

#### Scenario: New service is added with persistent storage
- **GIVEN** an operator adds a new service that uses a named Docker volume
- **WHEN** the service is committed to the repository
- **THEN** both `SERVICE_DOCUMENTATION.md` and `RESTORE_GUIDE.md` SHALL be present
- **AND** `RESTORE_GUIDE.md` SHALL document volume names, restore commands, and verification steps

### REQ-009: Firefox browser service deployed in container-services category
The homelab SHALL provide a lightweight self-hosted browser capability through a containerised Firefox instance at `containerServices/firefox/`, joining `container_network` and accessible via Nginx Proxy Manager and directly on host port 3000.

#### Scenario: Firefox access via NPM or direct
- **GIVEN** the relevant infrastructure configuration and deployment state are available for inspection
- **WHEN** a user accesses Firefox via Nginx Proxy Manager or directly on host port 3000
- **THEN** the noVNC Firefox interface is displayed over HTTP
- **AND** the user can interact with an isolated browser session streamed to their browser

#### Scenario: Firefox joins container_network via default network alias
- **GIVEN** `containerServices/firefox/docker-compose.yml` is inspected
- **WHEN** the top-level `networks:` block is reviewed
- **THEN** `default` SHALL be declared as an external network with `name: container_network`
- **AND** the `firefox` container SHALL appear in `docker network inspect container_network`

#### Scenario: Firefox container is accessible via NPM proxy host
- **GIVEN** an NPM proxy host is configured pointing to `http://firefox:5800`
- **WHEN** a user accesses the Firefox domain
- **THEN** the noVNC Firefox interface SHALL be displayed
- **AND** the "WebSockets Support" toggle SHALL be enabled in the NPM proxy host configuration

### REQ-010: Host provisioning is separate from service setup
Host-wide provisioning scripts SHALL live under `scripts/host/`. The bootstrap
entry point SHALL resolve its helpers independently of the caller's working
directory and SHALL NOT start Compose stacks.

#### Scenario: An operator provisions the host from another directory
- **GIVEN** a sudo-capable non-root user on Ubuntu with systemd
- **WHEN** the operator invokes `scripts/host/bootstrap.sh` by absolute path
- **THEN** bootstrap SHALL locate its helpers and install or verify Docker with Compose v2 before using the `docker` group
- **AND** bootstrap SHALL NOT upgrade or autoremove unrelated packages, disable Wi-Fi, enroll Tailscale, or reboot the host

### REQ-011: GPU setup checks its host prerequisites
NVIDIA Docker setup SHALL require a working NVIDIA host driver and SHALL NOT
restart Docker. The AMD ROCm installer SHALL target Ubuntu 24.04 on WSL with
GPU passthrough and SHALL reject native Linux.

#### Scenario: The NVIDIA host driver is missing or not working
- **GIVEN** a host without a working NVIDIA driver
- **WHEN** the operator runs the NVIDIA Container Toolkit setup
- **THEN** the script SHALL exit with a prerequisite error before installing packages or changing Docker's runtime configuration

### REQ-012: Swap configuration is limited to the designated file
The swap script SHALL operate only on `/swapfile` and its matching persistence
entry. It SHALL preserve unrelated swap, leave a correctly configured active
file in place, and SHALL NOT resize or reformat an existing file.

#### Scenario: Existing swap configuration is valid
- **GIVEN** an active 8 GiB `/swapfile` with one valid persistent entry and another active swap device
- **WHEN** the operator reruns the swap script
- **THEN** it SHALL leave both swap devices active without recreating the file or duplicating its entry

### REQ-013: Syncthing is categorized under container services
The homelab SHALL classify Syncthing as a container-services workload located under `containerServices/syncthing/`.

#### Scenario: Service directory follows category placement
- **GIVEN** the relevant infrastructure configuration and deployment state are available for inspection
- **WHEN** the repository service layout is inspected
- **THEN** Syncthing compose and documentation files SHALL reside under `containerServices/syncthing/`

### REQ-014: Syncthing follows single-network isolation model
Syncthing SHALL use the container services network only and SHALL NOT join other category networks directly.

#### Scenario: Network declaration enforces isolation
- **GIVEN** the relevant infrastructure configuration and deployment state are available for inspection
- **WHEN** Syncthing compose configuration is inspected
- **THEN** the top-level `networks` block SHALL declare `container_network` as external
- **AND** the Syncthing service SHALL not declare membership in media, knowledge, security, finance, ai, or games networks

### REQ-015: Syncthing can be fronted by NPM gateway
Syncthing web access SHALL be compatible with the existing NPM gateway model.

#### Scenario: NPM-to-Syncthing routing is valid
- **GIVEN** the relevant infrastructure configuration and deployment state are available for inspection
- **WHEN** an NPM proxy host targets the Syncthing service container endpoint
- **THEN** the route SHALL resolve within `container_network`
- **AND** direct cross-category networking SHALL not be required
