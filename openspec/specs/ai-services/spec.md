## Requirements

### REQ-001: Ollama Local LLM Inference
The AI services stack SHALL provide local large language model inference through an Ollama container named `ollama`.

#### Scenario: Inference executes locally without external API calls
- **GIVEN** the `ollama` container is running and connected to `ai_network`
- **WHEN** a user or service requests LLM inference
- **THEN** Ollama SHALL execute the model locally
- **AND** results SHALL be returned without any external API calls

### REQ-002: Open WebUI Chat Interface
The AI services stack SHALL provide a web-based AI chat interface through an Open WebUI container named `openwebui`.

#### Scenario: Open WebUI presents chat interface
- **GIVEN** the `openwebui` container is running and connected to `ai_network`
- **WHEN** a user accesses the Open WebUI service
- **THEN** the chat interface SHALL be displayed
- **AND** users SHALL be able to interact with locally-running LLM models via Ollama

### REQ-003: GPU Acceleration (Opt-In)
The Ollama service SHALL support opt-in GPU acceleration for NVIDIA (CUDA) and AMD (ROCm) GPUs via commented-out blocks in `aiServices/ollama/docker-compose.yml`; the default state SHALL be CPU-only.

#### Scenario: CPU-only mode is the default
- **GIVEN** all GPU blocks in `aiServices/ollama/docker-compose.yml` are commented out
- **WHEN** `docker compose up -d` is run
- **THEN** Ollama SHALL start in CPU-only mode
- **AND** no GPU-specific configuration SHALL be applied

#### Scenario: NVIDIA GPU acceleration is enabled
- **GIVEN** an NVIDIA GPU is available and the NVIDIA `deploy.resources.reservations` block is uncommented
- **WHEN** the container is recreated
- **THEN** Ollama SHALL use NVIDIA GPU acceleration via the NVIDIA Container Toolkit
- **AND** inference performance SHALL be significantly improved over CPU-only mode

#### Scenario: AMD ROCm GPU acceleration is enabled
- **GIVEN** an AMD ROCm-capable GPU is available and the AMD `deploy.resources.reservations` block is uncommented
- **WHEN** the container is recreated
- **THEN** Ollama SHALL use AMD GPU acceleration
- **AND** inference performance SHALL be significantly improved over CPU-only mode

### REQ-004: Multi-Model Support
The Ollama service SHALL support concurrent loading and switching of multiple AI models.

#### Scenario: Multiple models are available for inference
- **GIVEN** more than one model has been pulled into `ollama_data`
- **WHEN** a user requests a different model than the currently loaded one
- **THEN** Ollama SHALL load the requested model
- **AND** serve inference requests against it

### REQ-005: Offline Operation
The AI services stack SHALL continue to function for local inference when internet connectivity is unavailable.

#### Scenario: Inference operates without internet
- **GIVEN** the `ollama` container has at least one model already present in `ollama_data`
- **WHEN** outbound internet connectivity is unavailable
- **THEN** Ollama SHALL continue to serve inference requests
- **AND** no degradation in already-downloaded model availability SHALL occur

