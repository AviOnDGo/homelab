## Purpose
Define Watchtower-specific update automation behavior, notification behavior, and recovery references.

## Requirements

### REQ-001: Watchtower schedule and Docker daemon access are required
Watchtower SHALL mount `/var/run/docker.sock` and SHALL consume an explicit `WATCHTOWER_SCHEDULE` value via `.env`.

#### Scenario: Required runtime inputs are present
- **GIVEN** `securityServices/watchtower/docker-compose.yml` and runtime inputs are inspected
- **WHEN** volume mounts and schedule configuration are reviewed
- **THEN** Docker socket access SHALL be configured
- **AND** a valid schedule SHALL be defined before deployment

### REQ-002: Watchtower updates unlabeled containers by default
Watchtower SHALL evaluate running containers on schedule and SHALL update containers that are not explicitly excluded by label.

#### Scenario: Unlabeled container is updated
- **GIVEN** a container without `com.centurylinklabs.watchtower.enable=false`
- **WHEN** Watchtower runs its update cycle and a newer image exists
- **THEN** Watchtower SHALL pull the image and recreate the container
- **AND** existing runtime configuration SHALL be preserved

### REQ-003: Watchtower exclusion label is honored
Containers labeled with `com.centurylinklabs.watchtower.enable=false` SHALL be excluded from automatic updates.

#### Scenario: Excluded container is skipped
- **GIVEN** a container has the exclusion label
- **WHEN** Watchtower performs an update cycle
- **THEN** the container SHALL be skipped
- **AND** no automatic restart SHALL be triggered by Watchtower

### REQ-004: Watchtower sends Discord notifications with host identity
Watchtower SHALL send Discord notifications for update events, and `WATCHTOWER_NOTIFICATION_TEMPLATE` SHALL include `{{.Host}}`.

#### Scenario: Notification includes hostname
- **GIVEN** Watchtower notifications are enabled
- **WHEN** an update succeeds or fails
- **THEN** a Discord notification SHALL be emitted
- **AND** the message template SHALL include the Docker host identity

### REQ-005: Watchtower restore procedure is redeploy-only and externally defined
Watchtower SHALL provide `restore.sh`, and its canonical stateless restore behavior SHALL be defined in `openspec/specs/security-services-restore-scripts/spec.md`.

#### Scenario: Restore reference is available
- **GIVEN** an operator needs to recover Watchtower
- **WHEN** they consult security service specifications
- **THEN** `securityServices/watchtower/restore.sh` SHALL exist
- **AND** the authoritative restore flow SHALL be documented in the security restore scripts spec
