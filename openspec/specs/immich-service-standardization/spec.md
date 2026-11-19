## Purpose
Define the standardized operational documentation and restore workflow requirements for the Immich service.

## Requirements

### REQ-001: Immich operational docs are standardized
The `mediaServices/immich/` directory SHALL include `SERVICE_DOCUMENTATION.md` and `RESTORE_GUIDE.md` as the canonical operational documents.

#### Scenario: Required docs are present
- **GIVEN** the Immich service directory is inspected
- **WHEN** tracked files are listed
- **THEN** `SERVICE_DOCUMENTATION.md` SHALL be present
- **AND** `RESTORE_GUIDE.md` SHALL be present

### REQ-002: Legacy Immich onboarding artifacts are removed
The Immich service directory SHALL NOT contain `README.md` or `setup.sh` once standardized documentation is in place.

#### Scenario: Legacy artifacts are absent
- **GIVEN** the Immich service directory is inspected after standardization
- **WHEN** tracked files are listed
- **THEN** `README.md` SHALL NOT be present
- **AND** `setup.sh` SHALL NOT be present

### REQ-003: Immich restore guidance is script-first
The Immich `RESTORE_GUIDE.md` SHALL define `mediaServices/immich/restore.sh` as the primary restore path and SHALL document manual command-based fallback steps for exceptional recovery cases.

#### Scenario: Restore guide is script-first
- **GIVEN** an operator opens `mediaServices/immich/RESTORE_GUIDE.md`
- **WHEN** reviewing the primary restore procedure
- **THEN** the guide SHALL direct the operator to run `mediaServices/immich/restore.sh` as the primary path
- **AND** the guide SHALL include manual fallback steps for exceptional recovery conditions
