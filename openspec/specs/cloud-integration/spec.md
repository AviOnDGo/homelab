## Purpose

Define normative requirements for cloud provisioning, deployment automation,
identity federation, bootstrap security, and post-provision operations for the
homelab's GCP-integrated infrastructure.

## Requirements

### REQ-001: GCP VM Terraform deployment SHALL be automated via GitHub Actions
The Terraform module under googleCloud SHALL be deployable through a dedicated GitHub Actions workflow so provisioning is repeatable, auditable, and environment-governed.

#### Scenario: Workflow plans on relevant infrastructure changes
- **GIVEN** a commit changes Terraform files under googleCloud
- **WHEN** the deployment workflow is triggered by push
- **THEN** the workflow SHALL run terraform init, validate, and plan
- **AND** no automatic production apply SHALL occur in that push-triggered path unless explicitly approved by policy

#### Scenario: Apply requires protected environment controls
- **GIVEN** an operator requests deployment apply from GitHub Actions
- **WHEN** the apply stage starts
- **THEN** the job SHALL run within a protected GitHub Environment
- **AND** environment-scoped approvals and secrets SHALL be enforced

#### Scenario: Terraform execution is scoped to deployment module path
- **GIVEN** the workflow executes Terraform commands
- **WHEN** commands are run by the CI job
- **THEN** the working directory SHALL be googleCloud
- **AND** commands SHALL run with non-interactive flags suitable for CI automation

#### Scenario: Permission validation uses supported runner-compatible interfaces
- **GIVEN** the workflow validates deploy identity permissions before Terraform plan/apply
- **WHEN** CI permission checks execute on GitHub-hosted runners
- **THEN** checks SHALL use supported command or API surfaces available in runner images
- **AND** workflow execution SHALL fail with explicit error output when required permissions are absent

#### Scenario: Running-instance convergence avoids stop-blocked drift
- **GIVEN** the Terraform module manages a running GCP VM instance
- **WHEN** configuration changes are applied through the deployment workflow
- **THEN** the module SHALL avoid introducing in-place updates that GCP rejects for running instances unless the configuration explicitly permits the required stop/update behavior
- **AND** routine apply runs SHALL NOT fail solely because Terraform added non-essential instance settings after the initial create

#### Scenario: Startup-template changes require explicit replacement approval
- **GIVEN** a plan includes deletion and creation of a managed VM
- **WHEN** the deployment workflow prepares the saved plan for apply
- **THEN** the workflow SHALL reject it unless a manual dispatch explicitly enables VM replacement
- **AND** replacement approval SHALL NOT bypass main/ref or environment approval checks

### REQ-002: GCP authentication in CI SHALL use keyless OIDC federation only
The deployment workflow SHALL authenticate to GCP using GitHub OIDC Workload Identity Federation and SHALL NOT use static service account key files on GitHub-hosted runners.

#### Scenario: OIDC authentication path is mandatory
- **GIVEN** Workload Identity Federation is configured for the repository
- **WHEN** the workflow requests GCP access
- **THEN** authentication SHALL use GitHub OIDC-issued identity tokens
- **AND** no static service account key file SHALL be present in repository, secrets, or runner filesystem

#### Scenario: OIDC trust boundary is claim-constrained
- **GIVEN** the workflow exchanges a GitHub OIDC token for GCP access
- **WHEN** trust conditions are evaluated by Workload Identity Federation
- **THEN** access SHALL be constrained by repository, ref, workflow, and environment claims
- **AND** tokens from non-matching repositories or refs SHALL be rejected

#### Scenario: Service account impersonation is repository-scoped
- **GIVEN** a workflow identity token satisfies provider attribute conditions
- **WHEN** GCP evaluates service account impersonation authorization
- **THEN** the deploy service account SHALL grant roles/iam.workloadIdentityUser only to approved repository principal sets
- **AND** workflows outside the approved repository scope SHALL be denied impersonation

### REQ-003: Sensitive bootstrap inputs SHALL NOT leak through metadata, state, or logs
High-risk credentials used for VM bootstrap SHALL be handled such that instance metadata, Terraform state, plan output, and workflow logs do not expose secret values.

#### Scenario: Startup script secret interpolation is prohibited for high-risk values
- **GIVEN** Terraform variables include sensitive values for bootstrap
- **WHEN** metadata startup commands are authored
- **THEN** high-risk secrets SHALL NOT be directly interpolated into Terraform-managed startup script content
- **AND** an alternate secure retrieval mechanism SHALL be used

#### Scenario: Terraform state and metadata remain secret-free
- **GIVEN** a Terraform apply completes for the VM module
- **WHEN** operator-visible Terraform state and instance metadata are inspected
- **THEN** plaintext bootstrap credentials SHALL NOT be present
- **AND** no secret-bearing startup command SHALL be stored in metadata payloads

