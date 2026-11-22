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

# This script sets up Google Cloud SDK and Terraform on macOS using Homebrew.
brew tap hashicorp/tap
brew install hashicorp/tap/terraform
brew install --cask google-cloud-sdk
echo 'source "$(brew --prefix)/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/path.bash.inc"' >> ~/.zshrc
echo 'source "$(brew --prefix)/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/completion.bash.inc"' >> ~/.zshrc
source ~/.zshrc  # or restart your terminal

# Initialize Google Cloud SDK
gcloud init

# NOTE: Make sure the Service Usage API is enabled in the Google Cloud Console
# https://console.developers.google.com/apis/api/serviceusage.googleapis.com/overview?project=${PROJECT_ID}
# Enable necessary APIs
gcloud services enable \
    serviceusage.googleapis.com \
    iam.googleapis.com \
    cloudresourcemanager.googleapis.com \
    cloudbilling.googleapis.com \
    billingbudgets.googleapis.com \
    --project="${PROJECT_ID}"

# Create the new user [Only first time]
gcloud iam service-accounts create "${SA_NAME}" --display-name "Terraform Admin"

# Create a new service account key
gcloud iam service-accounts keys create "${CREDENTIALS_PATH}" \
  --iam-account="${SA_EMAIL}"

# Grant billing permissions
gcloud alpha billing accounts add-iam-policy-binding "${BILLING_ACCOUNT}" \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="roles/billing.costsManager"

# Create and Grant storage permissions
gcloud storage buckets create "gs://${BUCKET_NAME}" \
    --project="${PROJECT_ID}" \
    --location="${LOCATION}" \
    --uniform-bucket-level-access
gcloud storage buckets add-iam-policy-binding "gs://${BUCKET_NAME}" \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="roles/storage.objectAdmin"