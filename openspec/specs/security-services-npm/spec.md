## Purpose
Define Nginx Proxy Manager behavior, network ownership, persistence model, and recovery references for the security stack.

## Requirements

### REQ-001: NPM provides central ingress and TLS termination
NPM SHALL proxy inbound HTTP/HTTPS requests to internal homelab services and SHALL terminate HTTPS using valid certificates.

#### Scenario: Request is routed through NPM
- **GIVEN** NPM is running and proxy hosts are configured
- **WHEN** a request arrives on port 80 or 443
- **THEN** NPM SHALL route the request to the intended internal service
- **AND** HTTPS termination SHALL occur at NPM

### REQ-002: NPM is the Docker network creator across categories
NPM SHALL declare all required category networks in `securityServices/npm/docker-compose.yml` without `external: true`, and other services SHALL consume those networks as external.

#### Scenario: NPM owns category network definitions
- **GIVEN** the NPM compose file is inspected
- **WHEN** the top-level `networks` block is reviewed
- **THEN** proxied category networks SHALL be declared by NPM
- **AND** those entries SHALL not be marked external

### REQ-003: NPM volume and admin port mappings are standardized
NPM SHALL use external named volume `npm_filedata` mounted at both `/data` and `/etc/letsencrypt`, and SHALL expose host ports 80, 443, and 9003.

#### Scenario: Volume and port contract is met
- **GIVEN** `securityServices/npm/docker-compose.yml` is inspected
- **WHEN** volumes and ports are reviewed
- **THEN** both mount points SHALL reference `npm_filedata`
- **AND** host mappings for 80, 443, and 9003 SHALL be present

### REQ-004: NPM restore procedure is externally defined
NPM SHALL provide `restore.sh`, and the canonical restore workflow details SHALL be defined in `openspec/specs/security-services-restore-scripts/spec.md`.

#### Scenario: Restore reference is available
- **GIVEN** an operator needs to recover NPM state
- **WHEN** they consult security service specifications
- **THEN** `securityServices/npm/restore.sh` SHALL exist
- **AND** the authoritative restore flow SHALL be documented in the security restore scripts spec