#### Scenario: CI output remains secret-safe
- **GIVEN** workflow logs and Terraform plan output are retained by GitHub Actions
- **WHEN** a deployment run completes
- **THEN** secret values SHALL NOT appear in logs or plan summaries
- **AND** any debug output mode that can reveal secret content SHALL remain disabled in production runs

### REQ-004: Terraform backend state prerequisites SHALL be validated before deployment execution
The deployment path SHALL ensure backend state bucket existence and access controls are in place before Terraform plan/apply execution.

#### Scenario: Backend identities are supplied privately
- **GIVEN** either Terraform module is initialized locally or in CI
- **WHEN** its partial GCS backend is configured
- **THEN** the bucket name SHALL come from a private backend file or a GitHub environment variable
- **AND** tracked backend configuration SHALL NOT contain a deployment bucket name
- **AND** the existing bucket, `tfstate` prefix and workspace SHALL be preserved during configuration externalization
- **AND** missing CI bucket inputs SHALL fail initialization before resource changes

#### Scenario: Backend bucket existence is required for init
- **GIVEN** Terraform backend is configured to use a GCS bucket
- **WHEN** terraform init is executed in CI
- **THEN** the backend bucket SHALL already exist
- **AND** missing backend buckets SHALL fail the workflow with a clear initialization error

#### Scenario: Deploy identity has backend read/write access
- **GIVEN** CI authenticates through the deploy service account
- **WHEN** Terraform interacts with backend state in GCS
- **THEN** the deploy identity SHALL have required bucket/object access for state operations
- **AND** insufficient backend IAM SHALL fail before apply is attempted

### REQ-005: Pre-existing GCP resources SHALL be reconciled with Terraform state before retrying apply
When a resource already exists remotely but is missing from the configured Terraform state, operators SHALL reconcile state with the existing object before retrying CI apply so deployment remains declarative and non-destructive.

#### Scenario: Existing firewall rule is imported after alreadyExists failure
- **GIVEN** a Terraform apply fails because a GCP firewall rule already exists remotely
- **WHEN** the operator confirms the remote firewall matches the Terraform definition
- **THEN** the existing firewall SHALL be imported into the configured Terraform state
- **AND** the operator SHALL re-run Terraform plan and confirm the firewall is no longer planned for creation before retrying apply

#### Scenario: Drift recovery avoids blind delete and recreate
- **GIVEN** a Terraform-managed VM, firewall, or budget resource already exists in GCP outside tracked state
- **WHEN** the operator performs deployment recovery
- **THEN** the recovery path SHALL prefer importing the existing resource into state
- **AND** the resource SHALL NOT be deleted solely to clear the alreadyExists error unless the operator intentionally chooses replacement

### REQ-006: GCP Terraform resources SHALL use canonical provider identifiers where required for convergence
The Terraform module SHALL use the canonical identifier forms expected by the Google provider for persisted resource references so repeated plans do not drift on semantically equivalent values.

#### Scenario: Billing budget targets canonical project identity
- **GIVEN** the billing budget filters usage to the deployed GCP project
- **WHEN** Terraform computes the budget filter project reference
- **THEN** the module SHALL use the canonical project number form required by the provider
- **AND** repeated plans SHALL NOT show budget updates caused only by project ID versus project number normalization

### REQ-007: Post-provision secure onboarding SHALL be workflow-orchestrated
After Terraform apply creates or updates the VM, secret-bearing onboarding operations SHALL be executed by workflow stages designed to keep secret values out of Terraform plan/state/metadata surfaces.

#### Scenario: Workflow executes secure onboarding phases after apply
- **GIVEN** Terraform apply completes successfully for the cloud VM module
- **WHEN** the deployment workflow proceeds to onboarding
- **THEN** secret-bearing operations (for example VPN claim and monitoring claim) SHALL run in post-provision workflow stages
- **AND** startup metadata SHALL remain free of secret values required by those operations

### REQ-008: Bootstrap success criteria SHALL include host readiness outcomes
The cloud integration deployment process SHALL validate host readiness outcomes that confirm startup convergence beyond resource creation, including explicit bootstrap status signaling.

#### Scenario: Deployment validates bootstrap outcomes before onboarding
- **GIVEN** a deployment run reports Terraform apply success
- **WHEN** post-apply readiness verification executes
- **THEN** the process SHALL validate startup convergence using host bootstrap status data
- **AND** onboarding SHALL start only after readiness status reports completion

#### Scenario: Deployment diagnostics are emitted on readiness failure
- **GIVEN** readiness verification does not reach completion
- **WHEN** verification exits due to failed status or timeout
- **THEN** deployment output SHALL include bootstrap status and recent bootstrap logs
- **AND** workflow execution SHALL fail before secret-bearing onboarding steps

