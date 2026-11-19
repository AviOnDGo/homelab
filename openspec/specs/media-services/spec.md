## Purpose
Define the required behavior, service composition, and operational safeguards for the media services stack.
## Requirements

### REQ-001: Jellyfin Media Streaming
The media services stack SHALL provide media streaming capabilities through a Jellyfin container named `jellyfin`.

#### Scenario: Jellyfin serves media library
- **GIVEN** the `jellyfin` container is running and connected to `media_network`
- **WHEN** a user accesses the Jellyfin service
- **THEN** the Jellyfin web interface SHALL be presented
- **AND** users SHALL be able to stream media library content

### REQ-002: Sonarr TV Show Management
The media services stack SHALL automatically manage the TV show library through a Sonarr container named `sonarr`.

#### Scenario: Sonarr tracks and downloads new episodes
- **GIVEN** a TV show is configured for monitoring in Sonarr
- **WHEN** a new episode is released
- **THEN** Sonarr SHALL automatically discover and queue the episode for download
- **AND** the episode SHALL be organised in the TV media directory

### REQ-003: Radarr Movie Management
The media services stack SHALL automatically manage the movie library through a Radarr container named `radarr`.

#### Scenario: Radarr tracks and downloads new movies
- **GIVEN** a movie is configured for monitoring in Radarr
- **WHEN** a new movie release becomes available
- **THEN** Radarr SHALL automatically discover and queue the movie for download
- **AND** the movie SHALL be organised in the movies media directory

### REQ-004: Jackett Torrent Indexing
The Jackett service SHALL be defined in `mediaServices/jackett/docker-compose.yml` as container `jackett`, persist `/config` in the external volume `jackett_filedata`, and connect to `media_network` and `security_network` for media access and HTTP(S) proxy access.

#### Scenario: Jackett provides search results to Sonarr and Radarr
- **GIVEN** Sonarr or Radarr needs to search for content
- **WHEN** a search request is issued
- **THEN** Jackett SHALL query configured torrent trackers
- **AND** SHALL return download links to the requesting service

#### Scenario: Jackett configuration survives container replacement
- **GIVEN** the Jackett stack uses `jackett_filedata` at `/config`
- **WHEN** the container is recreated
- **THEN** Jackett SHALL retain its configuration in that external volume

### REQ-005: Transmission BitTorrent Client
The Transmission service SHALL be defined in `mediaServices/transmission/docker-compose.yml` as container `transmission`, persist `/config` in the external volume `transmission_filedata`, and connect to `media_network` and `security_network`.

#### Scenario: Transmission downloads torrent content
- **GIVEN** a torrent is added for download
- **WHEN** Transmission processes the torrent
- **THEN** the content SHALL be downloaded and stored in the configured downloads directory
- **AND** the content SHALL be accessible to Sonarr and Radarr for post-processing

#### Scenario: Transmission web UI credentials are not hardcoded
- **GIVEN** the `mediaServices/transmission/docker-compose.yml` file is inspected
- **WHEN** the Transmission service definition is reviewed
- **THEN** no plaintext USER or PASS values SHALL appear in the compose file
- **AND** credentials SHALL be sourced via `mediaServices/transmission/.env`

#### Scenario: Transmission configuration survives container replacement
- **GIVEN** the Transmission stack uses `transmission_filedata` at `/config`
- **WHEN** the container is recreated
- **THEN** Transmission SHALL retain its configuration in that external volume

### REQ-006: Invidious Privacy-Focused YouTube Frontend
The media services stack SHALL provide a privacy-focused YouTube frontend through an Invidious container named `invidious`.

#### Scenario: Invidious serves YouTube content without tracking
- **GIVEN** the `invidious` container is running and connected to `media_network`
- **WHEN** a user accesses the Invidious service
- **THEN** the Invidious web interface SHALL be presented
- **AND** users SHALL be able to watch YouTube videos without direct Google tracking

### REQ-007: Media Network Membership and Approved Integrations
All media services SHALL connect to `media_network`. A media service SHALL join another Docker network only for an explicitly documented integration, such as proxied external egress through Gluetun.

