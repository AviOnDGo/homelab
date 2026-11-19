# Homelab Infrastructure OpenSpec

This directory contains the baseline OpenSpec documentation for the homelab infrastructure. These specifications define the capabilities, requirements, and architecture of all services in the homelab.

## What is OpenSpec?

OpenSpec is a specification-driven development framework that documents:
- **What** the system does (capabilities)
- **How** it should behave (requirements and scenarios)
- **Why** design decisions were made (design documentation)
- **How to build it** (tasks and implementation)

## Specification Structure

```
openspec/
├── config.yaml                 # OpenSpec configuration
├── specs/                      # Baseline specifications (current state)
│   ├── homelab-core-infrastructure/
│   ├── media-services/
│   ├── knowledge-services/
│   ├── ai-services/
│   ├── security-services/
│   ├── backup-infrastructure/
│   ├── financial-services/
│   ├── gaming-services/
│   ├── monitoring-operations/
│   └── cloud-integration/
└── changes/                    # Work-in-progress changes
    └── [change-name]/
        ├── proposal.md
        ├── design.md
        ├── tasks.md
        └── specs/
```

## Baseline Specifications

The `specs/` directory contains the authoritative specification for the homelab infrastructure as it currently exists. Most categories use a single parent capability, and selected categories may additionally use namespaced child capabilities for service-level detail.

### Service Categories

#### 1. Core Infrastructure (`homelab-core-infrastructure/`)
**Capabilities:**
- Container orchestration (Docker/Podman)
- Service dashboard (Homepage)
- Automated updates (Watchtower)
- Reverse proxy with SSL (Nginx Proxy Manager)
- Network isolation
- GPU acceleration support

**Key Services:** Homepage, Watchtower, Nginx Proxy Manager

#### 2. Media Services (`media-services/`)
**Capabilities:**
- Media streaming (Jellyfin)
- TV show automation (Sonarr)
- Movie automation (Radarr)
- Torrent indexing (Jackett)
- BitTorrent client (Transmission)
- YouTube frontend (Invidious)
- Photo management (Immich)

**Key Services:** Jellyfin, Sonarr, Radarr, Jackett, Transmission, Invidious, Immich

#### 3. Knowledge Services (`knowledge-services/`)
**Capabilities:**
- All-in-one workspace (AFFiNE)
- RSS feed aggregation (FreshRSS)

**Key Services:** AFFiNE, FreshRSS

#### 4. AI Services (`ai-services/`)
**Capabilities:**
- Local LLM inference (Ollama)
- Chat interface (Open WebUI)
- GPU acceleration
- Multiple model support

**Key Services:** Ollama, Open WebUI

#### 5. Security Services (`security-services/`)
**Capabilities:**
- Password management (Vaultwarden)
- DNS ad-blocking (Pi-hole)
- VPN client (Gluetun)
- Multi-factor authentication
- Encrypted password storage

**Key Services:** Vaultwarden, Pi-hole, Gluetun

#### 6. Backup Infrastructure (`backup-infrastructure/`)
**Capabilities:**
- Automated PostgreSQL backups
- Docker volume backups
- GPG encryption (AES256)
- Multi-cloud synchronization (Dropbox, Google Drive, OneDrive)
- Retention policies
- Discord notifications
- Automated scheduling

**Key Services:** db-backup, filedata-backup

#### 7. Financial Services (`financial-services/`)
**Capabilities:**
- Personal finance management (Firefly III)
- Transaction tracking
- Budget management
- Multi-currency support
- Financial reporting

**Key Services:** Firefly III

#### 8. Gaming Services (`gaming-services/`)
**Capabilities:**
- ROM library management (RomM)
- Metadata discovery and game organization
- Emulation-friendly library workflow
- Nginx Proxy Manager routing for the web UI

**Key Services:** RomM

#### 9. Cloud Integration (`cloud-integration/`)
**Capabilities:**
- Cloud infrastructure provisioning (Terraform)
- VPN remote access (Tailscale)
- Multi-cloud backup sync
- GitOps configuration

**Key Services:** Terraform, Tailscale

#### 10. Monitoring & Operations (`monitoring-operations/`)
**Capabilities:**
- Container health monitoring
- Log management
- Resource monitoring
- Automated maintenance
- Performance metrics
- Alert generation

