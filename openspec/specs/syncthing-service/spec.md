# syncthing-service Specification

## Purpose
Define Syncthing service deployment, persistence, backup, and restore expectations for the container-services stack.
## Requirements
### REQ-001: Syncthing Service Deployment
The system SHALL provide a Syncthing service at `containerServices/syncthing/` for peer-to-peer file synchronization.

#### Scenario: Service deploys in container network
- **GIVEN** `containerServices/syncthing/docker-compose.yml` is deployed
- **WHEN** the Syncthing service starts
- **THEN** the Syncthing container SHALL join `container_network`
- **AND** the service SHALL use `restart: unless-stopped`

### REQ-002: Syncthing Uses Named-Volume Persistence For Config And Data
Syncthing SHALL persist identity/config state and synchronized data using Docker named volumes.

#### Scenario: Named volumes are declared and mounted
- **GIVEN** the Syncthing compose file is inspected
- **WHEN** the service volume mounts are reviewed
- **THEN** `syncthing_filedata` SHALL be mounted into Syncthing's config path
- **AND** `syncthing_data` SHALL be mounted into Syncthing's data path

### REQ-003: Syncthing Restore Sequence Restores Config Only
The Syncthing restore procedure SHALL restore the `syncthing_filedata` configuration volume from backup and SHALL NOT restore the `syncthing_data` volume from the Syncthing config backup artifact.

#### Scenario: Restore run follows safe order
- **GIVEN** an operator executes the Syncthing restore guide or `containerServices/syncthing/restore.sh`
- **WHEN** a Syncthing restore is performed
- **THEN** the procedure SHALL stop Syncthing and isolate peers before restoring configuration
- **AND** restore only the `syncthing_filedata` volume from the encrypted Syncthing backup artifact
- **AND** ensure `syncthing_data` exists without clearing or restoring it from backup
- **AND** set `syncthing_data` ownership to `1000:1000`
- **AND** reconnect peers only after local post-restore verification is complete

### REQ-004: Syncthing Provides A Script-First Restore Entrypoint
The Syncthing service SHALL provide an executable `restore.sh` script as the primary restore entrypoint.

#### Scenario: Script-first restore is available
- **GIVEN** the Syncthing service directory is inspected
- **WHEN** restore entrypoints are reviewed
- **THEN** `restore.sh` SHALL exist and be executable
- **AND** `RESTORE_GUIDE.md` SHALL reference `./restore.sh` as the primary recovery workflow

### REQ-005: Monthly Restore Drills Are Operationally Required
Operators SHALL perform and document a monthly Syncthing restore drill.

#### Scenario: Monthly restore validation is recorded
- **GIVEN** Syncthing restore operations are part of routine homelab maintenance
- **WHEN** a calendar month completes
- **THEN** at least one Syncthing restore drill result SHALL be recorded
- **AND** the record SHALL include verification outcome and any follow-up actions