#### Scenario: Media services communicate within media_network
- **GIVEN** two media services need to communicate
- **WHEN** a service-to-service request is made
- **THEN** the communication SHALL occur within `media_network`
- **AND** any additional network membership SHALL be limited to the service's documented integrations

### REQ-008: Shared Host-Path Media Volumes
Media content directories SHALL use host bind-mounts from `~/.media/` to share data across Jellyfin, Sonarr, Radarr, and Transmission.

#### Scenario: Downloaded content is accessible to all consumers
- **GIVEN** Transmission downloads content to `~/.media/.downloads`
- **WHEN** Sonarr or Radarr post-processes the download
- **THEN** the file SHALL be moved to `~/.media/TVSeries` or `~/.media/Movies` respectively
- **AND** Jellyfin SHALL immediately see the content in its library paths

### REQ-009: Invidious Service and Container Naming
The Invidious primary service SHALL be named `invidious` with `container_name: invidious`, and the PostgreSQL companion service SHALL be named `invidious-db` with `container_name: invidious-db`.

#### Scenario: Invidious primary service naming
- **GIVEN** the `mediaServices/invidious/docker-compose.yml` is deployed
- **WHEN** `docker ps` is run
- **THEN** a container named `invidious` SHALL be present

#### Scenario: Invidious database service naming
- **GIVEN** the `mediaServices/invidious/docker-compose.yml` is deployed
- **WHEN** `docker ps` is run
- **THEN** a container named `invidious-db` SHALL be present

### REQ-010: Invidious Companion Service Naming
The Invidious companion service SHALL use `companion` as the Docker service name and `invidious-companion` as the container name.

#### Scenario: Companion container is discoverable by its standardised name
- **GIVEN** the Invidious stack is deployed
- **WHEN** `docker ps` is run
- **THEN** a container named `invidious-companion` SHALL be present

### REQ-011: Invidious Security Keys via Environment Variables
The Invidious `INVIDIOUS_CONFIG` block and companion service SHALL NOT contain hardcoded security keys; all keys SHALL be sourced from environment variables.

#### Scenario: No literal keys in compose file
- **GIVEN** `mediaServices/invidious/docker-compose.yml` is inspected
- **WHEN** the `INVIDIOUS_CONFIG` block and companion `environment` section are reviewed
- **THEN** `invidious_companion_key` SHALL use `${INVIDIOUS_COMPANION_KEY}` substitution
- **AND** `hmac_key` SHALL use `${INVIDIOUS_HMAC_KEY}` substitution
- **AND** `SERVER_SECRET_KEY` SHALL use `${INVIDIOUS_COMPANION_KEY}` substitution

### REQ-012: Invidious Data Restoration Documentation
The `mediaServices/invidious/` directory SHALL contain a `RESTORE_GUIDE.md` that documents a script-first PostgreSQL restoration workflow aligned with Firefly/Firefox Sync operator UX.

#### Scenario: Restore guide defines script-first recovery
- **GIVEN** an operator needs to recover Invidious PostgreSQL data
- **WHEN** the operator follows `mediaServices/invidious/RESTORE_GUIDE.md`
- **THEN** the guide SHALL direct the operator to run `restore.sh` as the primary restore path
- **AND** SHALL document manual fallback steps for exceptional recovery cases

#### Scenario: Restore guide documents safety and failure posture
- **GIVEN** a restore operation can be destructive or fail mid-process
- **WHEN** safety behavior is described in `RESTORE_GUIDE.md`
- **THEN** the guide SHALL describe explicit confirmation before volume recreation
- **AND** SHALL state that on restore failure the stack is intentionally left down for manual inspection

### REQ-018: Immich Container Resource Limits
The `immich` server container and `immich-ml` container SHALL each have explicit Docker memory limits to prevent resource starvation of co-hosted services.

#### Scenario: Immich server memory is bounded
- **GIVEN** the `immich` container is running
- **WHEN** the container handles concurrent upload or job requests
- **THEN** Docker SHALL enforce the configured memory limit on the container

