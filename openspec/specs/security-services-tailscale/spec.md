## Purpose
Define Tailscale infrastructure location, secret-management, and CI variable-handling requirements for security services.

## Requirements

### REQ-001: Tailscale infrastructure code resides under securityServices
Tailscale Terraform code and supporting configuration SHALL be located at `securityServices/tailscale/`, and no root-level `tailscale/` directory SHALL exist.

#### Scenario: Tailscale files are colocated with security services
- **GIVEN** repository layout is inspected
- **WHEN** checking Tailscale infrastructure paths
- **THEN** required Terraform and support files SHALL exist under `securityServices/tailscale/`
- **AND** no root-level duplicate Tailscale directory SHALL remain

### REQ-002: Tailscale Terraform secrets use sensitive variables
Sensitive values in Tailscale Terraform configuration SHALL be represented as variables marked `sensitive = true`, and sensitive literals SHALL NOT be hardcoded in tracked Terraform files.

#### Scenario: Sensitive values are variable-backed
- **GIVEN** `securityServices/tailscale/main.tf` and `variables.tf` are inspected
- **WHEN** searching for credential-like or PII literals
- **THEN** sensitive values SHALL be referenced via `var.*`
- **AND** variables carrying sensitive data SHALL declare `sensitive = true`

### REQ-003: Local Terraform runs use gitignored tfvars with example template
Operator-specific local values SHALL be supplied through gitignored `terraform.tfvars`, and `terraform.tfvars.example` SHALL document required variable keys.

#### Scenario: Local variable handling is documented and safe
- **GIVEN** Tailscale Terraform files and gitignore rules are inspected
- **WHEN** local variable material is reviewed
- **THEN** `.tfvars` files with real values SHALL be gitignored
- **AND** a tracked example file SHALL exist with placeholders

### REQ-004: CI passes sensitive Terraform variables from GitHub Secrets
The Tailscale deployment workflow SHALL pass sensitive Terraform variables from `${{ secrets.* }}` values and SHALL NOT embed sensitive literals in workflow definitions.

#### Scenario: Workflow var flags source secrets
- **GIVEN** `.github/workflows/tailscale-deploy.yml` is inspected
- **WHEN** terraform apply arguments are reviewed
- **THEN** sensitive `-var` flags SHALL reference GitHub Secrets
- **AND** no sensitive literal SHALL appear in the workflow file

### REQ-005: initial_setup.sh remains self-documenting and variable-driven
`securityServices/tailscale/initial_setup.sh` SHALL be identified as a one-time GCP bootstrap and SHALL declare editable non-secret GCP-related variables near the top. It SHALL receive the billing account through the environment and SHALL NOT be required for normal Terraform deployments.

#### Scenario: Script configuration is centralized
- **GIVEN** `securityServices/tailscale/initial_setup.sh` is inspected
- **WHEN** initial setup variable declarations are reviewed
- **THEN** non-secret project-specific values SHALL be declared in one editable block
- **AND** the billing account SHALL be supplied through the environment
- **AND** hardcoded project identifiers SHALL NOT appear in later script body sections

#### Scenario: Existing service-account key is reused safely
- **GIVEN** a credential file already exists at the configured path
- **WHEN** initial setup is run
- **THEN** the script SHALL reuse the file only if its client email matches the configured service account
- **AND** an invalid or mismatched file SHALL be left unchanged and reported as an error

#### Scenario: Normal deployments do not rerun initial setup
- **GIVEN** the Tailscale deployment workflow or Terraform command is run
- **WHEN** applying ACL configuration
- **THEN** `initial_setup.sh` SHALL NOT be invoked
- **AND** normal deployment SHALL use the existing GCP credentials and Terraform state bucket

### REQ-006: Tailscale inputs explicitly identify variables and secrets
Tailscale Terraform inputs, local examples, and GitHub Actions configuration SHALL clearly distinguish non-secret variables from secrets.

#### Scenario: Terraform input declarations are classified
- **GIVEN** `securityServices/tailscale/variables.tf` is inspected
- **WHEN** each Terraform input is reviewed
- **THEN** non-secret inputs SHALL be described as variables
- **AND** credential, OAuth, and identity inputs SHALL be described as secrets
- **AND** only secret inputs SHALL use `sensitive = true`

#### Scenario: GitHub Actions attributes are classified
- **GIVEN** `.github/workflows/tailscale-deploy.yml` is inspected
- **WHEN** deployment attributes are reviewed
- **THEN** non-secret project, tailnet, and state-bucket values SHALL use `${{ vars.* }}`
- **AND** GCP credentials, OAuth credentials, and member identities SHALL use `${{ secrets.* }}`
- **AND** documentation SHALL provide the attribute name and classification for each input

### REQ-007: Privileged group accepts multiple identities
The Tailscale privileged ACL group SHALL use a sensitive list of identities supplied
through Terraform inputs and the deployment workflow.

#### Scenario: Multiple privileged identities are configured
- **GIVEN** multiple identities are supplied in `tailscale_privileged_emails`
- **WHEN** Terraform constructs the Tailscale ACL
- **THEN** all supplied identities SHALL be members of `group:privileged`
- **AND** the deployment workflow SHALL obtain the list from a GitHub secret
