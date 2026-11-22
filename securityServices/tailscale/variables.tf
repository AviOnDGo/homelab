# GCP project details (non-secret Terraform variables)
variable "project_id" {
  type        = string
  description = "The GCP project ID"
}

# GCP credentials (secret source)
variable "credentials_file" {
  type        = string
  description = "Secret: path to the GCP service account key file"
  sensitive   = true
}

# GCP region and zone (non-secret Terraform variables)
variable "region" {
  type        = string
  description = "Region to deploy in"
  default     = "us-central1"
}
variable "zone" {
  type        = string
  description = "Zone to deploy in"
  default     = "us-central1-a"
}

# Tailscale configuration
variable "tailscale_admin_email" {
  type        = string
  description = "Secret: admin email for Tailscale ACL group membership"
  sensitive   = true
}

variable "tailscale_privileged_emails" {
  type        = list(string)
  description = "Secret: emails with privileged Tailscale ACL access"
  sensitive   = true
}

variable "tailscale_tailnet" {
  type        = string
  description = "Non-secret Tailscale tailnet name (usually <user>@gmail.com)"
}

variable "tailscale_oauth_client_id" {
  type        = string
  description = "Secret: Tailscale OAuth client ID for authentication"
  sensitive   = true
}

variable "tailscale_oauth_client_secret" {
  type        = string
  description = "Secret: Tailscale OAuth client secret for authentication"
  sensitive   = true
}