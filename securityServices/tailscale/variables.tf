# GCP Project details
variable "project_id" {
  type        = string
  description = "The GCP project ID"
  sensitive   = true
}

# GCP Credentials
variable "credentials_file" {
  type        = string
  description = "Path to the service account key file"
  sensitive = true
}

# GCP Region and zone (the free one)
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

# Tailscale Configuration
variable "tailscale_admin_email" {
  type        = string
  description = "Admin email for Tailscale ACL group membership"
  sensitive   = true
}

variable "tailscale_privileged_email" {
  type        = string
  description = "Email with privileged Tailscale ACL access"
  sensitive   = true
}

variable "tailscale_tailnet" {
  type        = string
  description = "Tailscale tailnet name (usually <user>@gmail.com)"
  sensitive   = true
}

variable "tailscale_oauth_client_id" {
  type        = string
  description = "Tailscale OAuth client ID for authentication"
  sensitive   = true
}

variable "tailscale_oauth_client_secret" {
  type        = string
  description = "Tailscale OAuth client secret for authentication"
  sensitive   = true
}