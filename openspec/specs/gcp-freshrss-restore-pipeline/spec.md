## Purpose

Define normative requirements for a workflow-driven, audited FreshRSS restore
pipeline on the GCP VM, including ordering, destructive guardrails, and restore
validation behavior.

## Requirements

### REQ-001: Manual pipeline SHALL orchestrate end-to-end FreshRSS restore on GCP
The system SHALL provide a manually triggered GitHub Actions workflow that performs a complete FreshRSS recovery run on the target GCP VM.

#### Scenario: Successful restore run follows required order
- **GIVEN** the operator has approved and manually dispatched the FreshRSS restore workflow
- **WHEN** the workflow executes the remote restore sequence
- **THEN** it SHALL resolve and download the selected FreshRSS backup before stopping containers or removing `freshrss_filedata`
- **AND** it SHALL stop `filedata-backup` if that container is running and stop the FreshRSS service if it is running
- **AND** it SHALL recreate `freshrss_filedata`, restore the selected backup into the volume, start FreshRSS, and restart `filedata-backup` only if it was previously running
- **AND** the workflow SHALL fail if any step in the sequence fails

#### Scenario: Service resumes from restored volume
- **GIVEN** the latest backup archive has been restored into `freshrss_filedata`
- **WHEN** the workflow starts FreshRSS after extraction
- **THEN** the FreshRSS container SHALL be running and attached to `knowledge_network`
- **AND** restored application data SHALL be served from `freshrss_filedata`

### REQ-002: Backup retrieval and extraction SHALL be deterministic and validated
The workflow SHALL deterministically select a restore archive from Dropbox, validate that the selected file is available for download before destructive continuation, and fail with diagnostics if validation fails.

#### Scenario: Latest compatible archive is selected
- **GIVEN** multiple FreshRSS backup archives exist in the configured Dropbox path
- **WHEN** the restore workflow resolves the latest backup candidate
- **THEN** the selection logic SHALL choose the newest compatible archive by parsed timestamp
- **AND** the selected object path SHALL be reported in workflow output without exposing secret values

#### Scenario: Archive availability failure aborts destructive continuation
- **GIVEN** the selected backup cannot be listed or downloaded from Dropbox
- **WHEN** validation is attempted during restore
- **THEN** the workflow SHALL terminate with a non-zero result and diagnostic context
- **AND** it SHALL fail before stopping FreshRSS, stopping `filedata-backup`, or removing `freshrss_filedata`

#### Scenario: Streamed extraction restores the volume root
- **GIVEN** the selected backup archive has been downloaded successfully
- **WHEN** the workflow decrypts and extracts the archive into `freshrss_filedata`
- **THEN** it SHALL restore the archive through a streamed decrypt-and-extract flow into the recreated volume root
- **AND** it SHALL fail if decryption or extraction does not complete successfully

### REQ-003: Destructive restore actions SHALL require explicit operator confirmation
The workflow SHALL enforce an explicit confirmation input before executing any irreversible data-replacement steps.

#### Scenario: Missing confirmation blocks restore
- **GIVEN** the workflow is manually dispatched without the required confirmation value
- **WHEN** guard checks execute before remote restore operations
- **THEN** the workflow SHALL fail before stopping FreshRSS or removing `freshrss_filedata`
- **AND** output SHALL explain the required confirmation input

#### Scenario: Concurrent restore attempts are prevented
- **GIVEN** a FreshRSS restore run is already in progress on the target VM
- **WHEN** another restore run is started
- **THEN** the second run SHALL fail with a lock/concurrency error
- **AND** it SHALL NOT execute volume removal or extraction steps

### REQ-004: Restore workflow SHALL emit best-effort Discord notifications
The workflow SHALL attempt to send Discord notifications for both restore success and restore failure when `DISCORD_WEBHOOK_URL` is configured, but notification delivery failures SHALL NOT change the restore result.

#### Scenario: Success notification is attempted after verified restore
- **GIVEN** the restore workflow has completed successfully and `DISCORD_WEBHOOK_URL` is configured
- **WHEN** the workflow emits its completion notification
- **THEN** it SHALL attempt to send a success notification that identifies the FreshRSS restore outcome and selected backup
- **AND** a notification delivery failure SHALL be logged as a warning without changing the successful workflow result

#### Scenario: Failure notification is attempted after restore error
- **GIVEN** the restore workflow fails after entering a tracked restore phase and `DISCORD_WEBHOOK_URL` is configured
- **WHEN** the workflow emits its failure notification
- **THEN** it SHALL attempt to send a failure notification that includes the failing phase and failure detail
- **AND** a notification delivery failure SHALL be logged as a warning without replacing the original restore failure
