variable "project_id" {
  description = "The GCP project ID"
  type        = string

  validation {
    condition     = length(trimspace(var.project_id)) > 0
    error_message = "project_id must be non-empty."
  }
}

variable "region" {
  default     = "us-central1"
  description = "Region to deploy in"
}

variable "zone" {
  default     = "us-central1-a"
  description = "Zone to deploy in"
}

variable "billing_account_id" {
  type        = string
  description = "Billing Account ID (format: XXXX-XXXX-XXXX)"

  validation {
    condition     = length(trimspace(var.billing_account_id)) > 0
    error_message = "billing_account_id must be non-empty."
  }
}

variable "budget_currency_code" {
  description = "ISO 4217 currency code of the GCP billing account."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[A-Z]{3}$", var.budget_currency_code))
    error_message = "budget_currency_code must be a three-letter uppercase ISO 4217 currency code."
  }
}

variable "vm_service_account_email" {
  description = "Optional dedicated VM service account email for startup runtime API access."
  type        = string
  default     = ""
}

variable "bootstrap_git_repo_ssh_url" {
  description = "Optional SSH URL for startup clone (example: git@github.com:owner/repo.git)."
  type        = string
  default     = ""
}

variable "bootstrap_git_deploy_key_secret_name" {
  description = "Optional Secret Manager secret name containing startup deploy key private key."
  type        = string
  default     = ""
}