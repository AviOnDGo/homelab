## Requirements

### REQ-001: Preflight validation
The restore script SHALL verify that all required tools (`docker`, `rclone`, `gpg`, `zstd`, `flock`) are present and that the Docker daemon and Dropbox rclone remote are reachable before performing any destructive operation.

#### Scenario: Missing required tool
- **GIVEN** the restore script is invoked
- **WHEN** any of `docker`, `rclone`, `gpg`, `zstd`, or `flock` is not found on `PATH`
- **THEN** the script SHALL exit with a non-zero status and print an actionable error identifying the missing tool

#### Scenario: Docker daemon unreachable
- **GIVEN** the restore script is invoked
- **WHEN** `docker info` fails
- **THEN** the script SHALL exit with a non-zero status and print a message directing the operator to start Docker

#### Scenario: Dropbox remote unreachable
- **GIVEN** the restore script is invoked
- **WHEN** the `dropbox` rclone remote cannot be listed
- **THEN** the script SHALL exit with a non-zero status and print instructions for configuring or reconnecting the remote

### REQ-002: Passphrase acquisition
The restore script SHALL acquire the GPG passphrase before downloading any backup, either from the `PASSPHRASE` environment variable or by prompting the operator interactively (without echoing input).

#### Scenario: Passphrase via environment variable
- **GIVEN** `PASSPHRASE` is set in the environment before invoking the script
- **WHEN** the script reads the passphrase
- **THEN** it SHALL use the environment value without prompting

#### Scenario: Interactive passphrase prompt
- **GIVEN** `PASSPHRASE` is not set in the environment
- **WHEN** the script starts
- **THEN** it SHALL prompt for the passphrase without echoing characters to the terminal

#### Scenario: Empty passphrase rejected
- **GIVEN** the operator provides an empty passphrase (either via env or interactive)
- **WHEN** the passphrase validation check runs
- **THEN** the script SHALL exit with a non-zero status and print an error

### REQ-003: Latest backup discovery
The restore script SHALL identify the most recent backup archive at the configured Dropbox path without requiring the operator to specify a filename.

#### Scenario: Backups present
- **GIVEN** one or more files matching `freshrss_*.tar.zst.gpg` exist at `dropbox:/Apps/freshrss`
- **WHEN** the script lists available backups
- **THEN** it SHALL select the lexicographically last filename as the restore target

#### Scenario: No backups found
- **GIVEN** no matching backup files exist at `dropbox:/Apps/freshrss`
- **WHEN** the script attempts to list backups
- **THEN** it SHALL exit with a non-zero status and print the Dropbox path along with instructions to verify it

### REQ-004: Destructive operation confirmation
The restore script SHALL require confirmation before stopping a running container and before wiping an existing volume.

#### Scenario: Service running at restore time
- **GIVEN** the `freshrss` container is running
- **WHEN** the script reaches the stop step
- **THEN** it SHALL print a warning and prompt for `[y/N]` confirmation before stopping the service

#### Scenario: Operator declines service stop
- **GIVEN** the confirmation prompt is shown
- **WHEN** the operator enters anything other than `y` or `Y`
- **THEN** the script SHALL exit cleanly with a message indicating the restore was aborted

#### Scenario: Confirmation input is unavailable
- **GIVEN** a confirmation prompt is required
- **WHEN** no confirmation input is available
- **THEN** the script SHALL exit with a non-zero status and report that the restore was aborted

#### Scenario: Volume exists at restore time
- **GIVEN** the `freshrss_filedata` volume already exists
- **WHEN** the script reaches the volume preparation step
- **THEN** it SHALL print a warning and prompt for `[y/N]` confirmation before clearing the volume

#### Scenario: Backup container uses the volume
- **GIVEN** `filedata-backup` is running and a backup has been downloaded
- **WHEN** the script restores FreshRSS
- **THEN** it SHALL stop `filedata-backup` before clearing the volume and restart it only after successful health verification

### REQ-005: Archive extraction
The restore script SHALL decrypt and extract the backup archive into the `freshrss_filedata` volume using a streaming pipeline that avoids writing intermediate plaintext to disk.

#### Scenario: Successful extraction
- **GIVEN** the operator has confirmed all prompts and the encrypted archive is present in the temp directory
- **WHEN** the extraction pipeline runs
- **THEN** GPG SHALL decrypt the archive using a passphrase file descriptor, `zstd -d` SHALL decompress it, and `tar -xf -` SHALL extract it into the root of the `freshrss_filedata` volume via a temporary Alpine container

### REQ-006: Post-restore health verification
The restore script SHALL verify that FreshRSS is healthy after restart using the FreshRSS CLI, retrying for up to 300 seconds before declaring failure.

#### Scenario: FreshRSS becomes healthy within timeout
- **GIVEN** the service has been restarted after restore
- **WHEN** `docker exec freshrss php /var/www/FreshRSS/cli/health.php` exits 0 within 300 seconds
- **THEN** the script SHALL print a success banner and exit 0

#### Scenario: FreshRSS does not become healthy within timeout
- **GIVEN** the service has been restarted after restore
- **WHEN** 300 seconds elapse without `check-install.php` exiting 0
- **THEN** the script SHALL exit with a non-zero status and print the command to inspect container logs

### REQ-007: Cleanup on exit
The restore script SHALL remove all temporary files and unset the passphrase from the environment on any exit path (success or failure).

#### Scenario: Cleanup runs after successful restore
- **GIVEN** the restore completed successfully
- **WHEN** the script exits
- **THEN** the temp directory (`/tmp/freshrss-restore-$$`) SHALL be removed and `PASSPHRASE` SHALL be unset

#### Scenario: Cleanup runs after failure
- **GIVEN** the restore fails at any step
- **WHEN** the script exits with a non-zero status
- **THEN** the temp directory SHALL still be removed and `PASSPHRASE` SHALL still be unset
