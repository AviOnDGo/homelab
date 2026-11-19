## Purpose
Define Gluetun-specific VPN behavior, container hardening requirements, and recovery references.

## Requirements

### REQ-001: Gluetun uses ProtonVPN WireGuard free tier
Gluetun SHALL be configured with `VPN_SERVICE_PROVIDER=protonvpn`, `VPN_TYPE=wireguard`, and `FREE_ONLY=on`.

#### Scenario: Provider and protocol configuration are enforced
- **GIVEN** `securityServices/gluetun/docker-compose.yml` is inspected
- **WHEN** environment values are reviewed
- **THEN** provider, protocol, and free-tier keys SHALL match required values
- **AND** paid-tier selection SHALL NOT be enabled by default

### REQ-002: Gluetun container has required network capabilities
Gluetun SHALL declare `cap_add: [NET_ADMIN]` and `/dev/net/tun` device mapping, and SHALL NOT declare persistent volumes. The default configuration SHALL NOT set the `net.ipv6.conf.all.disable_ipv6` sysctl because the current image does not accept that override.

#### Scenario: Required runtime settings are present
- **GIVEN** `securityServices/gluetun/docker-compose.yml` is inspected
- **WHEN** capability, devices, sysctls, and volumes are reviewed
- **THEN** required Linux networking settings SHALL be present
- **AND** the IPv6 sysctl override SHALL remain disabled
- **AND** no named persistent volume SHALL be declared

### REQ-003: Gluetun routing endpoints stay internal to security network
Traffic routed through Gluetun SHALL use either `network_mode: "service:gluetun"` or the internal `gluetun:8888` proxy endpoint, and port 8888 SHALL NOT be exposed on the host. The HTTP proxy SHALL be explicitly enabled via `HTTPPROXY=on`.

#### Scenario: HTTP proxy remains internal
- **GIVEN** `securityServices/gluetun/docker-compose.yml` is inspected
- **WHEN** port mappings are reviewed
- **THEN** there SHALL be no active host mapping for 8888
- **AND** proxy consumers in `security_network` SHALL access `gluetun:8888`

#### Scenario: Proxy consumer joins security_network for egress only
- **GIVEN** a service (e.g. `openwebui`) sets lowercase `http_proxy` and `https_proxy` to `http://gluetun:8888` for external egress
- **WHEN** that service joins `security_network` to reach Gluetun
- **THEN** the service SHALL continue to use its own category network(s) for all other traffic
- **AND** its membership in `security_network` SHALL be limited to reaching the Gluetun proxy endpoint

### REQ-004: Gluetun restore procedure is redeploy-only and externally defined
Gluetun SHALL provide `restore.sh`, and its canonical stateless restore behavior SHALL be defined in `openspec/specs/security-services-restore-scripts/spec.md`.

#### Scenario: Restore reference is available
- **GIVEN** an operator needs to recover Gluetun
- **WHEN** they consult security service specifications
- **THEN** `securityServices/gluetun/restore.sh` SHALL exist
- **AND** the authoritative restore flow SHALL be documented in the security restore scripts spec
