# Homelab

Personal homelab infrastructure for media, knowledge, AI, security, financial,
gaming, streaming, and backup workloads. Each stack is defined independently
with Docker Compose and can be fronted by Nginx Proxy Manager where applicable.

## Project Scope and Expectations

This repository documents one person's homelab and is shared as a reference, not as a
turnkey distribution or supported product. The configurations reflect specific hardware,
network, storage, and provider choices; expect to adapt them for your environment.

Before deploying anything, review the Compose files and scripts, follow the services'
current upstream documentation, and configure your own credentials, secrets, networks,
volumes, and access controls. Do not expose services to the internet without understanding
and reviewing their security requirements. No particular level of availability, support,
or fitness for your use case is promised. Third-party services and images remain subject
to their respective licenses and terms.

The repository contains configuration examples, not live credentials, backup
payloads, database contents, or a portable snapshot of an existing deployment.
Never publish a local `.env`, generated Terraform state, private key, stream key,
or service data.

---

## Service Roster

### Core Infrastructure
| Container | Purpose |
|-----------|---------|
| `npm` | Nginx Proxy Manager — reverse proxy and SSL termination |
| `watchtower` | Automatic container image updates |

### Media Services
| Container | Purpose |
|-----------|---------|
| `jellyfin` | Media streaming server |
| `sonarr` | TV series automation |
| `radarr` | Movie automation |
| `jackett` | Torrent indexer proxy |
| `transmission` | BitTorrent client |
| `invidious` + `invidious-companion` | Privacy-friendly YouTube frontend |
| `immich` | Self-hosted photo and video library |

### Knowledge Services
| Container | Purpose |
|-----------|---------|
| `freshrss` | RSS aggregator |
| `paperless` | Document management (OCR) |
| `radicale` | CalDAV/CardDAV service |

### AI Services
| Container | Purpose |
|-----------|---------|
| `gemini` | Interactive Gemini CLI agent for the Obsidian vault workspace |
| `hermes` | Agent gateway and automation service |
| `n8n` | Workflow automation |
| `ollama` | Local LLM inference engine |
| `omniroute` | OpenAI-compatible gateway with automatic provider routing |
| `opencode` | OpenCode browser-based coding agent (optional; see [service documentation](./aiServices/opencode/SERVICE_DOCUMENTATION.md)) |
| `openwebui` | Open WebUI chat interface for Ollama and OpenAI-compatible APIs |

### Security Services
| Container | Purpose |
|-----------|---------|
| `vaultwarden` | Bitwarden-compatible password manager |
| `pihole` | Network-level ad blocker and DNS |
| `gluetun` | VPN client sidecar |
| `syncserver` | Firefox Sync server |

### Financial Services
| Container | Purpose |
|-----------|---------|
| `firefly` | Firefly III personal finance manager |
| `firefly-cron` | Scheduled Firefly tasks |
| `firefly-db` | PostgreSQL database for Firefly |

### Gaming Services
| Container | Purpose |
|-----------|---------|
| `romm` | Game library management and emulation frontend |

### Streaming Services
| Container | Purpose |
|-----------|---------|
| `rtmp` | RTMP ingest server |

### Container Services
| Container | Purpose |
|-----------|---------|
| `firefox` | Browser accessible through noVNC |
| `syncthing` | Peer-to-peer file synchronization |

### Backup Services
| Container | Purpose |
|-----------|---------|
| `db-backup` | Scheduled PostgreSQL dumps (GPG-encrypted, rclone upload) |
| `filedata-backup` | Docker named volume backups (archive mode: GPG + Dropbox, sync-crypt mode: incremental rclone crypt) |

---

## Cloud & VPN

**Tailscale** network policy (ACLs, device tags) is managed as Terraform in
[`securityServices/tailscale/`](securityServices/tailscale/). Changes to
that configuration can be applied through the `tailscale-deploy` workflow
after the required repository variables and secrets are configured.

[`securityServices/tailscale/initial_setup.sh`](securityServices/tailscale/initial_setup.sh)
is for **one-time GCP bootstrap only**. Run it after editing its project-specific
values to install the local tools, create the Terraform service account,
credential file, billing binding, and state bucket. It is not needed for routine
ACL deployments: use Terraform locally or run the `tailscale-deploy` GitHub
Actions workflow.