**Key Services:** (To be implemented)

## How to Use OpenSpec

### Reading Specifications

Each specification file (`spec.md`) contains:

1. **ADDED Requirements** - What the system must do
2. **Scenarios** - How the system behaves in specific situations
3. **Requirements use GIVEN-WHEN-THEN format:**
   ```markdown
   #### Scenario: Description
   - **GIVEN** initial conditions
   - **WHEN** an action occurs
   - **THEN** the expected result
   - **AND** additional expectations
   ```

### Making Changes

When you want to make changes to the homelab:

1. **Create a change:**
   ```bash
   openspec create "add-new-service"
   ```

2. **Write a proposal** explaining what and why

3. **Generate specifications** for the new/modified capabilities

4. **Create a design** documenting how it will work

5. **Generate tasks** for implementation

6. **Implement the tasks** one by one

7. **Archive the change** when complete

### Verifying Current State

The baseline specs can be used to:
- Verify the infrastructure meets requirements
- Understand how services should behave
- Troubleshoot issues (compare actual vs. expected behavior)
- Onboard new maintainers
- Plan future improvements

## Architecture Principles

### Network Isolation
Services are organized into isolated Docker networks by category:
- `media_network` - Media services
- `knowledge_network` - Knowledge management
- `ai_network` - AI services
- `security_network` - Security services
- `finance_network` - Financial services
- `gaming_network` - Gaming services

**Rationale:** Security through isolation, limiting blast radius of compromises

### Backup Strategy
Multi-tiered backup approach:
- **Database backups:** PostgreSQL dumps with GPG encryption
- **Volume backups:** Filesystem tar archives with GPG encryption
- **Cloud replication:** Dropbox, Google Drive, OneDrive
- **Retention:** 7 days default (configurable)

**Rationale:** Redundancy prevents data loss, encryption protects sensitive data

### Configuration Management
- Environment variables in `.env` files (Git-ignored)
- Secrets in Docker volumes or Vaultwarden
- Service definitions in `docker-compose.yml` (Git-tracked)

**Rationale:** Separation of code and configuration, security for sensitive data

### Container Updates
Watchtower automatically updates containers at 4 AM daily

**Rationale:** Security patches applied quickly, minimal manual intervention

## Spec Organization Conventions

All OpenSpec changes SHALL follow these conventions for creating and organizing specifications:

### Organizational Alignment
- **Parent category specs** correspond to top-level repository directories: `mediaServices/`, `securityServices/`, `containerServices/`, etc.
- Specification location mirrors service organization: Service category → `openspec/specs/<category>/spec.md`
- Example: Container services specifications live at `openspec/specs/container-services/spec.md` and correspond to `containerServices/` directory
- Categories with high service complexity MAY define namespaced child capabilities such as `security-services-<service-name>`.
- Parent category specs in those categories SHALL contain governance-level requirements only.

### Consolidation Pattern
When creating new specifications:
1. **Default to parent consolidation** — Narrow requirements SHOULD be placed in the relevant parent category specification.
2. **Use namespaced child specs when warranted** — If a category has dense, service-specific behavior, define child capabilities using `<category>-<service>` naming.
3. **Keep boundary strict** — Parent specs hold governance and cross-cutting policy; child specs hold implementation and service-specific operational requirements.
4. **Examples:**
   - Firefox browser service → Consolidated into `container-services/spec.md` (not a standalone `firefox-service` spec)
   - Security service details → Split into `security-services/spec.md` (governance) and `security-services-<service>/spec.md` (service details)
   - Backup procedures for a specific service → Consolidated into parent backup specs or dedicated restore capabilities
   - Service-specific environment variables → Consolidated into parent category or `environment-variables/spec.md`
   - Configuration standards for a service category → Consolidated into `repository-conventions/spec.md`

### Canonical Spec Format
All specifications in `openspec/specs/` SHALL use the canonical format:

1. **Single `## Requirements` header** at the top level (no `## ADDED Requirements` or changelog headers)
2. **Sequential REQ identifiers:** `### REQ-001:`, `### REQ-002:`, etc., numbered sequentially within each spec
3. **Normative language:** Use only `SHALL` and `SHALL NOT` — never use "should", "may", "must", or similar
4. **GIVEN-WHEN-THEN scenarios:** Every requirement SHALL include at least one scenario with all four elements:
   ```markdown
   #### Scenario: Descriptive name
   - **GIVEN** initial conditions
   - **WHEN** triggering action
   - **THEN** expected primary outcome
   - **AND** additional assertions
   ```

