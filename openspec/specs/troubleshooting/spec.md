## Requirements

### REQ-001: Container and Docker daemon troubleshooting guide
The homelab SHALL maintain a troubleshooting guide covering Docker daemon and container diagnostics. The guide SHALL document resolution steps for all common container failure modes.

#### Scenario: Container restart loop is documented
- **GIVEN** an operator encounters a container in a restart loop
- **WHEN** they consult the troubleshooting guide
- **THEN** the guide SHALL provide the diagnostic sequence: `docker logs <container> --tail 50`, `docker inspect <container>`, and exit code interpretation
- **AND** it SHALL provide resolution steps before modifying the restart policy

#### Scenario: Port conflict resolution is documented
- **GIVEN** a container fails to start with "address already in use"
- **WHEN** the operator consults the guide
- **THEN** it SHALL document `lsof -i :<port>` to identify the conflicting process
- **AND** SHALL provide options to stop the conflicting process or remap the container port

#### Scenario: Resource exhaustion diagnostics are documented
- **GIVEN** services degrade or fail due to CPU, memory, or disk exhaustion
- **WHEN** the operator consults the guide
- **THEN** it SHALL provide commands to inspect resource usage per container and per host

### REQ-002: Network troubleshooting procedure
The guide SHALL document diagnostic steps for all common network failures: inter-container DNS, cross-network access, NPM SSL/Let's Encrypt failures.

#### Scenario: Inter-container DNS failure is documented
- **GIVEN** Service A cannot reach Service B by container name
- **WHEN** the operator consults the guide
- **THEN** it SHALL document that container names (not IPs) are the correct DNS identifiers within Docker networks
- **AND** it SHALL provide `docker network inspect` commands to verify network membership

#### Scenario: NPM certificate failure is documented
- **GIVEN** NPM reports a Let's Encrypt certificate issuance failure
- **WHEN** the operator consults the guide
- **THEN** it SHALL document: verify port 80/443 are externally reachable, check DNS propagation, and review NPM ACME challenge logs

### REQ-003: Backup and restore troubleshooting procedure
The guide SHALL document resolution for all backup and restore failure modes including GPG errors, rclone authentication failures, disk space exhaustion, and cron job failures.

#### Scenario: GPG passphrase failure is documented
- **GIVEN** a backup script reports a GPG passphrase error
- **WHEN** the operator consults the guide
- **THEN** it SHALL provide steps to verify the `gpg-secrets` Docker volume is mounted
- **AND** SHALL include a manual GPG test command to confirm the passphrase works

#### Scenario: Rclone authentication failure is documented
- **GIVEN** rclone reports a Dropbox or Google Drive authentication error
- **WHEN** the operator consults the guide
- **THEN** it SHALL provide `rclone config reconnect <remote>:` as the resolution command

#### Scenario: Cron job not running is documented
- **GIVEN** a scheduled backup does not run at its expected time
- **WHEN** the operator consults the guide
- **THEN** it SHALL provide steps to verify the crond process, check container timezone, and trigger the backup manually

### REQ-004: Database troubleshooting procedure
The guide SHALL document PostgreSQL-specific resolution steps for version incompatibility on startup, connection pool exhaustion, and performance degradation.

#### Scenario: PostgreSQL startup failure after image update is documented
- **GIVEN** PostgreSQL fails to start after a version upgrade
- **WHEN** the operator consults the guide
- **THEN** it SHALL document how to identify a major version mismatch in logs
- **AND** SHALL reference the data migration procedure

#### Scenario: Connection pool exhaustion resolution is documented
- **GIVEN** applications report "too many connections" to PostgreSQL
- **WHEN** the operator consults the guide
- **THEN** it SHALL provide `SELECT * FROM pg_stat_activity` and `pg_terminate_backend` as diagnostic and remediation commands

### REQ-005: Service-specific troubleshooting coverage
The guide SHALL document service-specific resolution for all active homelab services including: Jellyfin GPU transcoding, Sonarr/Radarr/Jackett indexer issues, Transmission VPN routing, Ollama OOM errors, and Gluetun VPN connection failures.

#### Scenario: Transmission stuck downloads are diagnosed
- **GIVEN** Transmission shows downloads with no speed
- **WHEN** the operator consults the guide
- **THEN** it SHALL direct them to verify Gluetun VPN connectivity first (`docker logs gluetun | grep "VPN connected"`)

#### Scenario: Ollama OOM resolution is documented
- **GIVEN** Ollama reports an out-of-memory error loading a model
- **WHEN** the operator consults the guide
- **THEN** it SHALL recommend selecting a smaller model variant or reducing `num_gpu_layers`
