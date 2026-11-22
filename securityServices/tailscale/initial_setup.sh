#!/usr/bin/env bash
set -euo pipefail

# One-time GCP bootstrap for Tailscale Terraform.
# Re-running this script is safe: existing resources and configuration are reused.

# ─────────────────────────────────────────────────────
# Non-secret GCP variables — EDIT THESE BEFORE RUNNING
# ─────────────────────────────────────────────────────
PROJECT_ID="your-gcp-project-id"
BILLING_ACCOUNT="000000-000000-000000"
SA_NAME="terraform-sa"
BUCKET_NAME="your-tailscale-terraform-state-bucket"
LOCATION="us-central1"
CREDENTIALS_PATH="/tmp/gcp-credentials.json"

# Derived values
SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
# ─────────────────────────────────────────────────────

if [[ "${PROJECT_ID}" == "your-gcp-project-id" || "${BILLING_ACCOUNT}" == "000000-000000-000000" || "${BUCKET_NAME}" == "your-tailscale-terraform-state-bucket" ]]; then
  echo "Edit the project-specific variables near the top of $0 before running." >&2
  exit 1
fi

# This script bootstraps macOS hosts with Google Cloud SDK and Terraform.
brew tap hashicorp/tap
brew install hashicorp/tap/terraform
brew install --cask google-cloud-sdk

ZSH_LINE='source "$(brew --prefix)/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/path.bash.inc"'
if [[ -f "${HOME}/.zshrc" ]] && ! grep -Fqx "${ZSH_LINE}" "${HOME}/.zshrc"; then
  printf '\n%s\n' "${ZSH_LINE}" >> "${HOME}/.zshrc"
elif [[ ! -f "${HOME}/.zshrc" ]]; then
  printf '%s\n' "${ZSH_LINE}" > "${HOME}/.zshrc"
fi
source "$(brew --prefix)/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/path.bash.inc"

gcloud init

# Enable required APIs.
gcloud services enable \
  serviceusage.googleapis.com \
  iam.googleapis.com \
  cloudresourcemanager.googleapis.com \
  cloudbilling.googleapis.com \
  billingbudgets.googleapis.com \
  --project="${PROJECT_ID}"

# Create the Terraform service account only once.
if ! gcloud iam service-accounts describe "${SA_EMAIL}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
  gcloud iam service-accounts create "${SA_NAME}" \
    --display-name "Terraform Admin" \
    --project="${PROJECT_ID}"
fi

# Only create a local credential key when it does not already exist.
if [[ ! -f "${CREDENTIALS_PATH}" ]]; then
  gcloud iam service-accounts keys create "${CREDENTIALS_PATH}" \
    --iam-account="${SA_EMAIL}" \
    --project="${PROJECT_ID}"
fi

# These bindings are safe to reapply.
gcloud alpha billing accounts add-iam-policy-binding "${BILLING_ACCOUNT}" \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="roles/billing.costsManager"

if ! gcloud storage buckets describe "gs://${BUCKET_NAME}" >/dev/null 2>&1; then
  gcloud storage buckets create "gs://${BUCKET_NAME}" \
    --project="${PROJECT_ID}" \
    --location="${LOCATION}" \
    --uniform-bucket-level-access
fi

gcloud storage buckets add-iam-policy-binding "gs://${BUCKET_NAME}" \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="roles/storage.objectAdmin"