#### Scenario: Machine-learning container memory is bounded
- **GIVEN** `immich-ml` is running inference
- **WHEN** memory consumption approaches the configured limit
- **THEN** Docker SHALL enforce the limit without requiring manual intervention

### REQ-019: Immich Split Named External Volumes
The `immich` server container SHALL use three named external Docker volumes (`immich_library`, `immich_profile`, `immich_upload`) mounted at their respective sub-paths; no host bind-mount path variable SHALL be required.

#### Scenario: Three volumes are independently mountable
- **GIVEN** the Immich stack is deployed
- **WHEN** `docker volume ls` is run
- **THEN** `immich_library`, `immich_profile`, and `immich_upload` SHALL each appear in the output

### REQ-020: Immich Service and Container Naming
The Immich server service and container SHALL be named `immich`/`immich`. The ML, Redis, and PostgreSQL supporting services SHALL use aligned hyphenated service and container names: `immich-ml`/`immich-ml`, `immich-redis`/`immich-redis`, and `immich-db`/`immich-db`.

#### Scenario: Immich server container discoverable by name
- **GIVEN** the Immich stack is deployed
- **WHEN** `docker ps` is run
- **THEN** the Immich server container SHALL appear as `immich`

#### Scenario: Immich companion containers use aligned hyphenated names
- **GIVEN** the Immich stack is deployed
- **WHEN** `docker ps` is run
- **THEN** containers `immich-ml`, `immich-redis`, and `immich-db` SHALL be present
- **AND** each companion container name SHALL exactly match its service key

### REQ-021: Immich Port Exposure via NPM Only
The Immich server port 2283 SHALL NOT be exposed directly on the host interface; all external access SHALL route through Nginx Proxy Manager.

#### Scenario: Immich accessible via NPM reverse proxy
- **GIVEN** Nginx Proxy Manager is configured with an Immich proxy host pointing to `immich:2283`
- **WHEN** a user accesses Immich through the NPM proxy host
- **THEN** the request SHALL be forwarded to `immich:2283` inside `media_network` and the service SHALL respond normally

### REQ-022: Immich PostgreSQL Performance Tuning
The Immich `immich-db` container SHALL apply PostgreSQL performance tuning parameters via `-c` flags in the compose `command:` override.

#### Scenario: Shared buffers and cache size are configured
- **GIVEN** the `immich-db` container is running
- **WHEN** the PostgreSQL configuration is inspected
- **THEN** `shared_buffers` SHALL be set to at least 256MB
- **AND** `effective_cache_size` SHALL be set to at least 1GB
- **AND** `work_mem` SHALL be set to at least 64MB

#### Scenario: WAL and storage tuning are applied
- **GIVEN** the `immich-db` container is running
- **WHEN** the PostgreSQL configuration is inspected
- **THEN** `max_wal_size` SHALL be at least 1GB
- **AND** `random_page_cost` SHALL be 1.1 or lower

### REQ-023: Immich Redis/Valkey Memory Cap
The Immich Redis/Valkey container SHALL be configured with a maximum memory limit and `allkeys-lru` eviction policy.

#### Scenario: Memory limit is enforced
- **GIVEN** the `immich-redis` container is running
- **WHEN** memory usage approaches the configured limit
- **THEN** Redis SHALL evict least-recently-used keys
- **AND** SHALL NOT return OOM errors to the Immich server

### REQ-024: Immich NVIDIA acceleration for ML and transcoding
The Immich stack SHALL support NVIDIA GPU acceleration for both machine-learning inference and media transcoding when the host has the NVIDIA Container Toolkit installed. The `immich` server container SHALL use the NVENC transcoding backend. The `immich-ml` container SHALL use the CUDA backend when GPU VRAM is exclusively available; it SHALL fall back to the CPU-only image when another GPU-resident service (e.g. Ollama) would otherwise cause `CUBLAS_STATUS_ALLOC_FAILED` due to VRAM contention.

