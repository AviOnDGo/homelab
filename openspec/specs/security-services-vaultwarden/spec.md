## Purpose
Define Vaultwarden-specific security service behavior, deployment constraints, and recovery references.

## Requirements

### REQ-001: Vaultwarden deployment and persistence
Vaultwarden SHALL be deployed from `securityServices/vaultwarden/` and SHALL persist all vault data in the external named volume `vaultwarden_filedata`.

#### Scenario: Vault data persists across restarts
- **GIVEN** Vaultwarden is running
- **WHEN** the container is stopped and started again
- **THEN** vault data SHALL remain available from `vaultwarden_filedata`
- **AND** no user vault entries SHALL be lost due to container restart

### REQ-003: Vaultwarden host exposure is proxy-only
Vaultwarden SHALL NOT expose container port 80 directly on the host and SHALL be externally accessed only through NPM reverse proxying.

#### Scenario: No direct host mapping
- **GIVEN** `securityServices/vaultwarden/docker-compose.yml` is inspected
- **WHEN** the service ports are reviewed
- **THEN** no active host mapping for container port 80 SHALL exist
- **AND** external traffic SHALL route through NPM

### REQ-004: Vaultwarden requires manual update approval
Vaultwarden SHALL opt out of Watchtower automatic updates via `com.centurylinklabs.watchtower.enable=false`.

#### Scenario: Watchtower skips Vaultwarden
- **GIVEN** Watchtower performs an update cycle
- **WHEN** it evaluates the `vaultwarden` container
- **THEN** Vaultwarden SHALL be excluded by the opt-out label
- **AND** Vaultwarden image updates SHALL require manual operator action

### REQ-005: Vaultwarden restore procedure is externally defined
Vaultwarden SHALL provide `restore.sh`, and the canonical restore workflow details SHALL be defined in `openspec/specs/security-services-restore-scripts/spec.md`.

#### Scenario: Restore reference is available
- **GIVEN** an operator needs to recover Vaultwarden data
- **WHEN** they consult the service and restore specifications
- **THEN** `securityServices/vaultwarden/restore.sh` SHALL exist
- **AND** the authoritative restore flow SHALL be documented in the security restore scripts spec

### REQ-006: Vaultwarden admin panel is disabled
The Vaultwarden deployment SHALL leave `ADMIN_TOKEN` unset and SHALL keep the admin panel disabled.

#### Scenario: Admin panel remains disabled
- **GIVEN** the Vaultwarden service is deployed with its default Compose configuration
- **WHEN** a user requests the `/admin` route
- **THEN** the admin panel SHALL be unavailable
- **AND** the service SHALL NOT receive an `ADMIN_TOKEN` from Compose
