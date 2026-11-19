## Purpose
Define cross-service governance rules for the security services category without embedding service-specific implementation details.

## Requirements

### REQ-001: Security category network isolation is mandatory
All security services SHALL communicate within `security_network`, and services outside `security_network` SHALL only reach security services through approved reverse-proxy paths.

#### Scenario: East-west traffic stays inside the category network
- **GIVEN** two security services need to communicate
- **WHEN** service-to-service traffic is exchanged
- **THEN** communication SHALL occur inside `security_network`
- **AND** direct cross-category ingress to security services SHALL NOT occur unless explicitly proxied

### REQ-002: Security network membership declaration is standardized
Security services that do not create networks SHALL consume `security_network` as an external network, and network creator responsibilities SHALL be explicitly documented in the appropriate service child specification.

#### Scenario: Non-network-creator service declaration
- **GIVEN** a non-network-creator security service compose file is inspected
- **WHEN** reviewing network configuration
- **THEN** `security_network` SHALL be referenced as external
- **AND** no implicit network creation behavior SHALL be relied upon

### REQ-003: Security documentation and restore entrypoints are required
Each service directory under `securityServices/` SHALL include `SERVICE_DOCUMENTATION.md` and `RESTORE_GUIDE.md`, and SHALL provide `restore.sh` when a restore workflow is defined for the service.

#### Scenario: Service operational documentation is present
- **GIVEN** a security service directory is inspected
- **WHEN** tracked documentation files are reviewed
- **THEN** required service and restore documentation files SHALL exist
- **AND** restore entrypoints SHALL be present where restore workflows apply

### REQ-004: Security compose files forbid plaintext credentials
No `docker-compose.yml` under `securityServices/` SHALL include plaintext secret literals for passwords, tokens, API keys, or equivalent sensitive values.

#### Scenario: Compose credential scan
- **GIVEN** a security service compose file is inspected
- **WHEN** environment and configuration blocks are reviewed
- **THEN** sensitive values SHALL be supplied via variable substitution, env files, or Docker secrets
- **AND** plaintext credential literals SHALL NOT be present

### REQ-005: Critical security services require manual update control
Stateful or security-critical services SHALL require explicit manual update approval and SHALL opt out of unattended image updates where automatic updates could cause data loss or service disruption.

#### Scenario: Critical service update policy is enforced
- **GIVEN** update automation policy is reviewed for security-critical services
- **WHEN** service update controls are inspected
- **THEN** critical services SHALL be excluded from unattended update paths
- **AND** update procedures SHALL require operator approval