#### Scenario: Immich ML and transcoding use NVIDIA backends (no VRAM contention)
- **GIVEN** the host exposes an NVIDIA GPU through Docker
- **AND** no other service is occupying significant GPU VRAM (e.g. Ollama is stopped)
- **WHEN** the Immich stack is deployed
- **THEN** `immich-ml` SHALL run with the CUDA hardware-acceleration backend (`-cuda` image tag and `hwaccel.ml.yml` extends)
- **AND** `immich` SHALL run with the NVENC transcoding backend
- **AND** both containers SHALL rely on the NVIDIA Container Toolkit for GPU access

#### Scenario: Immich ML falls back to CPU when GPU VRAM is contested
- **GIVEN** a co-hosted service (e.g. Ollama) is consuming GPU VRAM on the same host
- **AND** the GPU has insufficient remaining VRAM for cuBLAS initialisation
- **WHEN** the Immich stack is deployed
- **THEN** `immich-ml` SHALL use the CPU-only image (no `-cuda` tag, no `hwaccel.ml.yml` extends)
- **AND** the `immich` server SHALL continue to use the NVENC transcoding backend unaffected

### REQ-024a: Immich ML model cache volume persistence
The `immich-ml` container SHALL mount the named external volume `immich_model_cache` at `/cache` so that downloaded CLIP and facial-recognition models persist across container restarts and image upgrades, avoiding repeated model downloads.

#### Scenario: ML models survive container recreation
- **GIVEN** `immich_model_cache` is an external Docker volume
- **WHEN** the `immich-ml` container is recreated or upgraded
- **THEN** previously downloaded models SHALL already be present in `/cache`
- **AND** the container SHALL NOT re-download models that are already cached

### REQ-025: Immich ML Service Network Alias
The `immich-ml` container SHALL declare the network alias `immich-machine-learning` on its default network so that the Immich server can resolve the ML service at the URL `http://immich-machine-learning:3003` — matching Immich's built-in default and any system config stored in the database.

#### Scenario: Immich server reaches ML service via default URL
- **GIVEN** the Immich stack is deployed
- **WHEN** the Immich server performs a machine-learning request
- **THEN** it SHALL successfully resolve `immich-machine-learning` to the `immich-ml` container
- **AND** the ML service SHALL respond without a "failed for all URLs" error

### Requirement: Invidious Restore Script SHALL Use Remote-First Latest Backup Flow
The Invidious restore script SHALL discover and restore the latest available Dropbox backup file matching `*.sql.zst.gpg` using selection behavior consistent with Firefly/Firefox Sync scripts.

#### Scenario: Latest encrypted compressed backup is selected
- **GIVEN** multiple backup files exist in the configured Dropbox path
- **WHEN** `restore.sh` resolves the restore source
- **THEN** it SHALL select the latest file using the same latest-selection approach as Firefly/Firefox Sync
- **AND** SHALL reject restore when no `*.sql.zst.gpg` file is available

### Requirement: Invidious Restore Script SHALL Enforce Preflight and `.env` Presence
The Invidious restore script SHALL fail fast if required runtime prerequisites are not present, including mandatory `.env` availability in the service directory.

#### Scenario: `.env` file is missing
- **GIVEN** `mediaServices/invidious/.env` is absent
- **WHEN** the operator runs `restore.sh`
- **THEN** the script SHALL exit before backup lookup or download begins
- **AND** SHALL present a clear error explaining `.env` is required

### Requirement: Invidious Restore Script SHALL Use Passphrase Precedence and Cleanup
The restore script SHALL prefer an environment-provided passphrase and prompt interactively only when no passphrase is supplied; it SHALL clear passphrase state during cleanup.

#### Scenario: Passphrase exists in environment
- **GIVEN** `PASSPHRASE` is already set in the shell environment
- **WHEN** `restore.sh` executes decrypt-and-restore steps
- **THEN** the script SHALL use the environment passphrase without prompting
- **AND** SHALL clear passphrase state during cleanup at script exit

#### Scenario: Passphrase absent in environment
- **GIVEN** `PASSPHRASE` is not set in the shell environment
- **WHEN** `restore.sh` reaches credential collection
- **THEN** the script SHALL prompt interactively for passphrase input
- **AND** SHALL fail if an empty passphrase is provided

