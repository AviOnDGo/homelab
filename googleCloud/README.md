# GCP VM Deployment (OIDC + GitHub Actions)

This directory provisions the free-tier GCP VM with Terraform and deploys through GitHub Actions.

## Security Model

- Authentication uses GitHub OIDC Workload Identity Federation only.
- Static service account key files are not used.
- High-risk bootstrap secrets are not interpolated into Terraform-managed startup metadata.
- Production apply runs are gated by GitHub Environment protection.

## Workflow

Workflow file:
- .github/workflows/gcp-vm-deploy.yml

Execution behavior:
- Push to main with changes under googleCloud runs format, init, validate, and plan.
- Manual dispatch supports plan or apply.
- Apply is restricted to:
	- refs/heads/main
	- workflow ref .github/workflows/gcp-vm-deploy.yml@refs/heads/main
	- prod environment
	- Exception: for temporary testing only, workflow_dispatch can set `enforce_main_guard=false`.
- VM replacement plans are blocked by default. A reviewed manual run can set
  `allow_vm_replacement=true` after data backup and recovery preparation.
- Before every apply, schedule NPM and FreshRSS downtime, back up their current
  data, and verify that both latest Dropbox backups are current and usable.
- After successful apply, the reusable NPM restore workflow runs in `prod` and
  forcibly replaces existing NPM data from the latest backup, even after a
  no-op apply. It can also be dispatched manually from a permitted branch;
  manual runs replace existing NPM data only with `force`. GitHub requires
  the workflow file on the default branch for manual
  dispatch; the `prod` environment and OIDC trust policy must allow the branch.
  The separate restore job may require another `prod` approval. See the
  [NPM restore guide](../securityServices/npm/RESTORE_GUIDE.md).
- After successful applies and NPM restores, the workflow also forces a
  FreshRSS restore, including after no-op applies. FreshRSS is skipped if the
  NPM restore fails or is skipped. Manual FreshRSS restores skip an existing
  volume unless `force` is enabled. The separate job may require another `prod`
  approval. Before deployment, allow its workflow ref in the WIF provider
  condition below. See the [FreshRSS restore guide](../knowledgeServices/freshrss/RESTORE_GUIDE.md).

Rollback behavior:
- Re-run workflow against a prior known-good commit and choose action=apply.
- This reapplies the earlier Terraform state target declaratively.
- If trust-policy changes caused the failure, restore the prior WIF provider attribute condition and service-account IAM policy snapshot before rerun.
- If VM convergence changes need to be reverted, restore the prior instance configuration and re-run `terraform plan` before retrying apply.
- If a firewall import was incorrect, remove the imported state entry and re-check the live firewall instead of deleting the firewall rule blindly.

## Step-by-Step Setup Before Running Workflow

Complete these one-time steps before the first workflow run.

Detailed guide with console.google.com navigation paths:
- [googleCloud/SETUP_CONSOLE_GUIDE.md](googleCloud/SETUP_CONSOLE_GUIDE.md)

1. Confirm GCP project and billing
	- Create or select the target GCP project.
	- Link an active billing account.
	- Keep deployment region/zone aligned with free-tier eligibility if cost optimization is required.

2. Enable required APIs
	- Enable the following services in the project:
		- iam.googleapis.com
		- cloudresourcemanager.googleapis.com
		- compute.googleapis.com
		- cloudbilling.googleapis.com
		- billingbudgets.googleapis.com
		- sts.googleapis.com
		- iamcredentials.googleapis.com

3. Create the shared deploy service account
	- Create one service account for both plan and apply.
	- Example:
		- gcloud iam service-accounts create gcp-vm-deployer --project <project_id>

4. Grant least-privilege IAM to the shared service account
	- Grant only the permissions needed by resources in this module (compute instance, firewall, budget, and state backend access).
	- Keep unrelated project administration permissions out of this identity.
	- Exact roles to assign:
		- On project ${GCP_PROJECT_ID}:
			- roles/compute.instanceAdmin.v1
			- roles/compute.securityAdmin
		- On billing account ${GCP_BILLING_ACCOUNT_ID}:
			- roles/billing.costsManager
		- On Terraform state bucket (backend bucket only):
			- roles/storage.objectAdmin
			- roles/storage.legacyBucketReader