### Tailscale deployment attributes

The workflow distinguishes non-secret GitHub Actions variables from credential
or identity secrets:

| Attribute | GitHub Actions classification | Use |
|-----------|-------------------------------|-----|
| `GCP_PROJECT_ID` | **Variable** (`vars`) | GCP project identifier passed to Terraform |
| `TAILSCALE_TF_STATE_BUCKET` | **Variable** (`vars`) | GCS bucket name for Terraform state |
| `TAILSCALE_TAILNET` | **Variable** (`vars`) | Tailnet name passed to Terraform |
| `GCP_CREDENTIALS` | **Secret** (`secrets`) | GCP service-account credential JSON |
| `TAILSCALE_OAUTH_CLIENT_ID` | **Secret** (`secrets`) | Tailscale OAuth client identifier |
| `TAILSCALE_OAUTH_CLIENT_SECRET` | **Secret** (`secrets`) | Tailscale OAuth client secret |
| `TAILSCALE_ADMIN_EMAIL` | **Secret** (`secrets`) | Identity in the Tailscale admin group |
| `TAILSCALE_PRIVILEGED_EMAIL` | **Secret** (`secrets`) | Identity in the Tailscale privileged group |

GitHub Actions variable names are not Terraform variable names. The workflow
maps repository variables and secrets to Terraform inputs such as
`var.project_id`, `var.tailscale_tailnet`, and
`var.tailscale_oauth_client_secret`. For local runs, copy
[`securityServices/tailscale/terraform.tfvars.example`](securityServices/tailscale/terraform.tfvars.example)
to a gitignored `terraform.tfvars` and replace only the example values.

**GCP VM** infrastructure is defined in [`googleCloud/`](googleCloud/) and
managed by guarded Terraform plan/apply/destroy workflow jobs. The VM bootstrap
can optionally clone this repository; it does not imply that every service in
the repository is deployed there.

---

## First-Time Setup

### Private configuration

Machine-specific MCP and OpenCode settings are intentionally not tracked.
For a new checkout, copy `.mcp.json.example` and `opencode.json.example` to
their corresponding names only when those local files do not already exist.
Customize the GitHub MCP token privately and export `GITHUB_TOKEN` in the
environment that launches your client.

The OpenCode example uses its supported `{env:VARIABLE}` substitutions. Export
`OLLAMA_REMOTE_BASE_URL` and `OLLAMA_LOCAL_BASE_URL` before launching OpenCode;
both must include `/v1`. Do not launch a client with unset endpoint variables.

