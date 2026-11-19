## Purpose
Define canonical restore workflows for all security service restore scripts, including stateful and stateless recovery behavior.

## Requirements

### REQ-001: Restore scripts SHALL exist for all security service recovery targets
The system SHALL provide executable `restore.sh` scripts in `securityServices/firefoxsync/`, `securityServices/gluetun/`, `securityServices/npm/`, `securityServices/pihole/`, `securityServices/vaultwarden/`, and `securityServices/watchtower/`.

#### Scenario: Restore scripts are present
- **GIVEN** the repository working tree is available
- **WHEN** the six target service directories are inspected
- **THEN** each directory SHALL contain an executable `restore.sh`
- **AND** each script SHALL be invokable directly from its service directory

### REQ-002: Stateful restore scripts use latest backup with safety prompts
For stateful services (`firefoxsync`, `npm`, `pihole`, `vaultwarden`), restore scripts SHALL discover the latest backup artifact, collect passphrase input safely, and require explicit confirmation before destructive operations.

#### Scenario: Latest backup and confirmations are enforced
- **GIVEN** multiple timestamped backups exist for a stateful service
- **WHEN** the relevant restore script is run
- **THEN** the most recent backup SHALL be selected
- **AND** passphrase entry and destructive steps SHALL require explicit operator confirmation

### REQ-003: Firefox Sync restore uses PostgreSQL-first workflow
`securityServices/firefoxsync/restore.sh` SHALL restore data using a PostgreSQL workflow: stop stack, prepare database volume as needed, start `firefoxsync-db`, wait for readiness, restore SQL via `psql`, then start the full stack.

#### Scenario: Firefox Sync PostgreSQL restore succeeds
- **GIVEN** a valid Firefox Sync backup exists
- **WHEN** the Firefox Sync restore script runs successfully
- **THEN** data SHALL be restored into the target database on `firefoxsync-db`
- **AND** full stack startup SHALL occur only after database restore success

### REQ-004: Pi-hole and Vaultwarden restore scripts use filedata flow
`securityServices/pihole/restore.sh` and `securityServices/vaultwarden/restore.sh` SHALL follow filedata restore flow with dependency preflight checks, encrypted archive restore into named volume, and service-specific verification.

#### Scenario: Filedata restore flow is enforced
- **GIVEN** either Pi-hole or Vaultwarden restore script runs
- **WHEN** restore steps execute
- **THEN** tool preflight checks SHALL run before destructive actions
- **AND** restored data SHALL be verified before success is reported

### REQ-005: NPM restore script follows canonical stateful filedata workflow
`securityServices/npm/restore.sh` SHALL perform preflight validation, support masked passphrase prompt fallback, select the latest Dropbox backup by timestamped filename sort, support `DROPBOX_PATH` override, prompt before service shutdown and volume wipe, decrypt and restore without writing decrypted archives to disk, verify startup via `database.sqlite`, and clean temporary state on exit.

#### Scenario: NPM restore executes end-to-end safely
- **GIVEN** required tools are available and a valid encrypted backup exists
- **WHEN** `securityServices/npm/restore.sh` is run with operator confirmations
- **THEN** `npm_filedata` SHALL be restored from the latest backup artifact
- **AND** the NPM service SHALL start and verify `database.sqlite` presence

#### Scenario: NPM restore fails safely during preflight or selection
- **GIVEN** required tooling or backup availability checks fail
- **WHEN** NPM restore preflight executes
- **THEN** the script SHALL exit non-zero before destructive restore actions
- **AND** a clear actionable error message SHALL be emitted

### REQ-006: Stateless restore scripts are redeploy-only
`securityServices/gluetun/restore.sh` and `securityServices/watchtower/restore.sh` SHALL perform redeploy plus verification only and SHALL NOT perform backup download or payload decryption.

#### Scenario: Stateless restore avoids backup payload operations
- **GIVEN** Gluetun or Watchtower restore is initiated
- **WHEN** the script executes
- **THEN** recovery SHALL use redeploy and health verification steps
- **AND** no archive download/decryption or volume extraction SHALL occur

### REQ-007: Stateful restore failure leaves services down for safety
For all stateful security service restores, if a restore fails after service shutdown, the script SHALL exit non-zero and SHALL NOT auto-start the stack.

#### Scenario: Failure path preserves safe stopped state
- **GIVEN** a stateful restore operation fails after shutdown
- **WHEN** failure handling runs
- **THEN** services SHALL remain stopped
- **AND** the script SHALL emit actionable diagnostics with a non-zero exit status