5. Create Terraform backend GCS bucket
	- Create a dedicated state bucket if not already present.
	- Grant backend access to the shared service account.
	- Set the existing bucket name privately through `GCP_TF_STATE_BUCKET` in CI
	  or an ignored `backend.hcl` locally; do not rename a deployed bucket.

6. Create Workload Identity Federation pool and provider
	- Create a workload identity pool in the same project.
	- Create an OIDC provider for token.actions.githubusercontent.com.
	- Configure claim mapping exactly as listed in the OIDC Trust Configuration section.

7. Add conditional impersonation binding
	- Allow GitHub identities from this repository to impersonate only the shared service account.
	- Use claim constraints for repository/ref/workflow_ref as documented below.
	- On the shared service account, grant:
		- roles/iam.workloadIdentityUser to your GitHub principalSet from the WIF provider.

8. Configure GitHub repository/environment variables
	- Set all variables listed in Required GitHub Variables.
	- Use the full provider resource in GCP_WIF_PROVIDER.

9. Configure GitHub Environment protection
	- Create prod environment with required reviewers.
	- Ensure apply is manually approved through prod environment gates.

10. Validate with a safe first run
	- Run workflow_dispatch with action=plan.
	- Review output and IAM validation checks.
	- Run workflow_dispatch with action=apply from main when ready.

## Required GitHub Variables


## Recommended Free Tier Region/Zone

- **GCP_REGION:** `us-central1` (recommended for free tier)
- **GCP_ZONE:** `us-central1-a` (recommended for free tier)

Configure these repository or environment variables:

- GCP_WIF_PROVIDER
	- Full resource name of workload identity provider.
	- Example: projects/123456789/locations/global/workloadIdentityPools/github-pool/providers/github-provider
- GCP_SERVICE_ACCOUNT
	- Service account email used for plan and apply jobs and attached to the VM.
	- The deployer must have `roles/iam.serviceAccountUser` on this service account.
	- The VM inherits the deployer's permissions; stronger privilege separation
	  requires updating the workflow to use a separate VM account.
- GCP_PROJECT_ID
	- Target GCP project.
- GCP_BUDGET_CURRENCY_CODE
	- Required three-letter uppercase ISO 4217 currency code matching the billing account. Sets Terraform's `budget_currency_code` for plan and destroy. Set it before merging changes that trigger the workflow; there is no default.
- GCP_TF_STATE_BUCKET
	- Existing GCS state bucket name. Required by plan, apply and destroy.
	- The state prefix remains `tfstate`; changing the input does not migrate state.
- GCP_REGION
	- Terraform region input.
- GCP_ZONE
	- Terraform zone input.

Optional variables:

- GCP_VM_NAME
	- Override target VM name for post-provision SSH onboarding.
	- Default: `gcp-debian-free-tier-vm`
- TAILSCALE_TAILNET
	- Tailnet name used when minting short-lived keys from OAuth credentials.
- BOOTSTRAP_GIT_REPO_SSH_URL
	- Optional SSH Git URL exported as `TF_VAR_bootstrap_git_repo_ssh_url`.
- BOOTSTRAP_GIT_DEPLOY_KEY_SECRET_NAME
	- Optional secret name exported as `TF_VAR_bootstrap_git_deploy_key_secret_name`.

## Required GitHub Secrets

- GCP_BILLING_ACCOUNT_ID
	- Billing account ID used for budget resources.

Tailscale credential options (configure one path for automatic onboarding;
otherwise onboarding is skipped with a warning):

- Option A (preferred): `TAILSCALE_OAUTH_CLIENT_ID` + `TAILSCALE_OAUTH_CLIENT_SECRET` with `TAILSCALE_TAILNET`
	- Workflow mints a short-lived key at runtime.
- Option B (fallback): `TAILSCALE_EPHEMERAL_AUTH_KEY`
	- Workflow fetches pre-generated short-lived key from secret store.

Optional Dropbox credentials for rclone on the VM:

