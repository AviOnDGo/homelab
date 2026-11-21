## Requirements

### REQ-001: RTMP deployment is network-isolated
The RTMP service SHALL join the external `stream_network` through an explicit
Compose networks declaration and SHALL NOT create that network implicitly.

#### Scenario: RTMP Compose network is valid
- **GIVEN** `streamServices/rtmp/docker-compose.yml` is inspected
- **WHEN** the network configuration is reviewed
- **THEN** the RTMP service SHALL join `stream_network`
- **AND** the top-level network declaration SHALL specify `external: true`

### REQ-002: RTMP image is immutable and resource-limited
The RTMP image SHALL be pinned to an immutable digest and the service SHALL
declare CPU and memory limits.

#### Scenario: Runtime image and limits are valid
- **GIVEN** the RTMP Compose service is inspected
- **WHEN** image and resource settings are reviewed
- **THEN** the image reference SHALL contain a `sha256` digest
- **AND** CPU and memory limits SHALL be present

### REQ-003: RTMP ingest access is restricted
The RTMP ingest port SHALL NOT be published to the host. Publishers SHALL reach
the service only through the external `stream_network` unless an authenticated
host-ingress design is added.

#### Scenario: Host port exposure is reviewed
- **GIVEN** the RTMP Compose port mapping is inspected
- **WHEN** host port exposure is reviewed
- **THEN** the `ports:` configuration SHALL remain commented
- **AND** an internal publisher SHALL reach `rtmp:1935` through `stream_network`
- **AND** the opt-in example SHALL bind port 1935 to `127.0.0.1`

### REQ-004: RTMP credentials remain local
The repository SHALL provide a `nginx.conf.example` without live stream keys,
and operator-specific `nginx.conf` content SHALL remain ignored by Git.

#### Scenario: Configuration secrecy is reviewed
- **GIVEN** the RTMP service directory is inspected
- **WHEN** tracked and ignored configuration files are reviewed
- **THEN** `nginx.conf.example` SHALL contain placeholders only
- **AND** `.gitignore` SHALL exclude `nginx.conf`

### REQ-005: RTMP recovery is script-first and stateless
The RTMP service SHALL provide `restore.sh`, `RESTORE_GUIDE.md`, and
`SERVICE_DOCUMENTATION.md`, and recovery SHALL redeploy the service without
restoring persistent recording data.

#### Scenario: Recovery artifacts are available
- **GIVEN** an operator needs to recover RTMP
- **WHEN** the service directory is inspected
- **THEN** all required operational files SHALL exist
- **AND** `restore.sh` SHALL verify configuration, restart RTMP, and check health
- **AND** the restore guide SHALL document stateless recovery