### REQ-009: Bootstrap package convergence SHALL be validated through deployment readiness
Cloud VM deployment SHALL ensure Debian 12 bootstrap package installation progresses through supported package sets before post-provision onboarding executes.

#### Scenario: Readiness gate observes bootstrap package progression
- **GIVEN** the apply workflow has completed Terraform apply for the VM
- **WHEN** host readiness verification runs
- **THEN** it SHALL evaluate bootstrap status exported by startup execution
- **AND** onboarding SHALL remain blocked while status indicates an in-progress bootstrap phase

### REQ-010: Bootstrap readiness waiting SHALL be condition-based and bounded
The deployment workflow SHALL wait for bootstrap completion by polling host readiness state until a terminal status is observed or a bounded timeout is reached.

#### Scenario: Polling completes on success
- **GIVEN** bootstrap status transitions to completed before timeout
- **WHEN** polling is in progress
- **THEN** the workflow SHALL continue to onboarding stages in the same run

#### Scenario: Polling fails fast on terminal bootstrap failure
- **GIVEN** bootstrap status transitions to a failed terminal state
- **WHEN** readiness evaluation reads the terminal status
- **THEN** the workflow SHALL fail the run
- **AND** diagnostics SHALL include bootstrap status and bootstrap log tail output

#### Scenario: Polling fails on bounded timeout
- **GIVEN** bootstrap status remains non-terminal throughout configured attempts
- **WHEN** polling attempts are exhausted
- **THEN** the workflow SHALL fail with timeout context
- **AND** diagnostics SHALL include current status and recent bootstrap logs

### REQ-011: Runtime repository bootstrap auth SHALL remain least-privilege and ephemeral
Any optional repository clone performed during VM bootstrap SHALL use runtime-retrieved least-privilege credentials and SHALL remove secret material after use.

#### Scenario: Runtime credential cleanup after clone
- **GIVEN** bootstrap performs an authenticated clone for a private repository
- **WHEN** clone authentication executes
- **THEN** credentials SHALL be retrieved at runtime from approved secret sources
- **AND** temporary credential files SHALL be shredded or removed after clone completion

### REQ-013: Cloud recovery workflow SHALL use existing keyless GCP trust boundaries
FreshRSS recovery workflow execution SHALL authenticate to GCP using repository-approved keyless OIDC federation and SHALL run under protected environment controls.

#### Scenario: Recovery workflow uses OIDC and approved service account
- **GIVEN** a restore run is triggered from GitHub Actions
- **WHEN** the workflow requests GCP access for VM SSH operations
- **THEN** authentication SHALL use the configured workload identity provider and approved service account
- **AND** static service-account key files SHALL NOT be used in the workflow

#### Scenario: Protected environment guard is enforced
- **GIVEN** a restore run is initiated
- **WHEN** workflow jobs requiring destructive operations start
- **THEN** the run SHALL execute inside the protected GitHub Environment used for production cloud operations
- **AND** environment-level approvals and secret scoping SHALL be enforced

### REQ-014: Cloud recovery execution SHALL keep restore secrets out of persistent IaC surfaces
Restore credentials and passphrases SHALL be handled in workflow/runtime secret channels and SHALL NOT be persisted in Terraform configuration, state, or VM metadata startup content.

#### Scenario: Restore secrets remain out of Terraform and metadata
- **GIVEN** the recovery workflow configuration and Terraform cloud module are reviewed
- **WHEN** secret-bearing restore inputs are traced
- **THEN** no plaintext restore secret value SHALL appear in Terraform state, plan output, or instance startup metadata
- **AND** restore inputs SHALL be sourced from approved secret stores at runtime

#### Scenario: Workflow logs remain secret-safe during recovery
- **GIVEN** a restore run completes or fails
- **WHEN** CI logs are inspected
- **THEN** secret values for Dropbox access and decryption SHALL NOT be printed
- **AND** diagnostics SHALL remain sufficient to troubleshoot non-secret failures

### REQ-015: GCP VM provisioning SHALL exclude Netdata
GCP VM bootstrap and post-provision workflow execution SHALL NOT install Netdata, configure Netdata Cloud, or send VM metrics to Netdata services.

#### Scenario: VM provisioning does not enable Netdata reporting
- **GIVEN** a GCP VM is provisioned through the cloud workflow
- **WHEN** bootstrap and post-provision onboarding complete
- **THEN** Netdata SHALL NOT be installed or claimed
- **AND** Netdata claim credentials SHALL NOT be required or transmitted

### REQ-016: GCP deployment SHALL configure the rclone Dropbox remote on the VM
After onboarding, the deployment workflow SHALL run the workflow checkout's
`scripts/host/configure-rclone.sh` on the VM as root, sending Dropbox tokens and
the script over SSH standard input.

