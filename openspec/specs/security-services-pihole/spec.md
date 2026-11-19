## Purpose
Define Pi-hole-specific DNS filtering behavior, exposure constraints, and recovery references.

## Requirements

### REQ-001: Pi-hole provides DNS filtering for clients
Pi-hole SHALL provide DNS-based ad and tracker blocking for clients configured to use it as their DNS resolver.

#### Scenario: DNS query is filtered
- **GIVEN** Pi-hole is running and a client uses Pi-hole for DNS
- **WHEN** the client queries a known ad or tracking domain
- **THEN** Pi-hole SHALL block the query response according to configuration
- **AND** the query outcome SHALL be recorded in Pi-hole statistics

### REQ-002: Pi-hole admin password is not hardcoded
Pi-hole admin credentials SHALL be sourced from `.env` using variable substitution and SHALL NOT be stored as plaintext literals in compose files.

#### Scenario: Password source is variable-backed
- **GIVEN** `securityServices/pihole/docker-compose.yml` is inspected
- **WHEN** `FTLCONF_webserver_api_password` is reviewed
- **THEN** the value SHALL be a variable reference
- **AND** plaintext password values SHALL exist only in operator-managed secret inputs

### REQ-003: Pi-hole DNS ports are exposed and web UI is not directly exposed
Pi-hole SHALL expose `53:53/tcp` and `53:53/udp` for DNS resolution, and Pi-hole web administration SHALL NOT be directly exposed on the host.

#### Scenario: DNS port bindings are present
- **GIVEN** `securityServices/pihole/docker-compose.yml` is inspected
- **WHEN** the ports list is reviewed
- **THEN** both `53:53/tcp` and `53:53/udp` SHALL be mapped
- **AND** no active direct host mapping for Pi-hole web administration SHALL be present

### REQ-004: Pi-hole restore procedure is externally defined
Pi-hole SHALL provide `restore.sh`, and the canonical restore workflow details SHALL be defined in `openspec/specs/security-services-restore-scripts/spec.md`.

#### Scenario: Restore reference is available
- **GIVEN** an operator needs to recover Pi-hole state
- **WHEN** they consult security service specifications
- **THEN** `securityServices/pihole/restore.sh` SHALL exist
- **AND** the authoritative restore flow SHALL be documented in the security restore scripts spec