- `DROPBOX_AUTH_TOKEN` + `DROPBOX_REFRESH_TOKEN`
	- After onboarding, the apply job runs `scripts/host/configure-rclone.sh` on the VM as root. It installs rclone and configures a verified `dropbox` remote in `/root/.config/rclone/rclone.conf`.
	- Tokens and the script are sent over SSH stdin, not command lines. If either secret is missing, the step warns and skips.

The NPM and FreshRSS restore workflows require `DROPBOX_AUTH_TOKEN`, `DROPBOX_REFRESH_TOKEN`,
and `GPG_PASSPHRASE` in `prod` (or repository secrets). Its own `prod` job
receives environment secrets independently; repository secrets are explicitly
passed to the reusable workflow. Missing credentials fail the restore job.
OIDC trust restrictions must also allow the reusable workflow's
`job_workflow_ref`, as well as manual runs of that workflow.

## OIDC Trust Configuration

Configure Workload Identity Provider claim mapping:

- google.subject=assertion.sub
- attribute.repository=assertion.repository
- attribute.repository_owner=assertion.repository_owner
- attribute.ref=assertion.ref
- attribute.workflow_ref=assertion.job_workflow_ref
- attribute.workflow=assertion.workflow
- attribute.actor=assertion.actor
- attribute.environment=assertion.environment

Provider condition baseline:

assertion.repository == "OWNER/REPO" &&
assertion.repository_owner == "OWNER" &&
assertion.environment == "prod" &&
assertion.ref == "refs/heads/main" &&
(assertion.job_workflow_ref == "OWNER/REPO/.github/workflows/gcp-vm-deploy.yml@refs/heads/main" ||
 assertion.job_workflow_ref == "OWNER/REPO/.github/workflows/gcp-npm-restore.yml@refs/heads/main" ||
 assertion.job_workflow_ref == "OWNER/REPO/.github/workflows/gcp-freshrss-restore.yml@refs/heads/main")

The reusable restore workflows also use this service account. Retain the single
provider value and include all three workflow refs in the explicit condition
above. Update an existing provider before running FreshRSS restores. Do not rely
on repository scope alone.

Binding condition baseline (single production service account):

principalSet://iam.googleapis.com/projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/WIF_POOL_ID/attribute.repository/OWNER/REPO

The IAM binding scopes impersonation to the repository principalSet. The WIF
provider attribute condition separately enforces repository, owner,
environment, ref, and workflow-ref claims. Workflow guard steps provide an
additional defense for `refs/heads/main` and workflow refs.

## Least-Privilege IAM Guidance

Shared identity:
- Includes required read/mutate permissions for instance, firewall, and budget resources managed by this module.
- Includes state bucket access scoped to backend path.
- Excludes unrelated administration permissions.

## Permission Validation in CI

The workflow validates IAM permissions at runtime using:

- Cloud Resource Manager `projects:testIamPermissions` API (via `curl` + OAuth token)
- `gcloud billing budgets list --billing-account=<id>` for billing budget access checks

Checks include:
- Shared identity has required read and mutate permissions.
- Shared identity does not have unrelated project admin permissions.
- Billing budget access checks fail with explicit messages when missing.

## Secret-Handling Rules

- Do not pass bootstrap secrets as Terraform variables consumed in metadata_startup_script.
- Do not print secrets in workflow logs.
- Keep Terraform debug logging disabled in production runs.
- Use workflow post-provision stages for secret-bearing Tailscale onboarding.
- If VM startup needs private clone credentials, store only secret *names* in Terraform and retrieve values at runtime via VM service account.

## First-Time Operator Checklist

- Confirm backend GCS bucket exists and is accessible by the shared service account.
- Configure workload identity provider and claim mappings.
- Configure a conditional binding for the shared service account identity.
- Set GitHub variables listed above.
- Ensure GitHub Environment prod has required reviewers/approvals.
- Run workflow_dispatch with action=plan.
- Review plan output for expected drift.
- Run workflow_dispatch with action=apply from main.
- Verify VM, firewall, and budget resources were reconciled correctly.

## Private Backend Configuration

