## Requirements

### REQ-001: Onboarding prerequisites documentation
The homelab SHALL maintain an onboarding guide that enumerates all prerequisites for accessing and operating the homelab, with a verification command for each prerequisite.

#### Scenario: Prerequisites checklist is self-contained
- **GIVEN** a new developer or agent reads the onboarding spec
- **WHEN** they follow the prerequisites checklist
- **THEN** they SHALL be able to complete initial access setup without consulting any other documentation
- **AND** each prerequisite SHALL have a corresponding shell command to verify it is satisfied

#### Scenario: Docker group membership verification is documented
- **GIVEN** a new developer follows the onboarding prerequisites checklist
- **WHEN** they run the Docker verification command
- **THEN** `docker ps` SHALL succeed without `sudo`
- **AND** the guide SHALL document how to add the user to the `docker` group if the command fails

### REQ-002: Network topology diagram
The onboarding guide SHALL include a Docker network topology diagram showing all named category networks and which container categories belong to each, with NPM shown as crossing all networks.

#### Scenario: Developer understands cross-network communication scope
- **GIVEN** a developer consults the architecture diagram
- **WHEN** they need to determine if two services can communicate directly
- **THEN** the diagram SHALL enable them to answer that question without searching compose files
- **AND** NPM's multi-network role as the sole cross-gateway SHALL be clearly shown

### REQ-003: System health check procedure
The onboarding guide SHALL document a system health check procedure that an operator can complete in under 5 minutes to verify all critical services are running, disks are healthy, and last night's backups succeeded.

#### Scenario: Morning health check is executable in under 5 minutes
- **GIVEN** an operator runs the documented health check procedure
- **WHEN** all services are healthy
- **THEN** the procedure SHALL confirm: all critical containers are running, disk usage is below threshold, and the most recent backup completed successfully
- **AND** the entire procedure SHALL be completable in under 5 minutes

### REQ-004: Recurring operational SOPs
The onboarding guide SHALL document routines for: daily container status check, weekly backup log verification, monthly security update workflow, quarterly test-restore procedure, and periodic disk space reclamation.

#### Scenario: Monthly security updates SOP is documented
- **GIVEN** an operator follows the monthly update SOP
- **WHEN** applying container image updates
- **THEN** the SOP SHALL sequence: pull new images, recreate containers, verify service health
- **AND** the SOP SHALL document how to detect and handle a failed update before considering it complete

#### Scenario: Quarterly test-restore is documented
- **GIVEN** the quarterly schedule arrives
- **WHEN** an operator follows the test-restore procedure
- **THEN** they SHALL restore a backup to a non-production target and verify data integrity

### REQ-005: Emergency procedures for critical failure scenarios
The onboarding guide SHALL document emergency response procedures for: critical service down, complete host failure and rebuild from scratch, data corruption detection, and backup system failure.

#### Scenario: Critical service recovery procedure is documented
- **GIVEN** a core service (NPM, a database) fails to respond
- **WHEN** an operator follows the emergency procedure
- **THEN** the procedure SHALL guide them through: log inspection → container state check → resource check → restart steps

#### Scenario: Full system rebuild procedure is documented
- **GIVEN** the homelab host is lost and must be rebuilt
- **WHEN** an operator follows the rebuild procedure
- **THEN** it SHALL cover: git clone → dependency installation → rclone config restore → DB restore → volume restore → service startup → end-to-end verification

### REQ-006: Adding a new service follows a documented template
The onboarding guide SHALL document the standard steps for adding a new service to the homelab.

#### Scenario: New stateful service is added using the template
- **GIVEN** an operator adds a new service with persistent storage
- **WHEN** they follow the documented template
- **THEN** the template SHALL ensure the service has: named external volume, backup registration, NPM proxy host, and documented env variables
- **AND** no step SHALL be omittable without explicit justification

### REQ-007: Dropbox backup download procedure documentation
The homelab SHALL maintain a guide documenting the complete procedure for downloading GPG-encrypted backup files from Dropbox into a target VM for restore operations.

#### Scenario: Download procedure uses curl or wget
- **GIVEN** an operator needs to retrieve a backup file from Dropbox
- **WHEN** they consult the download guide
- **THEN** the guide SHALL provide copy-paste `curl` and `wget` commands using Dropbox shared links with `?dl=1` appended
- **AND** it SHALL document `rclone copy dropbox:/Apps/<service>/<file> .` as the preferred method when rclone is already configured

#### Scenario: Mobile app link creation procedure is documented
- **GIVEN** an operator needs to create a Dropbox download link from a mobile device
- **WHEN** they consult the guide
- **THEN** it SHALL document the 5-step mobile workflow: open Dropbox app → locate file → three-dot menu → Share → Create link → copy link

### REQ-008: Backup file verification before restore
The guide SHALL document verification steps that the operator SHALL perform on a downloaded backup before attempting a restore.

#### Scenario: GPG container verification is documented
- **GIVEN** an operator has downloaded an encrypted backup file
- **WHEN** they consult the verification procedure
- **THEN** the guide SHALL document `gpg --list-packets <file>` to confirm valid GPG packet structure
- **AND** SHALL document `file <decrypted_file>` to confirm the decrypted output matches the expected type (SQL text, tar archive)

### REQ-009: Shared link hygiene after download
The guide SHALL document the requirement and procedure for deleting or expiring the Dropbox shared link immediately after the file is downloaded.

#### Scenario: Link deletion via two UI paths is documented
- **GIVEN** an operator has completed the download
- **WHEN** they need to delete the Dropbox link
- **THEN** the guide SHALL document two UI paths for link deletion: via the Share icon → Manage link → Remove link, and via right-click → Share → Copy link → Remove link

#### Scenario: Link deletion is verified
- **GIVEN** the operator has deleted the Dropbox shared link
- **WHEN** they attempt to access the previously shared URL
- **THEN** the guide SHALL note that the URL SHALL return a "link no longer exists" response from Dropbox as confirmation

### REQ-010: End-to-end restore checklist
The guide SHALL provide an ordered checklist tying the Dropbox download procedure to the service-specific restore procedures documented in each service's `RESTORE_GUIDE.md`.

#### Scenario: End-to-end checklist covers all required steps
- **GIVEN** an operator follows the end-to-end restore checklist after a data loss event
- **WHEN** they complete all checklist steps
- **THEN** the checklist SHALL have covered: identify backup on Dropbox → create temporary link or use rclone → download encrypted file → decrypt → verify integrity → follow service RESTORE_GUIDE.md → delete temporary link → remove decrypted file from disk

### REQ-011: Troubleshooting common download failures
The guide SHALL document resolution steps for SSL errors and URL-encoded filenames encountered during Dropbox download operations.

#### Scenario: SSL certificate error resolution is documented
- **GIVEN** wget or rclone reports an SSL certificate error when accessing Dropbox
- **WHEN** the operator consults the guide
- **THEN** it SHALL document `sudo apt install --reinstall ca-certificates` as the first resolution step

#### Scenario: URL-encoded filename handling is documented
- **GIVEN** a downloaded file has `%20` or similar characters in its name
- **WHEN** the operator consults the guide
- **THEN** it SHALL explain URL-decoding before passing the filename to `gpg --decrypt`