### Delta Specs in Changes
When a change creates new specifications:
1. Create delta spec files in `openspec/changes/<change-name>/specs/`
2. Use `## ADDED Requirements` header to distinguish from baseline specs
3. Delta spec REQ numbers start at the next sequential number in the parent baseline spec
4. Example: If `container-services/spec.md` has REQ-001 through REQ-006, new Firefox requirements in the delta spec are REQ-007 through REQ-013

### Applying Delta Specs
When applying a change to baseline:
1. Convert delta spec `## ADDED Requirements` header to `## Requirements` if consolidating into parent
2. Append delta requirements to the parent or to the relevant namespaced child spec in sequential order
3. Delete the standalone spec if it has been fully consolidated
4. Update tasks.md to reference the final baseline spec location

### Future Changes
All future OpenSpec changes SHALL:
- Organize new specs by category alignment
- Consolidate requirements into parent specs by default, and use namespaced child specs only for dense service-specific detail
- Use canonical format (REQ-NNN with GIVEN-WHEN-THEN scenarios)
- Create appropriate delta specs in `openspec/changes/<change-name>/specs/`
- Include consolidation tasks in `tasks.md` if removing standalone specs

## Documentation

All documentation lives in `openspec/specs/`. Each spec is the authoritative source for its service category or operational topic.

- **[backup-procedures](specs/backup-procedures/spec.md)** - Backup and restore guide
- **[troubleshooting](specs/troubleshooting/spec.md)** - Common issues and solutions
- **[environment-variables](specs/environment-variables/spec.md)** - Configuration reference
- **[onboarding-guide](specs/onboarding-guide/spec.md)** - New maintainer guide
- **[operational-procedures](specs/operational-procedures/spec.md)** - Standard operating procedures
- **[homelab-core-infrastructure](specs/homelab-core-infrastructure/spec.md)** - Core services
- **[media-services](specs/media-services/spec.md)** - Media streaming and management
- **[knowledge-services](specs/knowledge-services/spec.md)** - Knowledge management tools
- **[ai-services](specs/ai-services/spec.md)** - AI and LLM services
- **[security-services](specs/security-services/spec.md)** - Security and privacy
- **[financial-services](specs/financial-services/spec.md)** - Finance management
- **[gaming-services](specs/gaming-services/spec.md)** - Gaming and emulation
- **[cloud-integration](specs/cloud-integration/spec.md)** - Cloud and VPN
- **[monitoring-operations](specs/monitoring-operations/spec.md)** - Monitoring and ops
- **[backup-infrastructure](specs/backup-infrastructure/spec.md)** - Backup architecture
- **[dropbox-download-guide](specs/dropbox-download-guide/spec.md)** - Downloading backups from Dropbox

## Maintenance

### Updating Specifications

When the infrastructure changes:

1. Make the change via the OpenSpec workflow (create change → implement → archive)
2. Update the baseline specs to reflect the new state
3. Update related specs in `openspec/specs/`
4. Commit changes to Git

### Review Schedule

- **Monthly:** Review specs for accuracy
- **Quarterly:** Comprehensive spec audit
- **After major changes:** Update all affected specs

## Contributing

When contributing to the homelab:

1. **Check existing specs** to understand current behavior
2. **Create a change** for your work (don't modify baseline specs directly)
3. **Follow the spec-driven workflow** (proposal → design → tasks → implement)
4. **Update documentation** as part of your change
5. **Archive when complete** to update baseline specs

## Questions?

- See the [onboarding guide](specs/onboarding-guide/spec.md) for general homelab questions
- See the [troubleshooting guide](specs/troubleshooting/spec.md) for issues
- Check service-specific specs in `openspec/specs/` for detailed information

---

**Last Updated:** 2026-02-06  
**Specification Version:** 1.0 (Baseline)  
**Schema:** spec-driven  
**Status:** Active

This baseline represents the homelab infrastructure as documented on February 6, 2026.