Both Terraform modules use a partial GCS backend with the existing `tfstate`
prefix. Before running the updated workflows, set these GitHub environment
variables to the exact buckets already holding the corresponding state:

- `GCP_TF_STATE_BUCKET` for the VM module's `prod` environment.
- `TAILSCALE_TF_STATE_BUCKET` for every environment used by the Tailscale workflow.

Missing bucket inputs fail initialization before any plan/apply/destroy command.
Keep VM and Tailscale state in their respective existing buckets; swapping them
can select unrelated state. No bucket or state object is renamed by this change.

For local commands, copy each module's `backend.hcl.example` to an ignored
`backend.hcl`, enter its actual bucket, then initialize that module:

```bash
cd googleCloud
cp -n backend.hcl.example backend.hcl
# Edit backend.hcl privately before continuing.
terraform init -reconfigure -backend-config=backend.hcl
```

Repeat from `securityServices/tailscale` for its separate backend. Preserve any
existing workspace selection as well as bucket and prefix. Review a plan before
applying: unexpected resource creation is a reason to stop and check the backend.
Do not use `-migrate-state` merely to externalize the same backend settings.
For rollback, restore the previous workflow/configuration and reinitialize
against the same bucket and prefix; do not create an empty replacement backend.

VM bootstrap no longer sets a personal Git author identity. Cloning and fetching
do not require one. Configure an identity privately on hosts that create commits.
The Google provider recreates a VM when `metadata_startup_script` changes.
Removing the Netdata agent from the startup template therefore produces a
replacement plan for an existing VM. The workflow blocks that plan before
publishing it for apply unless a manual run explicitly enables
`allow_vm_replacement`. Back up application data and the boot disk and arrange a
maintenance window before approving a rebuild. The opt-in does not bypass the
existing main/ref or protected-environment checks. Local Terraform commands do
not execute this workflow guard; inspect their plan and do not apply an
unapproved replacement.

## State Drift Recovery

If `terraform apply` fails with `alreadyExists` for a resource that is supposed to be managed here, treat that as Terraform state drift first, not as a workflow or OIDC failure.

Example observed in this stack:

- `google_compute_firewall.allow_port_firefly`
- Remote object: `projects/<project>/global/firewalls/allow-port-9021`
- Recurring billing budget drift when using `projects/<project_id>` instead of the provider's canonical `projects/<project_number>` form

Recommended recovery sequence:

- Confirm the remote object really matches the Terraform intent.
- Import the existing object into the configured remote state.
- Use the canonical project number form for billing budget project references so repeated plans do not drift on identifier normalization.
- Re-run `terraform plan` and confirm the resource is no longer planned for creation.
- Re-run the GitHub Actions apply only after the plan is clean.

Example commands:

```bash
cd googleCloud
export TF_VAR_budget_currency_code="<billing-account-currency-code>"
terraform init -backend-config=backend.hcl
terraform import google_compute_firewall.allow_port_firefly \
	projects/<project>/global/firewalls/allow-port-9021
terraform plan \
	-var="project_id=<project>" \
	-var="billing_account_id=<billing-account-id>" \
	-var="region=<region>" \
	-var="zone=<zone>"
```

## Verification Checklist

- Confirm required variables are configured: `GCP_WIF_PROVIDER`, `GCP_SERVICE_ACCOUNT`, `GCP_PROJECT_ID`, `GCP_BUDGET_CURRENCY_CODE`, `GCP_TF_STATE_BUCKET`, `GCP_REGION`, `GCP_ZONE`.
- Confirm `prod` contains the `GCP_BILLING_ACCOUNT_ID` environment secret.
- Confirm `GCP_SERVICE_ACCOUNT` uses full email format (`<name>@<project>.iam.gserviceaccount.com`).
- Confirm Tailscale onboarding config is set (`TAILSCALE_TAILNET` and either OAuth credentials or an ephemeral auth key).
- Confirm WIF provider condition matches repository and owner values.
- Confirm service-account policy contains `roles/iam.workloadIdentityUser` binding for repository principalSet.
- Confirm backend bucket exists and includes `roles/storage.objectAdmin` and `roles/storage.legacyBucketReader` for deploy service account.
- Run workflow_dispatch `action=plan` from branch and confirm completion through auth/validate/init/plan.
- Run workflow_dispatch `action=apply` and verify post-provision checks:
	- Docker service active on VM
	- Tailscale backend state is `Running`
	- Optional startup clone completed or skipped with explicit non-secret log reason