### REQ-006: AI Network Isolation
All AI services SHALL connect to the `ai_network` Docker network for inference traffic, and SHALL only join additional networks for explicitly documented integration or egress purposes (e.g. Open WebUI's `security_network` proxied-egress membership per REQ-035). Open WebUI SHALL connect only to `ai_network` and `security_network` and SHALL NOT join `knowledge_network`.

#### Scenario: AI services communicate within ai_network
- **GIVEN** the Ollama and Open WebUI containers are running
- **WHEN** Open WebUI sends an inference request to Ollama
- **THEN** the communication SHALL occur entirely within `ai_network`
- **AND** no undocumented cross-network leakage to other category networks SHALL occur

#### Scenario: Open WebUI limits network membership
- **GIVEN** `aiServices/openwebui/docker-compose.yml` defines the Open WebUI service
- **WHEN** the service network references and top-level network declarations are inspected
- **THEN** both SHALL contain only `ai_network` and `security_network`
- **AND** neither SHALL contain `knowledge_network`

### REQ-007: Independent Service Deployment
Ollama and Open WebUI SHALL each have their own dedicated Docker Compose file and service directory, enabling independent lifecycle management.

#### Scenario: Restarting Ollama does not affect Open WebUI
- **GIVEN** both containers are running
- **WHEN** an operator restarts the Ollama service
- **THEN** only the `ollama` container SHALL be affected
- **AND** the `openwebui` container SHALL continue running uninterrupted

#### Scenario: Updating Open WebUI does not affect Ollama
- **GIVEN** both containers are running
- **WHEN** an operator recreates the Open WebUI container
- **THEN** only the `openwebui` container SHALL be recreated
- **AND** the `ollama` container and its loaded models SHALL be unaffected

### REQ-008: Network-Level Service Discovery
Open WebUI SHALL connect to Ollama exclusively via Docker internal DNS on `ai_network` using `OLLAMA_BASE_URL=http://ollama:11434`; no `depends_on` coupling between the two services SHALL be used.

#### Scenario: Open WebUI resolves Ollama via DNS
- **GIVEN** both containers are on `ai_network` and `OLLAMA_BASE_URL` is set to `http://ollama:11434`
- **WHEN** Open WebUI starts
- **THEN** it SHALL resolve the `ollama` hostname via `ai_network` internal DNS
- **AND** inference requests SHALL be forwarded to the Ollama container successfully

#### Scenario: Open WebUI retries if Ollama is not yet ready
- **GIVEN** Open WebUI starts before Ollama is fully initialised
- **WHEN** the initial connection attempt to Ollama fails
- **THEN** Open WebUI SHALL retry the connection automatically
- **AND** the service SHALL become fully functional once Ollama is reachable

### REQ-009: Ollama External Named Volume
The Ollama service SHALL use a named external Docker volume `ollama_data` mounted at `/root/.ollama` for persistent model storage.

#### Scenario: Ollama data volume is referenced as external
- **GIVEN** `aiServices/ollama/docker-compose.yml` is deployed
- **WHEN** `docker volume ls` is run
- **THEN** a volume named `ollama_data` SHALL exist and be mounted by the `ollama` container

#### Scenario: Compose down preserves model data
- **GIVEN** models are present in `ollama_data`
- **WHEN** `docker compose down` is run in `aiServices/ollama/`
- **THEN** the `ollama_data` external volume SHALL be preserved
- **AND** all downloaded model files SHALL remain intact

### REQ-010: Open WebUI External Named Volume
The Open WebUI service SHALL use a named external Docker volume `openwebui_filedata` for persistent user data.

#### Scenario: Open WebUI data volume is referenced as external
- **GIVEN** `aiServices/openwebui/docker-compose.yml` is deployed
- **WHEN** `docker volume ls` is run
- **THEN** a volume named `openwebui_filedata` SHALL exist and be mounted by the `openwebui` container

#### Scenario: Compose down preserves Open WebUI user data
- **GIVEN** user data is present in `openwebui_filedata`
- **WHEN** `docker compose down` is run in `aiServices/openwebui/`
- **THEN** the `openwebui_filedata` external volume SHALL be preserved

### REQ-011: Ollama Health Check
The `ollama` container SHALL define a Docker health check using `ollama list` to verify the service is responsive.

#### Scenario: Ollama health check reports healthy
- **GIVEN** the `ollama` container is running and the Ollama server has started
- **WHEN** the health check interval elapses
- **THEN** `ollama list` SHALL succeed
- **AND** the container status SHALL be reported as `healthy` in `docker ps`

### REQ-012: Open WebUI Health Check
The `openwebui` container SHALL define a Docker health check using an HTTP request to the root endpoint.

#### Scenario: Open WebUI health check reports healthy
- **GIVEN** the `openwebui` container is running and the web server has started
- **WHEN** the health check interval elapses
- **THEN** the HTTP request to `http://localhost:8080/` SHALL succeed
- **AND** the container status SHALL be reported as `healthy` in `docker ps`

### REQ-013: Container Security Hardening
Both the `ollama` and `openwebui` containers SHALL apply `security_opt: no-new-privileges` and `cap_drop: ALL`. The `ollama` container SHALL additionally include `cap_add: SYS_NICE` to permit GPU scheduling priority adjustments.

#### Scenario: Open WebUI runs with minimal capabilities
- **GIVEN** the `openwebui` container is running
- **WHEN** the container runtime configuration is inspected
- **THEN** `no-new-privileges` SHALL be enforced
- **AND** all Linux capabilities SHALL be dropped

#### Scenario: Ollama runs with minimal capabilities plus SYS_NICE
- **GIVEN** the `ollama` container is running
- **WHEN** the container runtime configuration is inspected
- **THEN** `no-new-privileges` SHALL be enforced
- **AND** all Linux capabilities SHALL be dropped except `SYS_NICE`
- **AND** `SYS_NICE` SHALL be explicitly added to permit GPU scheduling priority

### REQ-014: Environment Variable Externalisation
Both AI service directories SHALL include a `.env.example` file documenting all configurable environment variables with safe default values, so operators have a committed reference copy, and service documentation SHALL reference `.env.example` as the bootstrap source.

#### Scenario: Operator bootstraps Ollama configuration from reference
- **GIVEN** an operator copies `aiServices/ollama/.env.example` to `aiServices/ollama/.env`
- **WHEN** `docker compose up -d` is run in `aiServices/ollama/`
- **THEN** all Ollama configuration variables SHALL have documented defaults
- **AND** the service SHALL start successfully using those values

#### Scenario: Operator bootstraps Open WebUI configuration from reference
- **GIVEN** an operator copies `aiServices/openwebui/.env.example` to `aiServices/openwebui/.env`
- **WHEN** `docker compose up -d` is run in `aiServices/openwebui/`
- **THEN** all Open WebUI configuration variables SHALL have documented defaults
- **AND** the service SHALL start successfully using those values

#### Scenario: AI service documentation uses consistent bootstrap source
- **GIVEN** an operator follows setup instructions in AI service documentation
- **WHEN** environment bootstrap commands are reviewed
- **THEN** setup guidance SHALL reference copying from `.env.example`
- **AND** setup guidance SHALL NOT reference `.env.backup`

### REQ-015: Ollama Service Documentation
The `aiServices/ollama/` directory SHALL contain a `SERVICE_DOCUMENTATION.md` covering start/stop procedures, log inspection, health verification, and basic troubleshooting.

#### Scenario: Operator finds Ollama documentation
- **GIVEN** an operator needs to manage the Ollama service
- **WHEN** `aiServices/ollama/SERVICE_DOCUMENTATION.md` is opened
- **THEN** it SHALL contain sections for start, stop, logs, and troubleshooting

### REQ-016: Open WebUI Service Documentation
The `aiServices/openwebui/` directory SHALL contain a `SERVICE_DOCUMENTATION.md` covering start/stop procedures, log inspection, health verification, and basic troubleshooting.

#### Scenario: Operator finds Open WebUI documentation
- **GIVEN** an operator needs to manage the Open WebUI service
- **WHEN** `aiServices/openwebui/SERVICE_DOCUMENTATION.md` is opened
- **THEN** it SHALL contain sections for start, stop, logs, and troubleshooting

### REQ-017: Persistent Ollama Model Storage
The `ollama` container SHALL mount `ollama_data` at `/root/.ollama` to ensure downloaded model files are preserved across container restarts and recreations.

#### Scenario: Models survive container recreation
- **GIVEN** models have been downloaded into `ollama_data`
- **WHEN** an operator runs `docker compose up -d --force-recreate` in `aiServices/ollama/`
- **THEN** the `ollama_data` volume SHALL be remounted to the new container
- **AND** previously downloaded models SHALL be immediately available without re-pulling

#### Scenario: Missing ollama_data volume causes compose to error clearly
- **GIVEN** `ollama_data` does not exist on the host
- **WHEN** `docker compose up -d` is run in `aiServices/ollama/`
- **THEN** Docker SHALL refuse to start and SHALL report a clear error that the external volume does not exist

### REQ-018: Automatic Model Preload on Startup
The Ollama container SHALL automatically pull any models listed in `OLLAMA_MODELS_TO_PRELOAD` at startup if those models are not already present in `ollama_data`.

#### Scenario: Model is preloaded on first boot
- **GIVEN** the Ollama container starts with `OLLAMA_MODELS_TO_PRELOAD=llama3.2:3b` and `llama3.2:3b` is not in `ollama_data`
- **WHEN** the init script runs at container startup
- **THEN** `llama3.2:3b` SHALL be pulled from the Ollama model registry
- **AND** the model SHALL be available for inference once the pull completes

#### Scenario: Already-present model is not re-pulled
- **GIVEN** `llama3.2:3b` already exists in `ollama_data`
- **WHEN** the Ollama container restarts
- **THEN** the init script SHALL skip the pull for that model
- **AND** container startup SHALL complete without downloading any data

#### Scenario: Pull failure does not block Ollama startup
- **GIVEN** a model in `OLLAMA_MODELS_TO_PRELOAD` fails to pull (e.g., invalid name, network unavailable)
- **WHEN** the init script encounters the failure
- **THEN** the failure SHALL be logged
- **AND** the Ollama server SHALL start successfully and serve any already-available models

#### Scenario: Multiple models are preloaded in sequence
- **GIVEN** `OLLAMA_MODELS_TO_PRELOAD` contains a comma-separated list (e.g., `llama3.2:3b,nomic-embed-text`)
- **WHEN** the init script runs
- **THEN** each model SHALL be pulled in sequence
- **AND** all successfully pulled models SHALL be available for inference

### REQ-019: Configurable Inference Parallelism
The Ollama service SHALL expose `OLLAMA_NUM_PARALLEL` as an environment variable sourced from `.env` to control the number of concurrent inference requests handled simultaneously.

#### Scenario: Parallelism of 1 queues excess requests
- **GIVEN** `OLLAMA_NUM_PARALLEL=1` is set in the environment
- **WHEN** multiple concurrent inference requests arrive
- **THEN** Ollama SHALL process one request at a time
- **AND** additional requests SHALL be queued, preventing OOM on memory-constrained hosts

#### Scenario: Parallelism value is sourced from .env
- **GIVEN** `OLLAMA_NUM_PARALLEL` is defined in `.env`
- **WHEN** `docker compose up -d` is run
- **THEN** the compose file SHALL inject it into the container environment without hardcoding the value

### REQ-020: Configurable Model Keep-Alive Duration
The Ollama service SHALL expose `OLLAMA_KEEP_ALIVE` as an environment variable sourced from `.env` to control how long a loaded model remains in VRAM between requests before being evicted.

#### Scenario: Model stays loaded during active use window
- **GIVEN** `OLLAMA_KEEP_ALIVE=15m` is configured and a user is sending requests within 15-minute intervals
- **WHEN** a subsequent inference request arrives within the keep-alive window
- **THEN** the model SHALL remain loaded in VRAM
- **AND** the request SHALL be served with low latency (no cold-load delay)

#### Scenario: Model is evicted after idle period
- **GIVEN** no inference request is received for longer than the keep-alive duration
- **WHEN** the keep-alive timer expires
- **THEN** Ollama SHALL evict the model from VRAM
- **AND** VRAM SHALL be freed for other processes

### REQ-021: Configurable Maximum Loaded Models
The Ollama service SHALL expose `OLLAMA_MAX_LOADED_MODELS` as an environment variable sourced from `.env` to cap the number of models simultaneously resident in VRAM.

#### Scenario: Single model limit enforced on constrained GPU
- **GIVEN** `OLLAMA_MAX_LOADED_MODELS=1` is configured and one model is already loaded
- **WHEN** a user requests a different model
- **THEN** Ollama SHALL evict the currently loaded model before loading the requested one
- **AND** total VRAM usage SHALL remain within the GPU's capacity

### REQ-022: Optional Ollama Memory Limit Configuration
The Ollama service SHALL allow operators to configure a Docker memory limit via `${OLLAMA_MEMORY_LIMIT}` sourced from `.env` and enabled through documented compose toggles, while the default deployment SHALL remain unconstrained.

#### Scenario: Default deployment remains unconstrained
- **GIVEN** the default `aiServices/ollama/docker-compose.yml` configuration is used
- **WHEN** the service is inspected before optional limit toggles are enabled
- **THEN** no active Docker memory limit SHALL be enforced for `ollama`
- **AND** the service SHALL be allowed to use available host resources

#### Scenario: Memory limit value can be enabled from .env
- **GIVEN** `OLLAMA_MEMORY_LIMIT` is defined in `.env`
- **WHEN** optional limit toggles are enabled and `docker compose up -d --force-recreate` is run
- **THEN** Docker SHALL enforce the configured memory cap on the container
- **AND** changing the value in `.env` SHALL take effect on the next container recreation

### REQ-023: AI Backup Coverage Policy
The AI services backup policy SHALL include `openwebui_filedata` in automated filedata backups and SHALL NOT include `ollama_data` in automated filedata backups.

#### Scenario: Open WebUI volume is included in backup service
- **GIVEN** `backupServices/filedata/backup-volumes.conf` defines the host selections
- **WHEN** the default and Local selections are inspected
- **THEN** `openwebui_filedata` SHALL be mounted read-only for backup processing
- **AND** scheduled backup variables for Open WebUI SHALL be defined in backup environment configuration

#### Scenario: Ollama model volume is excluded from backup service
- **GIVEN** `backupServices/filedata/backup-volumes.conf` defines registered backup sources
- **WHEN** the filedata-backup service configuration is inspected
- **THEN** `ollama_data` SHALL NOT be mounted as a backup source
- **AND** no automated backup schedule for `ollama_data` SHALL be required

### REQ-024: AI Service Rolling Image Channels
The `ollama` and `openwebui` services SHALL use rolling image channels in their compose definitions.

#### Scenario: Ollama image uses implicit latest channel
- **GIVEN** `aiServices/ollama/docker-compose.yml` defines the `ollama` service image
- **WHEN** the image reference is validated
- **THEN** the image reference SHALL be `ollama/ollama`
- **AND** no explicit version tag SHALL be pinned

#### Scenario: Open WebUI image uses main channel
- **GIVEN** `aiServices/openwebui/docker-compose.yml` defines the `openwebui` service image
- **WHEN** the image reference is validated
- **THEN** the image reference SHALL be `ghcr.io/open-webui/open-webui:main`
- **AND** operators SHALL be able to temporarily pin a prior known-good version for rollback

### REQ-025: n8n Workflow Automation Service
The AI services stack SHALL provide workflow automation through an n8n container named `n8n`.

#### Scenario: n8n service starts successfully
- **GIVEN** `aiServices/n8n/docker-compose.yml` is deployed with the required external `ai_network` and `n8n_filedata` volume
- **WHEN** the n8n stack is started
- **THEN** the `n8n` container SHALL start successfully
- **AND** the service SHALL listen on port `5678` inside the container
- **AND** the container healthcheck SHALL report `healthy` when `http://127.0.0.1:5678/healthz` responds successfully

### REQ-026: SQLite Database for n8n
The n8n stack SHALL use the default SQLite database stored within the persistent `n8n_filedata` volume.

#### Scenario: n8n stores workflow metadata in SQLite
- **GIVEN** the `n8n_filedata` volume is mounted at `/home/node/.n8n`
- **WHEN** n8n creates or updates workflows
- **THEN** workflow metadata SHALL be stored in the SQLite database within that volume

### REQ-027: n8n Reverse Proxy Reachability
The `n8n` container SHALL attach to `ai_network` so it can be reached by Nginx Proxy Manager and other authorized AI services.

#### Scenario: NPM reaches n8n over ai_network
- **GIVEN** both `npm` and `n8n` containers are attached to `ai_network`
- **WHEN** NPM proxies traffic to `http://n8n:5678`
- **THEN** requests SHALL be routable to n8n
- **AND** reverse proxy responses SHALL be served without upstream connectivity errors

### REQ-028: n8n Persistent Storage
The n8n stack SHALL persist application state and SQLite data using the named external volume `n8n_filedata`.

#### Scenario: n8n data survives container recreation
- **GIVEN** workflows and credentials are stored in the service
- **WHEN** `docker compose down` and `docker compose up -d` are run for n8n
- **THEN** previously stored n8n data SHALL remain available

### REQ-031: n8n Environment Bootstrap Reference
The n8n service directory SHALL include a committed `.env.example` file documenting that no PostgreSQL credentials are required for the default SQLite deployment.

#### Scenario: Operator bootstraps n8n env from reference file
- **GIVEN** an operator copies `aiServices/n8n/.env.example` to `aiServices/n8n/.env`
- **WHEN** `docker compose up -d` is run in `aiServices/n8n/`
- **THEN** the stack SHALL start without PostgreSQL variables or missing variable interpolation errors

### REQ-032: n8n Service Documentation
The `aiServices/n8n/` directory SHALL contain `SERVICE_DOCUMENTATION.md` covering setup, start/stop commands, logs, health checks, and troubleshooting.

#### Scenario: Operator finds n8n operations guidance
- **GIVEN** an operator needs to manage n8n
- **WHEN** `aiServices/n8n/SERVICE_DOCUMENTATION.md` is opened
- **THEN** it SHALL include operational commands and verification steps
- **AND** it SHALL document NPM proxy target settings for n8n

### REQ-033: n8n Restore Procedure Documentation
The `aiServices/n8n/` directory SHALL contain an executable `restore.sh` and a `RESTORE_GUIDE.md` that presents the script as the primary filedata-only restore workflow.

#### Scenario: Operator restores n8n from encrypted backups
- **GIVEN** an encrypted backup of `n8n_filedata` is available
- **WHEN** the operator runs `aiServices/n8n/restore.sh`
- **THEN** filedata SHALL be restored into `n8n_filedata`
- **AND** the restored SQLite database SHALL be available when n8n starts
- **AND** the script SHALL verify that n8n is running after the restore

#### Scenario: Operator uses manual restore fallback
- **GIVEN** the automated restore script cannot be used
- **WHEN** the operator follows the manual steps in `RESTORE_GUIDE.md`
- **THEN** the encrypted filedata archive SHALL be restored into `n8n_filedata`
- **AND** n8n SHALL be started and verified after the restore

### REQ-034: Ollama Resource Constraints Are Optional
The Ollama service SHALL run without enforced resource limits by default, and SHALL provide an optional env-driven path to enable resource constraints quickly when needed.

#### Scenario: Default Ollama deployment has no enforced limit
- **GIVEN** `aiServices/ollama/docker-compose.yml` is used in its default state
- **WHEN** the service configuration is inspected
- **THEN** no active memory or CPU limit SHALL be enforced for `ollama`
- **AND** the service SHALL be allowed to use available host resources

#### Scenario: Operator can quickly enable Ollama limits
- **GIVEN** an operator needs to constrain Ollama on a resource-limited host
- **WHEN** they update values in `aiServices/ollama/.env.example` and enable the documented optional limit configuration
- **THEN** the container SHALL apply the configured limits after recreation
- **AND** the change SHALL not require redesign of compose structure

### REQ-035: OpenWebUI Proxied External Egress via Gluetun
Open WebUI SHALL route external HTTP(S) egress through the Gluetun VPN proxy at `gluetun:8888` using lowercase `http_proxy` and `https_proxy` environment variables, SHALL join `security_network` to reach this endpoint, and SHALL exempt internal hosts via lowercase `no_proxy`.

#### Scenario: External API calls exit through the VPN
- **GIVEN** `openwebui` is on `security_network` with lowercase `http_proxy` and `https_proxy` set to `http://gluetun:8888`
- **WHEN** Open WebUI makes an outbound call to an external API (e.g. an OpenAI-compatible endpoint)
- **THEN** the request SHALL be tunneled through the `gluetun` container's HTTP proxy
- **AND** the request SHALL exit via Gluetun's ProtonVPN WireGuard tunnel

#### Scenario: Internal traffic bypasses the VPN proxy
- **GIVEN** lowercase `no_proxy` includes `ollama` and `openwebui`
- **WHEN** Open WebUI communicates with Ollama on `ai_network` or serves its own healthcheck
- **THEN** that traffic SHALL NOT be routed through `gluetun:8888`
- **AND** inference and healthcheck behavior SHALL be unaffected by the VPN proxy configuration

### REQ-036: OmniRoute AI Gateway
The AI services stack SHALL provide an OmniRoute gateway container named `omniroute` using the published Docker image and listening on port `20128`.

#### Scenario: Operator reaches OmniRoute on the AI network
- **GIVEN** the `omniroute` container is running and attached to `ai_network`
- **WHEN** an authorized client sends a request to `http://omniroute:20128/v1`
- **THEN** OmniRoute SHALL expose its OpenAI-compatible API to that client
- **AND** the dashboard SHALL be available on the same container port

### REQ-037: OmniRoute API Authentication
The OmniRoute service SHALL require API keys for API requests and SHALL disable API key reveal.

#### Scenario: Unauthenticated API request is rejected
- **GIVEN** `REQUIRE_API_KEY=true` is configured for OmniRoute
- **WHEN** a client sends an API request without a valid API key
- **THEN** OmniRoute SHALL reject the request

### REQ-038: OmniRoute Persistent Data
The OmniRoute service SHALL use the external Docker volume `omniroute_filedata` mounted at `/app/data` for persistent application data and provider credentials.

#### Scenario: OmniRoute data survives container recreation
- **GIVEN** OmniRoute application data is stored in `omniroute_filedata`
- **WHEN** the container is recreated
- **THEN** the database, provider configuration, and stored credentials SHALL remain available

### REQ-039: OmniRoute Network Isolation
The OmniRoute container SHALL attach to `ai_network` and `security_network` and SHALL NOT publish its application port directly on the host.

#### Scenario: OmniRoute is reached through the internal network
- **GIVEN** Nginx Proxy Manager and OmniRoute are attached to `ai_network`
- **WHEN** NPM proxies a request to `http://omniroute:20128`
- **THEN** the request SHALL reach the OmniRoute dashboard
- **AND** no host-published port SHALL bypass the configured reverse proxy

### REQ-040: OmniRoute Encrypted Backup Coverage
The AI services backup policy SHALL include `omniroute_filedata` in encrypted filedata backups.

#### Scenario: Provider credentials are included in encrypted backups
- **GIVEN** OmniRoute stores provider credentials in `omniroute_filedata`
- **WHEN** the scheduled filedata backup runs
- **THEN** the volume SHALL be backed up using the configured encrypted backup workflow
- **AND** the OmniRoute backup job SHALL be present only in profiles where OmniRoute is deployed

### REQ-041: OmniRoute Operations and Restore Documentation
The `aiServices/omniroute/` directory SHALL contain a `QUICKSTART_GUIDE.md`, service documentation, an executable `restore.sh`, and a `RESTORE_GUIDE.md` describing the filedata-only recovery workflow.

#### Scenario: Operator can manage and restore OmniRoute
- **GIVEN** an operator needs to deploy, troubleshoot, or restore OmniRoute
- **WHEN** the operator follows the service documentation and restore guide
- **THEN** the documented commands SHALL cover deployment, health verification, encrypted data recovery, and post-restore verification

### REQ-042: OmniRoute External Egress via Gluetun
OmniRoute SHALL route external upstream HTTP(S) provider calls through the Gluetun HTTP proxy at `gluetun:8888`, SHALL join `security_network` to reach the proxy, SHALL bypass the proxy for local hosts, and SHALL NOT fall back to direct egress when the proxy is unavailable.

#### Scenario: External provider traffic uses Gluetun
- **GIVEN** OmniRoute is attached to `security_network` with `HTTP_PROXY` and `HTTPS_PROXY` set to `http://gluetun:8888`
- **WHEN** OmniRoute makes an upstream request to an external provider
- **THEN** the request SHALL use the Gluetun HTTP proxy
- **AND** the request SHALL exit through the Gluetun VPN tunnel

#### Scenario: Local traffic bypasses the proxy
- **GIVEN** `NO_PROXY` includes `localhost`, `127.0.0.1`, `omniroute`, and `ollama`
- **WHEN** OmniRoute performs a local healthcheck or communicates with Ollama
- **THEN** the traffic SHALL bypass the Gluetun proxy

#### Scenario: Gluetun proxy is unavailable
- **GIVEN** `PROXY_FAIL_OPEN=false` and the Gluetun HTTP proxy is unavailable
- **WHEN** OmniRoute makes an upstream provider request
- **THEN** the request SHALL fail without direct-egress fallback

### REQ-043: Authenticated Hermes Dashboard
The Hermes service SHALL enable its dashboard with credentials supplied through `HERMES_DASHBOARD_BASIC_AUTH_USERNAME` and `HERMES_DASHBOARD_BASIC_AUTH_PASSWORD`, and SHALL connect to `ai_network` and `security_network` for NPM access without publishing the dashboard port on the host.

#### Scenario: Dashboard is reachable through NPM
- **GIVEN** Hermes and NPM are running on a shared network and dashboard credentials are configured
- **WHEN** NPM proxies HTTP requests to `hermes:9119`
- **THEN** the dashboard SHALL respond to the requests
- **AND** authentication SHALL be required for dashboard access

#### Scenario: Dashboard credentials are externalized
- **GIVEN** an operator inspects the Hermes Compose configuration and `.env.example`
- **WHEN** dashboard authentication variables are reviewed
- **THEN** Compose SHALL obtain the username and password from the environment
- **AND** `.env.example` SHALL contain placeholders rather than actual credentials

### REQ-044: Hermes Dashboard Operations Documentation
The Hermes service directory SHALL contain documentation covering environment setup, NPM proxy settings, service lifecycle, verification, and dashboard startup troubleshooting.

#### Scenario: Operator diagnoses an unavailable dashboard
- **GIVEN** the Hermes dashboard is unreachable through NPM
- **WHEN** the operator consults `aiServices/hermes/SERVICE_DOCUMENTATION.md`
- **THEN** the documentation SHALL describe how to check connectivity and dashboard startup logs
- **AND** it SHALL identify missing dashboard authentication as a possible cause

### REQ-045: OpenCode Isolated Coding Agent Service
The AI services category SHALL define OpenCode as an independently managed
container built from the pinned `opencode-ai` package version, connected to
`ai_network`, with only the configured Obsidian vault bind-mounted at
`/workspace`. OpenCode session, configuration, and cache data SHALL NOT be
persisted in a Docker volume. The Compose service SHALL NOT set `cap_drop` or
`security_opt`, retaining Docker's default capability and privilege settings
for cloud model provider access. OpenCode SHALL NOT receive Docker socket
access.

#### Scenario: OpenCode service mounts only the Obsidian vault
- **GIVEN** `aiServices/opencode/docker-compose.yml` is deployed with its web
  runtime enabled
- **WHEN** the container configuration is inspected
- **THEN** the container SHALL be attached to `ai_network`
- **AND** the configured Obsidian vault SHALL be mounted at `/workspace`
- **AND** no Docker volume or other host directory SHALL be mounted
- **AND** `cap_drop` and `security_opt` SHALL NOT be configured
- **AND** the Docker socket SHALL NOT be mounted

#### Scenario: OpenCode accesses cloud model providers
- **GIVEN** the OpenCode container uses Docker's default capability and
  privilege settings
- **WHEN** OpenCode makes an outbound request to a configured cloud model provider
- **THEN** OpenCode SHALL be able to establish an outbound connection to that
  provider

#### Scenario: OpenCode web server requires authentication
- **GIVEN** the OpenCode web runtime is enabled
- **WHEN** the service starts
- **THEN** a non-empty `OPENCODE_SERVER_PASSWORD` SHALL be required
- **AND** the web server SHALL use HTTP Basic authentication
- **AND** any published host port SHALL bind to `127.0.0.1`

#### Scenario: Operator grants access to a project workspace
- **GIVEN** an operator intends OpenCode to inspect or edit a project
- **WHEN** the project is selected for use
- **THEN** the operator SHALL explicitly bind-mount the authorized project
  directory at `/workspace`
- **AND** project files SHALL NOT be exposed through an implicit host mount

#### Scenario: Operator uses Git in the mounted vault
- **GIVEN** the OpenCode image has been built and the container is running
- **WHEN** the operator runs `docker exec opencode git --version`
- **THEN** Git SHALL be available to the configured non-root user and report its version
- **AND** the image SHALL include Git without requiring package installation at container startup

### REQ-046: OpenCode Operational and Restore Documentation
The `aiServices/opencode/` directory SHALL contain service documentation and
a restore guide covering environment setup, workspace access, authentication,
the ephemeral nature of container data, and vault recovery using its
host-level backup process.

#### Scenario: Operator prepares and accesses OpenCode
- **GIVEN** an operator follows `aiServices/opencode/SERVICE_DOCUMENTATION.md`
- **WHEN** they prepare the service for use
- **THEN** the guide SHALL direct them to create `.env` from `.env.example`
- **AND** the guide SHALL explain how to configure the Obsidian vault mount
- **AND** the guide SHALL document authentication and network access

#### Scenario: Operator restores the Obsidian vault
- **GIVEN** an operator needs to recover OpenCode's working files
- **WHEN** an operator follows `aiServices/opencode/RESTORE_GUIDE.md`
- **THEN** the guide SHALL direct them to restore the vault using its
  host-level backup process
- **AND** the guide SHALL explain that OpenCode session data is not persisted
- **AND** the guide SHALL include concrete service and workspace verification

### REQ-047: Gemini CLI Coding Agent
The AI services stack SHALL provide a persistent Gemini CLI utility container named `gemini` that uses the Obsidian vault mounted at `/workspace` as its working directory and authenticates using `GEMINI_API_KEY` supplied through a local environment file.

#### Scenario: Operator starts the Gemini utility container
- **GIVEN** the operator has configured `aiServices/gemini/.env` and the external `ai_network` exists
- **WHEN** the operator runs `docker compose up -d gemini` from `aiServices/gemini/`
- **THEN** the `gemini` container SHALL remain running and available to `docker exec`
- **AND** its default working directory SHALL be `/workspace`

#### Scenario: Operator starts Gemini CLI in the Obsidian vault
- **GIVEN** the `gemini` container is running
- **WHEN** the operator runs `docker exec -it gemini gemini`
- **THEN** Gemini CLI SHALL start with `/workspace` as its working directory
- **AND** changes to workspace files SHALL be reflected in the host Obsidian vault

#### Scenario: Gemini CLI runs with constrained container privileges
- **GIVEN** the Gemini CLI container is running
- **WHEN** its container configuration is inspected
- **THEN** it SHALL run as the configured non-root UID and GID
- **AND** it SHALL drop all Linux capabilities and enable `no-new-privileges`

#### Scenario: Operator uses Git in the mounted vault
- **GIVEN** the Gemini CLI image has been built and the container is running
- **WHEN** the operator runs `docker exec gemini git --version`
- **THEN** Git SHALL be available to the configured non-root user and report its version
- **AND** the image SHALL include Git without requiring package installation at container startup

### REQ-048: Gemini CLI Obsidian Vault Access
The Gemini CLI service SHALL mount only the host Obsidian vault configured by `OBSIDIAN_VAULT_PATH` in `aiServices/gemini/.env` at `/workspace` with read/write access, SHALL NOT mount the homelab repository separately, and SHALL NOT create a missing host vault path.

#### Scenario: Gemini CLI accesses the configured Obsidian vault
- **GIVEN** `OBSIDIAN_VAULT_PATH` identifies the existing host Obsidian vault also used by OpenCode
- **WHEN** the operator starts Gemini CLI
- **THEN** the vault contents SHALL be available inside the container at `/workspace`
- **AND** changes made to vault files SHALL be reflected in the host vault

#### Scenario: Obsidian vault path is missing or invalid
- **GIVEN** `OBSIDIAN_VAULT_PATH` is unset or does not identify an existing host path
- **WHEN** the operator runs the Gemini Compose service
- **THEN** Compose SHALL report a configuration or mount error
- **AND** Compose SHALL NOT create a new host vault directory

### REQ-049: OpenWebUI Tier C Data Classification
The OpenWebUI data volume `openwebui_filedata` SHALL classify SQLite state and uploads as backup-essential for Tier C policy, and SHALL classify cache and vector index directories as rebuildable.

#### Scenario: Tier C classification is documented for operators
- **GIVEN** an operator reviews OpenWebUI backup and restore documentation
- **WHEN** data classes are listed
- **THEN** essential paths SHALL include `webui.db`, `webui.db-wal`, `webui.db-shm`, and `uploads/`
- **AND** rebuildable paths SHALL include `cache/` and `vector_db/`

### REQ-050: OpenWebUI Restore Documentation Script Priority
The OpenWebUI restore guide SHALL present `aiServices/openwebui/restore.sh` as the primary recovery workflow and manual command restore as fallback guidance.

#### Scenario: Operator follows restore guide primary path
- **GIVEN** an operator opens `aiServices/openwebui/RESTORE_GUIDE.md`
- **WHEN** they follow the documented procedure
- **THEN** the first-class restore path SHALL be script-led
- **AND** verification steps SHALL include explicit core-service readiness checks

### REQ-051: OpenWebUI Core Restore SLO
OpenWebUI restore operations SHALL target core service usability within 10 minutes from restore start to successful core verification.

#### Scenario: Restore drill validates core SLO target
- **GIVEN** a controlled OpenWebUI restore drill is executed
- **WHEN** phase timestamps are collected
- **THEN** total time to core readiness SHALL be measurable against a 10-minute objective
- **AND** SLO evaluation SHALL not require immediate RAG or vector availability
