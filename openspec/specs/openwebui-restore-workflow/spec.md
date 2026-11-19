## Requirements

### REQ-001: OpenWebUI Restore Script Canonical Stateful Flow
The system SHALL provide an executable `aiServices/openwebui/restore.sh` script that performs preflight checks, selects a backup artifact, prompts for destructive actions, restores into `openwebui_filedata`, and restarts the service.

#### Scenario: Restore script executes end-to-end
- **GIVEN** required tools are available and at least one OpenWebUI backup artifact exists
- **WHEN** the operator runs `aiServices/openwebui/restore.sh` and confirms destructive prompts
- **THEN** the script SHALL restore data into `openwebui_filedata`
- **AND** the OpenWebUI service SHALL be started after restore success

#### Scenario: Preflight failure blocks destructive operations
- **GIVEN** a required dependency (for example `docker`, `rclone`, `gpg`, or `zstd`) is unavailable
- **WHEN** `aiServices/openwebui/restore.sh` runs
- **THEN** the script SHALL exit non-zero before stopping services or wiping volumes
- **AND** the script SHALL emit actionable error output

### REQ-002: OpenWebUI Restore Script Timing and SLO Reporting
The `aiServices/openwebui/restore.sh` script SHALL log start and end timestamps for each restore phase and SHALL report whether core service readiness was achieved within 10 minutes.

#### Scenario: Restore output includes per-phase timing
- **GIVEN** an OpenWebUI restore run is executed
- **WHEN** restore output is reviewed
- **THEN** each major phase SHALL include start and end timestamps
- **AND** a total elapsed duration SHALL be printed

#### Scenario: Restore output includes SLO pass/fail
- **GIVEN** a restore run completes with core verification attempted
- **WHEN** elapsed time is compared to 10 minutes
- **THEN** the script SHALL print an explicit SLO pass/fail status
- **AND** the status SHALL be based on core readiness checks, not RAG or vector readiness

### REQ-003: Core Restore Readiness Independent of RAG Indexing
Core OpenWebUI restore readiness SHALL mean healthy container status with recoverable account, chat, and settings state and SHALL NOT require immediate RAG or vector index readiness.

#### Scenario: Core-ready with deferred retrieval indexing
- **GIVEN** `vector_db` content was excluded from backup
- **WHEN** restore completes and OpenWebUI starts successfully
- **THEN** the restore SHALL be considered core-ready if account, chat, and settings access is functional
- **AND** retrieval index rebuild delay SHALL be treated as expected post-restore behavior