#### Scenario: Dropbox secrets are configured
- **GIVEN** `DROPBOX_AUTH_TOKEN` and `DROPBOX_REFRESH_TOKEN` exist in the `prod` environment
- **WHEN** the apply job reaches the rclone setup step
- **THEN** the VM SHALL have rclone installed and a verified `dropbox` remote in root's rclone config
- **AND** the tokens SHALL NOT appear in command lines, Terraform state, or VM metadata

#### Scenario: Dropbox secrets are absent
- **GIVEN** either Dropbox secret is empty in the `prod` environment
- **WHEN** the apply job reaches the rclone setup step
- **THEN** the step SHALL emit a warning and skip rclone setup without failing the deployment

### REQ-017: GCP Tailscale and DuckDNS setup SHALL be independently runnable
The deployment SHALL provide a reusable, manually dispatchable workflow to
install and connect Tailscale on the GCP VM and update its DuckDNS record.

#### Scenario: Login is required but credentials are missing
- **GIVEN** the VM's Tailscale backend state is `NeedsLogin` and credentials
  are incomplete
- **WHEN** the setup workflow runs
- **THEN** the login step SHALL emit a warning and skip login
- **AND** the DuckDNS update SHALL fail because Tailscale is not running

#### Scenario: An existing running session needs no credentials
- **GIVEN** the VM's Tailscale backend state is `Running`
- **WHEN** the setup workflow runs
- **THEN** it SHALL skip auth-key creation and login
- **AND** it SHALL continue to update DuckDNS with the VM's Tailscale IPv4 address

#### Scenario: A stopped session reconnects without credentials
- **GIVEN** the VM's Tailscale backend state is `Stopped`
- **WHEN** the setup workflow runs
- **THEN** it SHALL attempt `tailscale up` without an auth key
- **AND** it SHALL request login credentials only if the backend then reports `NeedsLogin`

#### Scenario: A VM requires initial Tailscale login
- **GIVEN** the VM needs Tailscale installation or login
- **WHEN** the setup workflow runs with valid onboarding credentials
- **THEN** it SHALL install Tailscale if needed and authenticate the VM
- **AND** it SHALL update DuckDNS only after Tailscale is running

#### Scenario: Tailscale or DNS update fails
- **GIVEN** Tailscale setup or the DuckDNS update fails
- **WHEN** the deployment invokes the setup workflow
- **THEN** the setup workflow SHALL report the failure
- **AND** service restore jobs SHALL NOT depend on its success

### REQ-018: Firefly GCP recovery SHALL be workflow-orchestrated
The deployment SHALL provide a reusable and manually dispatchable Firefly
database restore workflow using the existing GCP restore transport.

#### Scenario: Manual recovery protects an existing volume
- **GIVEN** an operator dispatches the Firefly restore workflow
- **WHEN** force is not enabled and the database volume exists
- **THEN** the restore SHALL skip the existing volume without replacing its data

#### Scenario: Deployment restores after NPM
- **GIVEN** the VM apply and NPM restore jobs complete successfully
- **WHEN** the deployment schedules Firefly recovery
- **THEN** it SHALL invoke the Firefly workflow with force enabled, including after a no-op apply
- **AND** the recovery SHALL share the queued service restore concurrency group

#### Scenario: Firefly credentials are transmitted privately
- **GIVEN** the restore workflow receives Dropbox, GPG, and Firefly configuration secrets
- **WHEN** it invokes the restore script on the VM
- **THEN** it SHALL transmit those values through SSH standard input without printing them or placing them in command arguments
- **AND** Firefly configuration SHALL be supplied to Compose without persisting it in the temporary workflow directory

### REQ-019: Pi-hole GCP recovery SHALL be workflow-orchestrated
The deployment SHALL provide a reusable and manually dispatchable Pi-hole
filedata restore workflow using the existing GCP restore transport.

#### Scenario: Manual recovery protects an existing volume
- **GIVEN** an operator dispatches the Pi-hole restore workflow
- **WHEN** force is not enabled and the Pi-hole volume exists
- **THEN** the restore SHALL skip the existing volume without replacing its data

#### Scenario: Deployment restores after NPM
- **GIVEN** the VM apply and NPM restore jobs complete successfully
- **WHEN** the deployment schedules Pi-hole recovery
- **THEN** it SHALL invoke the Pi-hole workflow with force enabled, including after a no-op apply
- **AND** the recovery SHALL share the queued service restore concurrency group

#### Scenario: Pi-hole credentials are transmitted privately
- **GIVEN** the restore workflow receives Dropbox, GPG, and Pi-hole password secrets
- **WHEN** it invokes the restore script on the VM
- **THEN** it SHALL transmit those values through SSH standard input without printing them or placing them in command arguments
- **AND** the Pi-hole password SHALL be supplied to Compose through the process environment
