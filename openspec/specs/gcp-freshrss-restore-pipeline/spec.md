## Purpose

Define normative requirements for a workflow-driven, audited FreshRSS restore
pipeline on the GCP VM, including ordering, destructive guardrails, and restore
validation behavior.

## Requirements

### REQ-001: Pipeline SHALL orchestrate FreshRSS restore on GCP
The system SHALL provide a reusable and manually triggered GitHub Actions workflow that performs FreshRSS recovery on the target GCP VM.

#### Scenario: Successful restore run follows required order
- **GIVEN** the operator has approved a FreshRSS restore with force enabled
- **WHEN** the workflow executes the remote restore sequence
- **THEN** it SHALL resolve and download the selected FreshRSS backup before stopping containers or clearing `freshrss_filedata`
- **AND** it SHALL stop `filedata-backup` if that container is running and stop the FreshRSS service if it is running
- **AND** it SHALL clear `freshrss_filedata` in place, restore the selected backup into the volume, start FreshRSS, and restart `filedata-backup` only if it was previously running
- **AND** the workflow SHALL fail if any step in the sequence fails

#### Scenario: Manual restore without force
- **GIVEN** the FreshRSS volume already exists
- **WHEN** the operator dispatches the workflow without force
- **THEN** the workflow SHALL skip the restore without clearing the volume

#### Scenario: Restore following successful NPM restore
- **GIVEN** Terraform Apply succeeds
- **WHEN** the NPM restore succeeds
- **THEN** the deployment workflow SHALL invoke the FreshRSS restore with force enabled

#### Scenario: NPM restore fails or is skipped
- **GIVEN** the NPM restore does not succeed
- **WHEN** the deployment workflow evaluates the FreshRSS restore job
- **THEN** it SHALL skip the FreshRSS restore

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
- **THEN** the selection logic SHALL choose the newest compatible timestamped `.tar.zst.gpg` archive by filename
- **AND** the selected object path SHALL be reported in workflow output without exposing secret values

#### Scenario: Archive availability failure aborts destructive continuation
- **GIVEN** the selected backup cannot be listed or downloaded from Dropbox
- **WHEN** validation is attempted during restore
- **THEN** the workflow SHALL terminate with a non-zero result and diagnostic context
- **AND** it SHALL fail before stopping FreshRSS, stopping `filedata-backup`, or clearing `freshrss_filedata`

#### Scenario: Streamed extraction restores the volume root
- **GIVEN** the selected backup archive has been downloaded successfully
- **WHEN** the workflow decrypts and extracts the archive into `freshrss_filedata`
- **THEN** it SHALL restore the archive through a streamed decrypt-and-extract flow into the cleared volume root
- **AND** it SHALL fail if decryption or extraction does not complete successfully

### REQ-003: Destructive restore actions SHALL require operator approval
The restore job SHALL use the GitHub `prod` environment with required reviewers configured before executing irreversible data-replacement steps.

#### Scenario: Approval is pending
- **GIVEN** the `prod` environment has required reviewers configured
- **WHEN** the workflow is manually dispatched
- **THEN** GitHub SHALL wait for an eligible reviewer to approve the job before it starts
- **AND** the workflow SHALL NOT stop FreshRSS or clear `freshrss_filedata` while approval is pending

#### Scenario: Concurrent workflow runs are serialized
- **GIVEN** a FreshRSS restore workflow run is already in progress
- **WHEN** another run of the workflow is dispatched
- **THEN** the workflow concurrency group SHALL prevent both runs from executing simultaneously

### REQ-005: Workflow SHALL invoke the selected checkout's FreshRSS restore script
The workflow SHALL transfer the selected checkout's restore script and Compose file to the VM and invoke the script from a temporary directory.

#### Scenario: VM checkout differs from the workflow checkout
- **GIVEN** the VM checkout is absent or differs from the workflow checkout
- **WHEN** the workflow performs a restore
- **THEN** it SHALL use the workflow checkout's script and Compose file without updating the VM checkout
- **AND** it SHALL use `freshrss` as the Compose project name
- **AND** it SHALL remove the temporary directory on exit
