# Homelab

Personal homelab infrastructure running media, knowledge, AI, security, financial, gaming, and backup services — orchestrated via Docker Compose with Nginx Proxy Manager as the central gateway.

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

### AI Services
| Container | Purpose |
|-----------|---------|
| `gemini` | Interactive Gemini CLI agent for the Obsidian vault workspace |
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
| `watchtower` | Automatic image updates |

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

### Backup Services
| Container | Purpose |
|-----------|---------|
| `db-backup` | Scheduled PostgreSQL dumps (GPG-encrypted, rclone upload) |
| `filedata-backup` | Docker named volume backups (archive mode: GPG + Dropbox, sync-crypt mode: incremental rclone crypt) |

---

## Cloud & VPN

**Tailscale** network policy (ACLs, device tags) is managed as Terraform code in `tailscale/`. Changes to `tailscale/**.tf` merged to `main` are applied automatically via the `tailscale-deploy` GitHub Actions workflow using GCP-backed state.

**GCP VM** runs a fixed subset of services (pihole, npm, vaultwarden, firefly, freshrss). The `gcp` branch tracks the GCP-specific configuration. A `sync-gcp-branch` workflow opens a PR to sync `main` → `gcp` on every push.

---

## First-Time Setup

### Private configuration

Machine-specific MCP and OpenCode settings are intentionally not tracked.
Existing local `.mcp.json` and `opencode.json` files are preserved by the cleanup.
For a new checkout, copy `.mcp.json.example` and `opencode.json.example` to their
corresponding names only if those local files do not already exist. Customize
the GitHub MCP token privately and export `GITHUB_TOKEN` in the environment
that launches your client.

The OpenCode example uses its supported `{env:VARIABLE}` substitutions. Export
`OLLAMA_REMOTE_BASE_URL` and `OLLAMA_LOCAL_BASE_URL` before launching OpenCode;
both must include `/v1`. The root `.env.example` documents sample values, but
copying it does not automatically export variables into a tool's environment.
Do not launch a client with unset endpoint variables.

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

### 3. Start container services

Create the shared external network once, then start each service from its own
directory:

```bash
docker network inspect container_network >/dev/null 2>&1 ||
  docker network create container_network

docker compose -f containerServices/firefox/docker-compose.yml up -d
docker compose -f containerServices/syncthing/docker-compose.yml up -d
```

### 4. Cron jobs

```bash
sudo crontab -e
```

---

## GitHub Actions Workflows

| Workflow | Trigger | Purpose |
|----------|---------|---------|
| `tailscale-deploy.yml` | Push to `main` (paths: `tailscale/**.tf`) | Applies Tailscale ACL and device tag changes via Terraform |
| `sync-gcp-branch.yml` | Push to `main` | Opens/updates a PR to sync `main` into the `gcp` branch |
| `cleanup-workflow-runs.yml` | 1st of each month, 02:00 UTC | Deletes workflow run records older than 60 days (keeps ≥ 3 per workflow) |
| `pr-title.yml` | PR updates targeting `main` | Advisory check for the title that will become the squash commit subject |
| `release.yml` | Push to `main`, or manual dispatch on `main` | Validates and previews or publishes a source release; publishing is opt-in |

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
**Validate PR title (advisory)** reports invalid titles without being a required
merge check. Review the final squash subject before merging: semantic-release
reads commits on `main`, and an unrecognized subject may miss its intended
version bump. Direct pushes follow the same convention.

### Activate or recover releases

Publishing is disabled until an operator approves and completes this sequence:

1. After the workflow and title checker are on `main`, enable squash merging only,
   with **Pull request title and description** as the default message. Leave the
   title check advisory; branch protection is not needed to activate publishing.
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
| [homelab-core-infrastructure](openspec/specs/homelab-core-infrastructure/) | Docker, NPM, Homepage |
| [media-services](openspec/specs/media-services/) | Jellyfin, Sonarr, Radarr, Immich, Paperless |
| [knowledge-services](openspec/specs/knowledge-services/) | FreshRSS, Paperless |
| [ai-services](openspec/specs/ai-services/) | Ollama, Open WebUI |
| [security-services](openspec/specs/security-services/) | Vaultwarden, Pi-hole, Gluetun |
| [financial-services](openspec/specs/financial-services/) | Firefly III |
| [gaming-services](openspec/specs/gaming-services/) | RomM |
| [cloud-integration](openspec/specs/cloud-integration/) | Tailscale (Terraform), GCP sync workflow, run cleanup |
| [backup-services](openspec/specs/backup-services/) | PostgreSQL and volume backup automation |
| [operational-procedures](openspec/specs/operational-procedures/) | Standard operating procedures |
| [troubleshooting](openspec/specs/troubleshooting/) | Common issues and solutions |
| [onboarding-guide](openspec/specs/onboarding-guide/) | New maintainer and agent onboarding |
| [dropbox-download-guide](openspec/specs/dropbox-download-guide/) | Downloading backups from Dropbox |

For agent and tooling conventions, see [AGENTS.md](AGENTS.md).