## Onboarding Rollback

If post-provision onboarding fails after Terraform apply:

1. Temporarily remove or rotate failing onboarding secrets in `prod` environment.
2. Re-run workflow with `action=apply` to reapply infrastructure while skipping/failing fast on secret checks.
3. If needed, revert workflow onboarding steps to previous commit and re-run apply.
4. Keep startup script secret-safe during rollback; do not move secrets into Terraform metadata.

## Troubleshooting Notes

- OIDC error: `unauthorized_client` / credential rejected by attribute condition
	- Verify WIF provider `attributeCondition` matches repository and owner.
	- Verify service account has `roles/iam.workloadIdentityUser` for the repository principalSet.
- Permission-validation step fails before Terraform
	- Confirm workflow is using API-based permission checks (not deprecated/unsupported gcloud subcommands).
	- Recheck project and billing IAM role assignments for deploy service account.
	- Confirm required GCP variables are configured in the `prod` GitHub environment.
- Terraform init fails with `bucket doesn't exist`
	- Check `GCP_TF_STATE_BUCKET` points to the existing state bucket.
	- For a genuinely new deployment only, create its configured backend bucket.
	- Reapply backend bucket IAM roles for deploy service account.
- Terraform apply fails with `alreadyExists` for firewall, VM, or budget resources
	- Check whether the object already exists in GCP but is missing from Terraform state.
	- Import the existing resource into state instead of deleting and recreating it blindly.
	- For the firewall in this module, import ID format can be `projects/<project>/global/firewalls/allow-port-9021`.
	- Re-run `terraform plan` locally and confirm the drift is resolved before retrying CI apply.
- Apply succeeds but onboarding fails at SSH readiness
	- Confirm VM has external SSH reachability and project firewall allows SSH.
	- Confirm target VM name (`GCP_VM_NAME`) and zone values are correct.
- Tailscale onboarding fails with OAuth errors
	- Verify `TAILSCALE_OAUTH_CLIENT_ID`, `TAILSCALE_OAUTH_CLIENT_SECRET`, and `TAILSCALE_TAILNET` values.
	- If OAuth cannot mint key, configure `TAILSCALE_EPHEMERAL_AUTH_KEY` fallback and retry.
- Startup clone skips or fails
	- Ensure VM service account can access Secret Manager secret version.
	- Confirm deploy key secret name and SSH repo URL are configured and valid.
- Terraform plan shows a billing budget update even though the target project did not change
	- Check whether the budget filter is using `projects/<project_id>` instead of `projects/<project_number>`.
	- Use the canonical project number form expected by the Google provider to eliminate repeated normalization drift.
- Terraform apply wants to modify a running VM and requires stop acknowledgement
	- Remove non-essential instance settings that were added after the initial create if they do not provide required behavior.
	- If the setting must remain, explicitly allow stop-for-update behavior and schedule the apply accordingly.

## Local Terraform Commands (Optional)

Use local CLI only for development diagnostics. CI remains the source of truth.

From repository root:

```bash
cd googleCloud
cp -n terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your project and billing values.
cp -n backend.hcl.example backend.hcl
# Edit backend.hcl with the existing state bucket.
terraform fmt -check -recursive
terraform init -reconfigure -backend-config=backend.hcl
terraform validate
export USER_PROJECT_OVERRIDE=true
export GOOGLE_BILLING_PROJECT="<gcp-project-id>"
terraform plan
```

Local plan requires Google Application Default Credentials with access to the
project, billing account, and state bucket. Set `GOOGLE_BILLING_PROJECT` to a
quota project ID, not a billing account ID, and use `USER_PROJECT_OVERRIDE` to
send it with provider API requests. These exports apply only to the current
shell and do not configure the GitHub workflow.

The copied variable and backend files are ignored by Git; do not put credentials
or private keys in them. A plan does not apply changes; review it carefully
before any apply.