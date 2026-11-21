## Purpose
Define the sync-crypt backup execution mode for filedata services, supporting provider-neutral
crypt remotes, incremental sync with optional deleted-file retention, and namespace organization.

## Requirements

### REQ-001: Filedata backup supports per-service backup modes
The `filedata-backup` service SHALL support per-service execution modes with at least `archive` and `sync-crypt` values, selected by environment-driven configuration.

#### Scenario: Service runs in archive mode
- **GIVEN** a registered filedata service is configured with mode `archive`
- **WHEN** its cron entry executes in `filedata-backup`
- **THEN** the backup flow SHALL create a compressed archive artifact
- **AND** existing archive-mode behavior SHALL remain unchanged
- **AND** Dropbox archive uploads SHALL NOT require `rclone crypt`

#### Scenario: Service runs in sync-crypt mode
- **GIVEN** a registered filedata service is configured with mode `sync-crypt`
- **WHEN** its cron entry executes in `filedata-backup`
- **THEN** the backup flow SHALL perform incremental `rclone sync` behavior
- **AND** archive artifact creation SHALL NOT be required for that run

### REQ-002: Sync-crypt mode writes latest-good-state to current namespace
In `sync-crypt` mode, filedata backup SHALL write the active synchronized dataset into a `current/` namespace on the configured remote path.

#### Scenario: Current namespace is populated
- **GIVEN** a sync-crypt backup run starts for a registered service
- **WHEN** rclone synchronization completes successfully
- **THEN** remote objects SHALL exist under `<remote-path>/current/`
- **AND** the tree under `current/` SHALL represent latest-good-state for that service

### REQ-003: Sync-crypt mode preserves replaced/deleted files in dated retention namespace
In `sync-crypt` mode, replaced or deleted source files SHALL be moved to a dated retention namespace before removal from `current/`, using `deleted-archive/YYYY-MM-DD/` under the same service remote path.

#### Scenario: Deleted source file is retained remotely
- **GIVEN** a file exists in prior remote `current/` state and is removed from source
- **WHEN** the next sync-crypt run executes
- **THEN** that file SHALL be moved under `deleted-archive/YYYY-MM-DD/`
- **AND** the file SHALL no longer exist under `current/`

### REQ-004: Sync-crypt mode enforces retention pruning for deleted-archive
Sync-crypt mode SHALL prune dated deleted-archive content older than the configured retention threshold for the service.

#### Scenario: Old deleted-archive data is pruned
- **GIVEN** deleted-archive subpaths older than configured retention exist on remote
- **WHEN** sync-crypt retention cleanup runs
- **THEN** paths older than the threshold SHALL be removed
- **AND** newer deleted-archive paths SHALL be preserved

### REQ-005: Rclone configuration is generated once at startup
The filedata backup container SHALL generate one rclone configuration before cron starts, containing
each configured plain and crypt remote whose credentials are available. The configuration SHALL be
owner-readable only and cron jobs SHALL NOT rewrite it.

#### Scenario: Archive mode validates the shared Dropbox remote
- **GIVEN** an archive-mode service has a valid Dropbox path and the container has started
- **WHEN** its backup job reaches the upload phase
- **THEN** the job SHALL validate the startup-generated `dropbox:` remote
- **AND** it SHALL upload the encrypted archive without invoking per-run configuration

#### Scenario: Google Drive crypt remote is selected
- **GIVEN** a service has `sync-crypt` mode and a configured `gdrive-crypt:` destination
- **WHEN** its scheduled backup runs
- **THEN** the service SHALL synchronize through that configured remote
- **AND** the backup script SHALL NOT hardcode or select another cloud provider

### REQ-006: Zero retention performs a pure mirror
When a service's retention is `0`, sync-crypt SHALL synchronize directly into `current/` without
`--backup-dir` and SHALL NOT create or prune a `deleted-archive` namespace.

#### Scenario: Zero-retention deletion is propagated
- **GIVEN** a service is configured with retention `0` and a file is removed from its source
- **WHEN** the next sync-crypt run completes
- **THEN** the file SHALL be absent from `current/`
- **AND** no deleted copy SHALL be retained by that run

### REQ-007: Volume exclusions apply to both modes
The backup script SHALL apply volume-specific exclusion rules to archive and sync-crypt runs.

#### Scenario: Paperless derived files are excluded
- **GIVEN** a Paperless archive or sync-crypt backup runs
- **WHEN** the source tree is processed
- **THEN** `documents/thumbnails` and `media.lock` SHALL NOT be copied
