# Configure the Google Cloud provider
provider "google" {
  project     = var.project_id
  credentials = file(var.credentials_file)
  region      = var.region
  zone        = var.zone
}

terraform {
  required_providers {
    tailscale = {
      source  = "tailscale/tailscale"
      version = "~> 0.17"
    }
  }
  backend "gcs" {
    prefix = "tfstate"
  }
}

provider "tailscale" {
  oauth_client_id     = var.tailscale_oauth_client_id
  oauth_client_secret = var.tailscale_oauth_client_secret
  tailnet             = var.tailscale_tailnet
}

# resource "tailscale_tailnet_key" "ephemeral_key" {
#   reusable      = false
#   ephemeral     = true
#   preauthorized = true
#   tags          = ["tag:dev"]
# }

# # Identifying particular devices
# data "tailscale_devices" "aws_device" {
#     name_prefix = "aws"
# }

# data "tailscale_devices" "gcp_device" {
#     name_prefix = "gcp"
# }

# # Fetching the IP address of the first GCP device and using it as a DNS nameserver
# resource "tailscale_dns_nameservers" "dns_from_gcp" {
#   nameservers = [
#     data.tailscale_devices.gcp_device.devices[0].addresses[0]
#   ]
# }

resource "tailscale_acl" "main" {
  acl = jsonencode({
    groups = {
      "group:admin":      [var.tailscale_admin_email],
      "group:privileged": [var.tailscale_privileged_email],
      "group:member":     [],
    },
    tagOwners = {
      "tag:server": ["group:admin"],
    },
    acls = [
      {
        "action": "accept",
        "ports": [
          "tag:server:53",
          "tag:server:443",
        ],
        "users": [
          "tag:server",
        ],
      },
      {
        "action": "accept",
        "ports": [
          "tag:server:22",
          "tag:server:53",
          "tag:server:443",
          "tag:server:9003",
        ],
        "users": [
          "group:admin",
        ],
      },
      {
        "action": "accept",
        "ports": [
          "tag:server:53",
          "tag:server:443",
          "tag:server:9003",
        ],
        "users": [
          "group:privileged",
        ],
      },
      {
        "action": "accept",
        "ports": [
          "tag:server:53",
        ],
        "users": [
          "group:member",
        ],
      },
    ],
    ssh = [
      {
        "action": "accept",
        "src":    ["group:admin"],
        "dst":    ["tag:server"],
        "users":  ["autogroup:nonroot"],
      }
    ]
  })
}
