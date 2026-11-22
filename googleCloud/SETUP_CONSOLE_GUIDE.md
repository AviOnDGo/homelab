# GCP Console Setup Guide for GitHub OIDC Workflow

This guide expands the setup checklist in [googleCloud/README.md](googleCloud/README.md#L29) with detailed, click-by-click navigation.

## Scope

Use this guide before the first run of [.github/workflows/gcp-vm-deploy.yml](.github/workflows/gcp-vm-deploy.yml).

## Values You Should Prepare First

- `PROJECT_ID`: Target GCP project ID
- `PROJECT_NUMBER`: Numeric project number
- `BILLING_ACCOUNT_ID`: Billing account ID in format `XXXXXX-XXXXXX-XXXXXX`
- `REGION`: Terraform region
- `ZONE`: Terraform zone
- `SERVICE_ACCOUNT_NAME`: Suggested `gcp-vm-deployer`
- `SERVICE_ACCOUNT_EMAIL`: `<SERVICE_ACCOUNT_NAME>@<PROJECT_ID>.iam.gserviceaccount.com`
- `WIF_POOL_ID`: Suggested `github-pool`
- `WIF_PROVIDER_ID`: Suggested `github-provider`
- `REPO`: GitHub repository in format `<owner>/<repo>`
- `GCP_TF_STATE_BUCKET`: Existing VM Terraform state bucket (or a new bucket only
  for a genuinely new deployment)

## 1. Confirm Project and Billing

1. Open https://console.cloud.google.com/
2. In the top project selector, choose your target project.
3. Open Navigation menu -> Billing.
4. Confirm the project is linked to an active billing account.
5. If not linked: Billing -> Account management -> select billing account -> Account management -> Projects -> Link project.

## 2. Enable Required APIs

1. Open Navigation menu -> APIs & Services -> Library.
2. Enable each API below for your selected project:
- `Identity and Access Management (IAM) API` (`iam.googleapis.com`)
- `Cloud Resource Manager API` (`cloudresourcemanager.googleapis.com`)
- `Compute Engine API` (`compute.googleapis.com`)
- `Cloud Billing API` (`cloudbilling.googleapis.com`)
- `Cloud Billing Budget API` (`billingbudgets.googleapis.com`)
- `Security Token Service API` (`sts.googleapis.com`)
- `Service Account Credentials API` (`iamcredentials.googleapis.com`)
3. Verify in APIs & Services -> Enabled APIs & services.

## 3. Create Shared Deploy Service Account

1. Open Navigation menu -> IAM & Admin -> Service Accounts.
2. Click Create service account.
3. Name: `gcp-vm-deployer` (or your chosen name).
4. Click Create and continue.
5. Skip role assignment in this screen (you will add exact roles in the next steps).
6. Click Done.

## 4. Grant IAM Roles to Shared Service Account

Grant these exact roles.

### 4.1 Project-level roles

Navigation: IAM & Admin -> IAM

1. Click Grant access.
2. New principals: `SERVICE_ACCOUNT_EMAIL`.
3. Add roles:
- `Compute Instance Admin (v1)` -> `roles/compute.instanceAdmin.v1`
- `Compute Security Admin` -> `roles/compute.securityAdmin`
4. Save.

### 4.2 Billing-account role

Navigation: Billing -> select your billing account -> Account management -> Permissions

1. Click Add principal.
2. New principals: `SERVICE_ACCOUNT_EMAIL`.
3. Add role:
- `Billing Account Costs Manager` -> `roles/billing.costsManager`
4. Save.

### 4.3 Terraform backend bucket roles

If bucket does not exist yet, complete step 5 first and return.

Navigation: Cloud Storage -> Buckets -> select backend bucket -> Permissions

1. Click Grant access.
2. New principals: `SERVICE_ACCOUNT_EMAIL`.
3. Add roles:
- `Storage Object Admin` -> `roles/storage.objectAdmin`
- `Storage Legacy Bucket Reader` -> `roles/storage.legacyBucketReader`
4. Save.

## 5. Create Terraform Backend GCS Bucket

Navigation: Cloud Storage -> Buckets

1. Click Create.
2. Use a globally unique bucket name (for example, `<project-id>-terraform-state-bucket`).
3. Region: choose location close to your workload.
4. Access control: Uniform.
5. Protection: keep default settings or enable object versioning if desired.
6. Create bucket.
7. Go to bucket Permissions and grant roles from section 4.3.

## 6. Create Workload Identity Federation Pool and Provider

Navigation: IAM & Admin -> Workload Identity Federation

1. Click Create pool.
2. Pool ID: `WIF_POOL_ID` (for example `github-pool`).
3. Create.
4. In the pool, click Add provider.
5. Provider type: OpenID Connect (OIDC).
6. Provider ID: `WIF_PROVIDER_ID` (for example `github-provider`).
7. Issuer URL: `https://token.actions.githubusercontent.com`.
8. Configure attribute mapping exactly:
- `google.subject=assertion.sub`
- `attribute.repository=assertion.repository`
- `attribute.repository_owner=assertion.repository_owner`
- `attribute.ref=assertion.ref`
- `attribute.workflow_ref=assertion.job_workflow_ref`
- `attribute.workflow=assertion.workflow`
- `attribute.actor=assertion.actor`
- `attribute.environment=assertion.environment`
9. Add provider condition:
- `assertion.repository == "OWNER/REPO" && assertion.repository_owner == "OWNER"`
10. Create provider.

## 7. Add Conditional Impersonation Binding

Grant GitHub identities permission to impersonate the shared service account.

Navigation: IAM & Admin -> Service Accounts -> select `SERVICE_ACCOUNT_EMAIL` -> Permissions

1. Click Grant access.
2. New principals: principalSet for your WIF provider.
3. PrincipalSet format:

```text
principalSet://iam.googleapis.com/projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/WIF_POOL_ID/attribute.repository/OWNER/REPO
```

4. Add role:
- `Workload Identity User` -> `roles/iam.workloadIdentityUser`
5. IAM condition is optional when using repository-scoped principalSet member.
	Ref and workflow restrictions for apply are enforced in the workflow itself.

6. Save.

## 8. Configure GitHub Variables

Navigation: GitHub -> repository -> Settings -> Secrets and variables -> Actions -> Variables

Add these variables:
- `GCP_WIF_PROVIDER`
- `GCP_SERVICE_ACCOUNT`
- `GCP_PROJECT_ID`
- `GCP_BUDGET_CURRENCY_CODE` = the billing account's three-letter uppercase ISO 4217 currency code
- `GCP_TF_STATE_BUCKET` = the exact existing VM state bucket name
- `GCP_REGION` = `us-central1` (recommended for free tier)
- `GCP_ZONE` = `us-central1-a` (recommended for free tier)

Add `GCP_BILLING_ACCOUNT_ID` to the `prod` GitHub Environment as a Secret.

`GCP_WIF_PROVIDER` must be the full provider resource path:

```text
projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/WIF_POOL_ID/providers/WIF_PROVIDER_ID
```

## 9. Configure GitHub Environment Protection

Navigation: GitHub -> repository -> Settings -> Environments -> New environment

1. Create environment `prod`.
2. Add required reviewers.
3. Keep apply approvals gated by this environment.

## 10. Validate with Safe First Run

Navigation: GitHub -> repository -> Actions -> Deploy GCP VM Terraform

1. Run workflow.
2. First run:
- action: `plan`
- environment: `prod`
3. Verify:
- OIDC authentication succeeds.
- IAM permission checks pass.
- Terraform plan completes.
4. Second run (when ready):
- action: `apply`
- environment: `prod`
- branch/ref: `main`
- optional temporary test override: set `enforce_main_guard=false`
- Keep `allow_vm_replacement=false` unless a reviewed plan intentionally rebuilds
  the VM and its data has been backed up. Startup-template changes can require a
  rebuild; the workflow blocks them by default.

## Quick Troubleshooting

- OIDC auth fails:
- Verify `GCP_WIF_PROVIDER` path and provider condition values.
- Confirm issuer URL is exactly `https://token.actions.githubusercontent.com`.
- Confirm service account policy includes `roles/iam.workloadIdentityUser` for repository principalSet.
- Permission check fails:
- Recheck role assignments in sections 4.1 to 4.3 and ensure required GitHub variables exist in the `prod` environment.
- Terraform init fails with missing bucket:
- Verify `GCP_TF_STATE_BUCKET` identifies the existing state bucket and reapply
  section 4.3 IAM roles. Create a new bucket only for a new deployment; an empty
  replacement does not recover existing Terraform state.
- Apply blocked:
- Ensure workflow runs from `main`, uses the expected workflow file path, and has `prod` approval.
- For temporary non-main testing only, dispatch with `enforce_main_guard=false`.