### Requirement: Invidious Restore Script SHALL Gate Destructive Operations
The restore script SHALL require explicit operator confirmation before deleting and recreating `invidious_postgresdata` while keeping confirmation behavior aligned with Firefly/Firefox Sync UX.

#### Scenario: Existing volume requires operator confirmation
- **GIVEN** `invidious_postgresdata` already exists
- **WHEN** `restore.sh` prepares to restore into a clean database volume
- **THEN** the script SHALL prompt the operator to confirm recreation
- **AND** SHALL follow Firefly/Firefox Sync-style default confirmation semantics

### Requirement: Invidious Restore Script SHALL Validate PostgreSQL Readiness and Failure Safety
The restore script SHALL wait for PostgreSQL readiness before import and SHALL leave the stack down with explicit messaging when restore validation fails.

#### Scenario: Database readiness check passes
- **GIVEN** the database container is started for restore
- **WHEN** readiness checks complete successfully
- **THEN** the script SHALL proceed with decrypt, decompress, and `psql` import
- **AND** SHALL start the full Invidious stack after successful verification

#### Scenario: Database readiness or verification fails
- **GIVEN** readiness or post-restore verification does not succeed
- **WHEN** `restore.sh` handles the failure
- **THEN** the script SHALL exit non-zero
- **AND** SHALL explicitly state the stack is intentionally left down for manual inspection

### REQ-029: Invidious Proxied External Egress via Gluetun
The `invidious` service SHALL join `security_network` for external HTTP(S) egress and SHALL use the Gluetun proxy at `http://gluetun:8888` through lowercase `http_proxy` and `https_proxy` environment variables. The `invidious-db` and `companion` services SHALL remain exclusively on `media_network`.

#### Scenario: Invidious external requests traverse Gluetun
- **GIVEN** the Invidious stack is deployed with Gluetun reachable on `security_network`
- **WHEN** Invidious makes an external HTTP(S) request
- **THEN** the request SHALL be sent through `http://gluetun:8888`
- **AND** requests to `localhost` and `127.0.0.1` SHALL bypass the proxy through lowercase `no_proxy`

#### Scenario: Invidious internal components retain media-network isolation
- **GIVEN** the Invidious stack is deployed
- **WHEN** Docker network membership is inspected
- **THEN** `invidious` SHALL be attached to both `media_network` and `security_network`
- **AND** `invidious-db` and `companion` SHALL be attached only to `media_network`

### REQ-030: Jellyfin Uses an Independent Compose Stack
The Jellyfin service SHALL be defined in `mediaServices/jellyfin/docker-compose.yml` and SHALL NOT be defined in `mediaServices/docker-compose.yml`. The standalone stack SHALL connect to the external `media_network` and `security_network` and SHALL preserve the shared host media paths used by the media services stack. Jellyfin SHALL route external HTTP(S) egress through Gluetun at `http://gluetun:8888` using lowercase `http_proxy` and `https_proxy` environment variables and SHALL bypass the proxy for `localhost` and `127.0.0.1` using lowercase `no_proxy`.

#### Scenario: Jellyfin is independently deployable
- **GIVEN** the media category and Jellyfin compose files are inspected
- **WHEN** an operator starts the Jellyfin compose file from its service directory
- **THEN** a container named `jellyfin` SHALL start on `media_network` and `security_network`
- **AND** it SHALL mount the configured Movies, TVSeries, and Music host paths

#### Scenario: Jellyfin external requests traverse Gluetun
- **GIVEN** Jellyfin and Gluetun are connected to `security_network`
- **WHEN** Jellyfin makes an external HTTP(S) request
- **THEN** the request SHALL be sent through `http://gluetun:8888`
- **AND** requests to `localhost` and `127.0.0.1` SHALL bypass the proxy

### REQ-031: Jellyfin Configuration Is Persisted Separately
The Jellyfin service SHALL mount the external volume key `filedata` at `/config`; its top-level volume declaration SHALL map to the external Docker volume named `jellyfin_filedata`. The volume SHALL be created before first deployment and SHALL be restorable without copying the legacy XML configuration files into it.

