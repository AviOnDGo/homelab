# Configure the Google Cloud provider
provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

data "google_project" "current" {
  project_id = var.project_id
}

locals {
  bootstrap_startup_script = templatefile("${path.module}/bootstrap-startup.sh.tftpl", {
    bootstrap_git_deploy_key_secret_name = var.bootstrap_git_deploy_key_secret_name
    bootstrap_git_repo_ssh_url           = var.bootstrap_git_repo_ssh_url
  })

  vm_service_account_email = length(trimspace(var.vm_service_account_email)) > 0 ? var.vm_service_account_email : "${data.google_project.current.number}-compute@developer.gserviceaccount.com"
}

terraform {
  backend "gcs" {
    prefix = "tfstate"
  }
}

resource "google_compute_instance" "gcp-debian_free_tier_vm" {
  project      = var.project_id
  name         = "gcp-debian-free-tier-vm"
  machine_type = "e2-micro" # Free tier machine type
  zone         = var.zone   # Must be a free tier eligible zone (us-central1-a, us-east1-b, us-west1-b are common)

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12" # Use latest Debian 12 for better performance
      size  = 30                       # 30 GB standard persistent disk is part of free tier
      type  = "pd-standard"
    }
  }

  network_interface {
    network = "default" # Use the default network
    access_config {
      // Ephemeral IPs
    }
  }

  # Enable memory optimization for better performance
  scheduling {
    preemptible         = false
    automatic_restart   = true
    on_host_maintenance = "MIGRATE"
  }

  # metadata = {
  #   ssh-keys = "${var.ssh_user}:${file(var.ssh_public_key_path)}" # Add your SSH key for better connection stability
  # }

  metadata_startup_script = local.bootstrap_startup_script

  metadata = {
    for key, value in {
      "homelab-git-url"               = var.bootstrap_git_repo_ssh_url
      "homelab-git-deploy-key-secret" = var.bootstrap_git_deploy_key_secret_name
    } : key => value if length(trimspace(value)) > 0
  }

  tags = ["http-server"]

  service_account {
    email  = local.vm_service_account_email
    scopes = ["cloud-platform"]
  }
}

# Create firewall rule to allow port 9021.
# If this rule already exists outside Terraform, import it before apply:
# terraform import google_compute_firewall.allow_port_firefly \
#   projects/<project>/global/firewalls/allow-port-9021
resource "google_compute_firewall" "allow_port_firefly" {
  name    = "allow-port-9021"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["9021"]
  }

  source_ranges = ["0.0.0.0/0"]   # Allow from anywhere
  target_tags   = ["http-server"] # Targets VMs with this tag
}

# Create the budget
resource "google_billing_budget" "monthly_budget" {
  billing_account = var.billing_account_id
  display_name    = "Month Budget Alerts"

  budget_filter {
    projects = ["projects/${data.google_project.current.number}"]
    # You can also filter by services if you want the budget to apply only to Compute Engine:
    # services = ["services/6f817e08-f421-4f33-b452-f47285600000"] # Compute Engine API ID
  }

  amount {
    specified_amount {
      currency_code = var.budget_currency_code
      units         = 10
    }
  }

  threshold_rules {
    threshold_percent = 0.8 # 80% of the budget
    spend_basis       = "CURRENT_SPEND"
  }

  threshold_rules {
    threshold_percent = 1.0 # 100% of the budget
    spend_basis       = "CURRENT_SPEND"
  }
}