Back up private client configuration in other existing clones before pulling
the cleanup: Git can remove files that were previously tracked.
Terraform backend configuration requires
the [GCP backend setup](googleCloud/README.md#private-backend-configuration).

### 1. Provision the machine

```bash
cd /path/to/homelab
./scripts/host/bootstrap.sh
```

Run bootstrap as your normal sudo-capable user on Ubuntu with systemd. It
installs Docker with the Compose plugin, starts SSH, and installs Tailscale.
It does not upgrade the whole system, disable Wi-Fi, or reboot. Log out and
back in if the script adds your user to the `docker` group. Docker group
membership grants root-equivalent access.

After bootstrap, and after starting a new login session if needed, verify Docker
access and SSH before starting container services:

```bash
docker compose version
docker info
systemctl is-active ssh
```

See the [host provisioning requirements](openspec/specs/homelab-core-infrastructure/spec.md#req-010-host-provisioning-is-separate-from-service-setup)
for the expected bootstrap, GPU, and swap behavior.

Host scripts previously at the repository root now live in `scripts/host/`.
Update any external runbooks or automation that use the old paths.

| Old path | New command |
|---|---|
| `setup.sh` | [`scripts/host/bootstrap.sh`](scripts/host/bootstrap.sh) |
| `configureDocker.sh` | [`scripts/host/configure-docker.sh`](scripts/host/configure-docker.sh) |
| `configureSSH.sh` | [`scripts/host/configure-ssh.sh`](scripts/host/configure-ssh.sh) |
| `configureTailscale.sh` | [`scripts/host/configure-tailscale.sh`](scripts/host/configure-tailscale.sh) |
| `increaseSwap.sh` | [`scripts/host/configure-swap.sh`](scripts/host/configure-swap.sh) |
| `installNvidiaDrivers.sh` | [`scripts/host/configure-nvidia-container-toolkit.sh`](scripts/host/configure-nvidia-container-toolkit.sh) |
| `installAmdRadeonDrivers.sh` | [`scripts/host/install-amd-rocm-wsl.sh`](scripts/host/install-amd-rocm-wsl.sh) |

Optional host setup:

- **NVIDIA:** Install the host driver separately and check `nvidia-smi -L`.
  Run `./scripts/host/configure-nvidia-container-toolkit.sh` to configure the
  Docker runtime. Restart Docker during a maintenance window, then verify GPU
  access before starting GPU-dependent services.
- **AMD ROCm:** `./scripts/host/install-amd-rocm-wsl.sh` is for Ubuntu 24.04 on
  WSL with GPU passthrough. Use AMD's native Linux instructions on a native host.
- **Swap:** `sudo ./scripts/host/configure-swap.sh` creates an 8 GiB
  `/swapfile` on ext4 or XFS, or enables an existing matching one. It
  leaves other swap devices alone and refuses to resize or format an
  unexpected existing file.

### 2. Configure networking

To enroll the host in your tailnet, run this once after bootstrap. The
standalone Tailscale installer does not enroll or reconfigure the host.

```bash
sudo tailscale up
tailscale status
```

### 3. Start services selectively

There is no root aggregate Compose deployment. Each service declares the
external networks and named volumes it expects; review its Compose file and
service documentation before creating those prerequisites.

For example, to start the container-services stacks:

```bash
docker network inspect container_network >/dev/null 2>&1 ||
  docker network create container_network

docker compose -f containerServices/firefox/docker-compose.yml up -d
docker compose -f containerServices/syncthing/docker-compose.yml up -d
```

Do not start every Compose file on a single host without reviewing port
conflicts, GPU support, storage paths, VPN requirements, and backup profiles.
Use each service's `SERVICE_DOCUMENTATION.md`; use its script-first
`RESTORE_GUIDE.md` when present for recovery.

Backup schedules are embedded in the backup-service Compose definitions and
do not require a repository-level host crontab.

---

## GitHub Actions Workflows

| Workflow | Trigger | Purpose |
|----------|---------|---------|
| `tailscale-deploy.yml` | Relevant pushes or manual dispatch | Validates and applies Tailscale Terraform configuration |
| `gcp-vm-deploy.yml` | GCP Terraform changes or manual dispatch | Plans and, with explicit action/guarding, applies or destroys the GCP VM |
| `gcp-freshrss-restore.yml` | Manual dispatch with confirmation | Restores FreshRSS backups on the GCP VM |
| `cleanup-workflow-runs.yml` | 1st of each month, 02:00 UTC | Deletes workflow run records older than 60 days (keeps ≥ 3 per workflow) |
| `pr-title.yml` | PR updates targeting `main` | Required check for the title that will become the squash commit subject |
| `release.yml` | Push to `main`, or manual dispatch on `main` | Validates and previews or publishes a source release; publishing is opt-in |
| `secret-scan.yml` | Pushes and pull requests | Scans tracked changes for secret patterns |

### Release conventions

Use `type(scope)!: description` for PR titles and squash commit subjects. The scope
and `!` are optional; the description must not be empty. The highest classification
since the last release wins:

| Example | Release |
|---------|---------|
| `fix(ollama): restore boot startup`, `perf: reduce startup latency`, `revert: undo default change` | Patch |
| `feat(backups): add integrity verification` | Minor |
| `docs!: change the restore procedure` or a commit with a `BREAKING CHANGE:` footer | Major |
| Non-breaking `docs`, `style`, `refactor`, `test`, `build`, `ci`, and `chore` | None |

For breaking PRs, use `!` in the title and include migration steps in the PR body
under a `BREAKING CHANGE:` footer. Start the footer with a description, and include
the affected services, prerequisites, and steps operators must take. Keep that
footer in the squash commit body so those steps appear in the generated notes.
**Validate PR title** reports invalid titles and is required by branch protection
on `main`. Review the final squash subject before merging: semantic-release reads
commits on `main`, and an unrecognized subject may miss its intended version bump.
Direct pushes follow the same convention.

### Activate or recover releases

Publishing is disabled until an operator approves and completes this sequence:

1. After the workflow and title checker are on `main`, enable squash merging only,
   with **Pull request title and description** as the default message. Require the
   `Validate PR title` status check in `main` branch protection.
   Restrict direct pushes where available, and review tag and notes write restrictions.
   The publishing job uses `GITHUB_TOKEN` with `contents: write`; do not add a PAT
   to bypass restrictions.
2. Record the reviewed `main` SHA immediately preceding activation. With explicit
   operator approval, tag it, publish the matching baseline release, and set the
   Actions repository variable `RELEASE_BASELINE_SHA` to that SHA:

   ```bash
   git fetch origin main --tags
   git tag -a v1.0.0 <reviewed-main-sha> -m 'Initial reviewed configuration baseline'
   git push origin refs/tags/v1.0.0
   gh release create v1.0.0 --verify-tag --title v1.0.0 \
     --notes 'Initial reviewed source configuration baseline.'
   git merge-base --is-ancestor 'v1.0.0^{commit}' origin/main
   ```

3. With the workflow on `main`, dispatch **Semantic Release** with **publish**
   unchecked. Record the predicted version and notes (or no release). The
   preview uses a temporary local Git mirror and does not publish.
4. Set the Actions repository variable `RELEASES_ENABLED` to `true`. Verify
   that a feature or fix merge creates exactly one release and a non-breaking
   docs-only merge creates none. To retry safely, dispatch on the current
   `main` with **publish** checked. A superseded run is skipped.

If publication fails after a tag is pushed, verify the tagged commit, review the
release notes, and publish the missing GitHub Release for **that same tag**
before retrying (use `gh release create <tag> --verify-tag`, or finish an existing
draft). Never move or delete the tag to retry. Check the original workflow logs
for permission or publication errors. To disable publication, unset
`RELEASES_ENABLED` and check for in-flight runs; disable the workflow as well if
validation and previews should stop. Preserve existing tags and releases.

A release tags the repository's source configuration. It does not deploy services,
snapshot data, or roll back volumes, and it cannot guarantee reproducibility while
upstream images, external services, and private configuration remain mutable.

---

## Documentation

All service and infrastructure specifications live in **[openspec/specs/](openspec/specs/)**. Each spec provides normative requirements and testable scenarios.

| Spec | Coverage |
|------|---------|
| [homelab-core-infrastructure](openspec/specs/homelab-core-infrastructure/) | Host provisioning, networking, and shared infrastructure |
| [media-services](openspec/specs/media-services/) | Jellyfin, Sonarr, Radarr, Transmission, Invidious, Immich |
| [knowledge-services](openspec/specs/knowledge-services/) | FreshRSS, Paperless |
| [ai-services](openspec/specs/ai-services/) | AI and automation services |
| [security-services](openspec/specs/security-services/) | Vaultwarden, Pi-hole, Gluetun |
| [container-services](openspec/specs/container-services/) | Firefox and Syncthing |
| [stream-services-rtmp](openspec/specs/stream-services-rtmp/) | RTMP ingest and restreaming |
| [financial-services](openspec/specs/financial-services/) | Firefly III |
| [gaming-services](openspec/specs/gaming-services/) | RomM |
| [cloud-integration](openspec/specs/cloud-integration/) | GCP provisioning and recovery automation |
| [backup-services](openspec/specs/backup-services/) | PostgreSQL and volume backup automation |
| [repository-conventions](openspec/specs/repository-conventions/) | Layout, secrets, documentation, and Git conventions |
| [operational-procedures](openspec/specs/operational-procedures/) | Standard operating procedures |
| [troubleshooting](openspec/specs/troubleshooting/) | Common issues and solutions |
| [onboarding-guide](openspec/specs/onboarding-guide/) | New maintainer and agent onboarding |

For contribution and agent conventions, see [AGENTS.md](AGENTS.md). Report
suspected vulnerabilities through the private process in
[SECURITY.md](SECURITY.md).