#### Scenario: Jellyfin config survives container replacement
- **GIVEN** the Jellyfin stack is running with `jellyfin_filedata` mounted at `/config`
- **WHEN** the Jellyfin container is recreated
- **THEN** the `/config` state SHALL remain available from `jellyfin_filedata`
- **AND** the media-library bind mounts SHALL remain separate from `/config`

### REQ-032: Jellyfin Configuration Uses the Persistent Volume Without Playlist Mounts
The Jellyfin service SHALL use `jellyfin_filedata` as its only `/config` mount and SHALL NOT mount the tracked M3U playlists into `/config`.

#### Scenario: Jellyfin config volume is the sole config mount
- **GIVEN** the standalone Jellyfin compose stack is running
- **WHEN** its container mounts are inspected
- **THEN** `/config` SHALL be backed by `jellyfin_filedata`
- **AND** the tracked M3U playlists SHALL NOT be mounted into `/config`

### REQ-033: Jellyfin Publishes Its Web Interface on Host Port 8096
The Jellyfin service SHALL publish container port `8096` on host port `8096` and SHALL remain connected to `media_network`.

#### Scenario: Jellyfin web interface is available on the published port
- **GIVEN** the Jellyfin stack is deployed
- **WHEN** a user connects to host port `8096`
- **THEN** Docker SHALL forward the connection to container port `8096`
- **AND** the Jellyfin container SHALL remain reachable on `media_network`

### REQ-034: Radarr and Sonarr Use Gluetun for External HTTP(S) Egress
The `radarr` and `sonarr` services SHALL connect to both `media_network` and `security_network`, use the Gluetun proxy at `http://gluetun:8888` through lowercase `http_proxy` and `https_proxy` environment variables, and bypass the proxy for `localhost` and `127.0.0.1` through lowercase `no_proxy`.

#### Scenario: Radarr and Sonarr external requests traverse Gluetun
- **GIVEN** Radarr and Sonarr are deployed with Gluetun reachable on `security_network`
- **WHEN** either service makes an external HTTP(S) request
- **THEN** the request SHALL be sent through `http://gluetun:8888`
- **AND** requests to `localhost` and `127.0.0.1` SHALL bypass the proxy
- **AND** both services SHALL remain connected to `media_network`

### REQ-035: Radarr and Sonarr Web Interfaces Are Not Published on Host Ports
The Radarr and Sonarr services SHALL NOT publish their web interface ports on the Docker host. Their web interfaces SHALL remain reachable by container name on `media_network` for reverse-proxy access.

#### Scenario: Radarr and Sonarr web interfaces remain internal
- **GIVEN** the Radarr and Sonarr stacks are deployed
- **WHEN** Docker port bindings are inspected
- **THEN** host ports `7878` and `8989` SHALL NOT be published
- **AND** each service SHALL remain reachable by its container name and native port on `media_network`

### REQ-036: Jackett and Transmission Web Interfaces Are Not Published on Host Ports
The Jackett and Transmission services SHALL NOT publish their web interface ports on the Docker host. Their web interfaces SHALL remain reachable by container name on `media_network` for reverse-proxy access.

#### Scenario: Jackett and Transmission web interfaces remain internal
- **GIVEN** the Jackett and Transmission stacks are deployed
- **WHEN** Docker port bindings are inspected
- **THEN** their web interface ports SHALL NOT be published on the host
- **AND** each service SHALL remain reachable by container name on `media_network`

### REQ-037: Transmission Proxy Scope Is Documented Accurately
The Transmission service documentation SHALL distinguish proxy-aware HTTP(S) requests from BitTorrent peer traffic. It SHALL NOT claim that BitTorrent peer traffic is routed through Gluetun unless the service uses a network tunnel or equivalent enforcement.

#### Scenario: Transmission network behavior is described without overstating VPN coverage
- **GIVEN** the Transmission Compose configuration sets HTTP(S) proxy environment variables
- **WHEN** its operator documentation is reviewed
- **THEN** HTTP(S) proxy behavior SHALL be described separately from BitTorrent peer traffic
- **AND** the documentation SHALL state that the current proxy variables alone do not tunnel peer traffic

