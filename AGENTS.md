# AGENTS.md – Repository Development Guide

**Purpose**: This document provides the conventions and helper commands that any code‑generation or agentic tooling (e.g. OpenAI agents, Cursor, GitHub Copilot, OpenCode) should follow when working in the **homelab** repository. It centralises build, lint, test and style guidance so that agents can act consistently and without needing to infer policies from scattered files.

**Project Overview**: Personal homelab infrastructure providing media, knowledge, AI, security, financial, gaming, and backup services orchestrated via Docker containers with Nginx Proxy Manager as the central gateway.

---

## 1️⃣  Build / Deploy Commands

| Goal | Command | Description |
|------|---------|-------------|
| **Start all services locally** | `docker compose up -d` | Brings up every service defined in the top‑level `docker-compose.yml` files (including sub‑folders via `extends`). |
| **Re‑create services** | `docker compose up -d --build --force-recreate` | Re‑builds any Dockerfiles and starts fresh containers. |
| **Stop everything** | `docker compose down` | Stops containers, removes networks and anon volumes. |
| **Deploy via CI** | `gh workflow run deployment.yml` | Triggers the GitHub Actions workflow defined in `.github/workflows/deployment.yml`. |
| **Run a single service** | `docker compose up -d <service‑name>` | Useful for isolated debugging (e.g. `docker compose up -d pihole`). |
| **Inspect logs** | `docker compose logs -f <service‑name>` | Follow live logs of a specific container. |

> **Agent tip** – When a change only touches a single service, prefer the *single‑service* commands to keep CI fast.

---

## 2️⃣  Lint / Formatting Commands

The repository uses **standard, language‑agnostic tools** that are pre‑installed in the development container.  Agents should run the following before committing any change.

### Python
```bash
# Install tools (run once per dev environment)
python -m pip install --quiet black isort flake8 pylint mypy
```

| Check | Command | What it does |
|-------|---------|--------------|
| **Formatting** | `black .` | Applies Black (line length 88) to all Python files. |
| **Import ordering** | `isort .` | Groups imports according to the Black profile. |
| **Static analysis** | `flake8 .` | Enforces PEP‑8 style, unused imports, line length < 88, etc. |
| **Lint with type hints** | `pylint --disable=R,C .` | Highlights possible bugs while ignoring style‑only messages (handled by Black/Flake8). |
| **Type checking** | `mypy .` | Checks for type‑hint consistency. |

### JavaScript / TypeScript
```bash
npm install --silent eslint prettier
```
| Check | Command | What it does |
|-------|---------|--------------|
| **Formatting** | `npx prettier --write "**/*.{js,ts,tsx,json,md}"` | Auto‑formats using Prettier (2‑space indent, LF line endings). |
| **Lint** | `npx eslint "**/*.{js,ts,tsx}" --fix` | Runs ESLint with the repo’s config (if any) and auto‑fixes where possible. |

> **Agent tip** – Run the language‑specific formatter first, then the linter. This avoids false‑positive lint errors caused by formatting issues.

---

## 3️⃣  Testing Commands

The repository does **not** ship a formal test suite yet, but agents are encouraged to add **pytest** based tests for any new Python logic and **Jest** tests for JavaScript.  The following commands assume the appropriate test runner is installed.

### Install test dependencies (once)
```bash
# Python
python -m pip install --quiet pytest pytest-cov
# JavaScript (if package.json exists in a sub‑folder)
npm install --silent jest
```

### Run the full test suite
```bash
# Python
pytest
# JavaScript (if Jest config present)
npx jest
```

### Run a **single** test (highly useful for agents)
```bash
# Python – <path> is relative to the repo root, <test_name> is the function name
pytest path/to/test_file.py::test_name

# JavaScript – Jest pattern
npx jest path/to/test_file.test.js -t "test name"
```

> **Agent tip** – When fixing a bug, modify only the failing test and run the single‑test command to verify your fix instantly.

---

## 4️⃣  Code‑Style Guidelines

### 4.1 Python
* **File encoding** – UTF‑8, no BOM.
* **Naming** – `snake_case` for functions/variables, `PascalCase` for classes, `UPPER_SNAKE_CASE` for constants.
* **Docstrings** – Google style, placed immediately after the definition.
* **Type hints** – All public functions should have type annotations. Use `typing` primitives (`List`, `Dict`, `Optional`, `Union`).
* **Imports** – Sorted alphabetically, grouped as `stdlib`, `third‑party`, `local`. One import per line unless using parentheses for multiple names.
* **Error handling** – Prefer specific exception types, log errors with the standard library `logging` module, and re‑raise only when necessary.
* **No dead code** – Remove unused imports/variables; `flake8` will flag them.
* **Circular imports** – Avoid; refactor into a shared module when needed.
* **One function per file** – Not mandatory, but keep files small (≤ 300 LOC) for readability.

### 4.2 JavaScript / TypeScript
* **File extension** – `.js` for plain JavaScript, `.ts` / `.tsx` for TypeScript/React.
* **Naming** – `camelCase` for variables/functions, `PascalCase` for classes/components, `UPPER_SNAKE_CASE` for constants.
* **Imports** – Use ES‑module syntax (`import … from …`). Order: `builtin`, `external`, `internal` – each group separated by a blank line.
* **Semicolons** – Enforced via ESLint (`semi: ['error', 'always']`).
* **Async/Await** – Prefer over callbacks; always `try/catch` async code.
* **PropTypes / TypeScript** – Provide full typings for public APIs.
* **Error handling** – Throw `Error` subclasses, include contextual information.
* **Prettier settings** – 2‑space indent, trailing commas where valid, single quotes.

### 4.3 General Guidelines
* **Commit granularity** – One logical concern per commit; never lump unrelated files into a single commit. Group files by concern (security fix, spec rewrite, docs, structural change) and create one commit per group. See the **Commit Grouping Strategy** in the Agent Git Behavior section for the full decision rules. Keep commit messages concise (max 72 char subject, blank line, body if needed).
* **Line length** – 88 characters for Python, 100 characters for JS/TS (Prettier respects this with `printWidth`).
* **Trailing whitespace** – Never commit trailing spaces or tabs.
* **File headers** – No license headers required; repository root contains the global LICENSE.
* **Shell scripts** – Use `#!/usr/bin/env bash`, `set -euo pipefail`, and shellcheck (`shellcheck <file>`).
* **Dockerfiles** – Pin base image versions, use multi‑stage builds when possible, and keep layers minimal.

---

## 5️⃣  Pull Request Standards

All Pull Requests (PRs) created by agents or developers **must follow a structured, detailed format** to ensure reviewers understand the scope, rationale, and impact of changes.

### PR Description Template

Every PR MUST include:

1. **Problem Statement** — Why is this change needed? What problem or limitation does it address?
2. **Solution** — How does this PR solve the problem? What is the approach?
3. **Files Changed** — Organized into "New Files" and "Modified Files" with brief descriptions
4. **Technical Details** — Explanation of key implementation decisions, trade-offs, and rationale
5. **Security Considerations** (if applicable) — Any security implications or measures
6. **Impact** — User-facing and developer-facing effects
7. **Testing Recommendations** — Specific tests reviewers should perform
8. **Related Changes** — Links to OpenSpec changes, issues, or companion PRs
9. **Reviewer Checklist** — Specific points for code reviewers to validate

### Template Location

See `.github/pull_request_template.md` for the standard template. When creating a PR:

```bash
# Template is auto-populated by GitHub for web-based PRs
# For CLI (gh), you can reference the template:
gh pr create --title "..." --body-file .github/pull_request_template.md
# Then manually fill in the sections with specific details
```

### OpenSpec Integration

For PRs that implement OpenSpec changes:
- Include a "Related Changes" section linking to the OpenSpec change name, branch, and key artifacts (proposal, design, specs, tasks)
- Reference which spec and design requirements are being implemented
- Link approval checklist items to the change's tasks

### Example: Detailed PR Structure

```
# Short Title Describing the Change

## Problem Statement
[1-2 sentences explaining why this is needed]

## Solution  
[2-3 sentences explaining the approach]

## Files Changed

### New Files
- file/path — Brief description
- file/path — Brief description

### Modified Files
- file/path — What changed and why

## Technical Details
[Explanation of decisions and trade-offs]

## Impact
[How users/operations are affected]

## Testing Recommendations
- [ ] Test 1
- [ ] Test 2

## Related Changes
- OpenSpec change: add-feature-xyz
- Proposal: openspec/changes/add-feature-xyz/proposal.md
- Design: openspec/changes/add-feature-xyz/design.md
```

### Agent Responsibilities

When agents create or update PRs:
- Always populate ALL sections of the template
- Ensure technical decisions are explained (not just "what" but "why")
- Include security considerations when applicable
- Provide testable, specific recommendations
- Link to related OpenSpec changes or documentation
- Verify links are correct before opening the PR

---

## 6️⃣  Cursor / Copilot Rules (if present)

The repository currently **does not contain** a `.cursor` directory or a `.github/copilot‑instructions.md` file.  If those files are added in the future, agents should:
1. Parse the rules and respect any `#cursor‑disable` or `#copilot‑skip` pragmas.
2. Honor any custom file‑type handling (e.g., `*.tf` specific suggestions).
3. Use `cursor‑suggest` only when the rule explicitly enables it for the current file type.

---

## 6️⃣  CI / Pre‑Commit Hooks (Future)**

*Add the following hooks to the repository when the project matures:* 
```yaml
# .pre-commit-config.yaml (example)
repos:
  - repo: https://github.com/psf/black
    rev: 23.9.1
    hooks:
      - id: black
  - repo: https://github.com/PyCQA/flake8
    rev: 6.1.0
    hooks:
      - id: flake8
  - repo: https://github.com/prettier/prettier
    rev: v3.0.0
    hooks:
      - id: prettier
```
Agents should **never** bypass hooks unless explicitly instructed.

---

## 7️⃣  Quick Reference Cheat‑Sheet (for agents)
```
# Build / Deploy
docker compose up -d
docker compose down

# Lint / Format
black . && isort .
flake8 .
mypy .
prettier --write "**/*.{js,ts,tsx,json,md}" && eslint "**/*.{js,ts,tsx}" --fix

# Tests
pytest                     # all Python tests
pytest path/to/file.py::test_name   # single test
npx jest                    # all JS tests
npx jest path/to/file.test.js -t "test name"   # single test

# Git commit
git add .
git commit -m "feat: add xyz"
```

---

## 8️⃣  Architecture & Service Organization

### Service Categories
Services are organized by function in top-level directories (mediaServices/, securityServices/, etc.). Each category contains:
- `docker-compose.yml` – service definitions for that category
- `.env` – environment variables (never committed; in `.gitignore`)
- Service-specific subdirectories with configs, scripts, and documentation

### Network Architecture
- **External networks per category**: Each category has a named network (e.g., `media_network`, `finance_network`) created once and referenced via `external: true` in compose files
- **NPM gateway**: Nginx Proxy Manager acts as the central reverse proxy; most service ports are commented out (not exposed directly)
- **Network joining**: Services explicitly declare `networks: [<category>_network]`; backup services join multiple networks to access database volumes

### Two-Tier Backup System

**Database backups** (`backupServices/postgres/`):
- PostgreSQL container runs scheduled `pg_dump` jobs via cron
 - Handles invidious, firefly databases with standard naming: `backup_{database}_{timestamp}.sql.zst.gpg` (zstd-compressed SQL dumps, GPG encrypted)
- Uses GPG AES256 encryption + rclone for multi-cloud upload (Dropbox, Google Drive, OneDrive)
- Sourcing: reads from Docker volumes (`invidious_postgresdata`, `firefly_postgresdata`, etc.)

**Filedata/volume backups** (`backupServices/filedata/`):
- Backs up Docker named volumes (pihole, npm, vaultwarden, etc.)
- Same encryption + rclone pattern; retention configurable per service via .env
- Paths standardized: all Dropbox backup paths use `/Apps/{service}` directory

---

## 9️⃣  Project Conventions

### Release Classification

PRs targeting `main` use `type(scope)!: description` (scope and `!` are
optional). `feat` produces a minor release; `fix`, `perf`, and `revert` produce
a patch. Non-breaking `docs`, `style`, `refactor`, `test`, `build`, `ci`, and
`chore` do not release. A valid breaking footer or a `!` produces a major
release, even for documentation or maintenance.

For example, `fix(ollama): restore boot startup` is a patch; `docs!: change the
restore procedure` is major. For a breaking PR, include `!` in the title and
write operator migration steps in a `BREAKING CHANGE:` footer in the PR body.
The `Validate PR title` check is required on pull requests targeting `main`.
Verify the final squash subject and preserve the migration footer before merging. Follow
[the release runbook](./README.md#activate-or-recover-releases) for required
GitHub settings, baseline approval, preview, retries, and disabling publication
without changing deployed services or moving tags.

### Docker Compose Patterns
All `docker-compose.yml` files use **v3.8** and follow:
```yaml
services:
  <service>:
    image: <registry>/<name:tag>
    container_name: <service>       # matches service name for DNS
    restart: unless-stopped          # universal policy
    networks:
      - <category>_network
    volumes:
      - <service>_filedata:/data    # external persistence
    ports:
      - <host>:<container>          # increasingly commented (use NPM)

networks:
  <category>_network:
    external: true
    name: <category>_network

volumes:
  <service>_filedata:
    external: true
    name: <service>_filedata
```

> **Network block standard** — Every `docker-compose.yml` MUST include a top-level `networks:` block declaring all referenced networks as `external: true`. Never rely on implicit network creation; the block makes network membership auditable at a glance.

### Volume Naming Convention
Named external Docker volumes use the pattern **`<service_name>_filedata`** (e.g., `freshrss_filedata`, `vaultwarden_filedata`). Services with multiple distinct volumes append a purpose suffix instead: `<service>_<purpose>` (e.g., `immich_library`, `immich_profile`). Never use generic names like `data` or `config` without a service prefix.

### Environment & Secrets
- `PUID: 1000`, `PGID: 1000` standard for linuxserver.io images
- `TZ: UTC` is the generic timezone default — inline it directly in `docker-compose.yml` under `environment:`, do NOT put it in `.env`
- Keep secret values out of tracked files; mount required credentials via `/run/secrets/<file>` from files provisioned outside version control
- **`.env` file policy** — Only create a `.env` file (and `env_file: .env` reference) when:
  - The service has multiple secret/user-specific variables, OR
  - A variable is referenced in several places within `docker-compose.yml`
  - If a service needs only one or two non-secret, rarely-changing values (e.g., a single cron schedule), inline them directly in the `environment:` block instead. This avoids `.env` file sprawl and makes the compose file self-documenting.

### Terraform Lockfile Policy
- Terraform lockfiles (`.terraform.lock.hcl`) SHALL NOT be committed to this repository.
- `.terraform.lock.hcl` files are local execution artifacts and MUST be ignored by git in all directories.
- If a lockfile is already tracked, remove it from index with `git rm --cached <path>` and keep it ignored going forward.

### Cron Jobs in Docker
Embed cron jobs in `docker-compose.yml` command sections:
```yaml
command: >
  sh -c "echo '0 3 * * * /usr/local/bin/backup.sh' >> /etc/crontabs/root && crond -f"
```
This pattern runs scheduled tasks within the container without external cron daemons.

### Backup Compose Ordering (Mandatory)
For `backupServices/postgres/`, maintain the layout in
`docker-compose.yml`, `docker-compose.local.yml`, and `docker-compose.remote.yml`.
For `backupServices/filedata/`, keep one canonical `docker-compose.yml` and use
`backup-volumes.conf` plus `start-backup.sh` to generate host-specific mounts,
volume declarations, and cron jobs:
- Group source-volume mounts, top-level volume declarations, and cron jobs alphabetically by
  service category, then alphabetically by service name within each category. Sort multiple
  volumes for the same service by their purpose suffix. Apply the same order to disabled entries.
- Use category labels matching the service directories: AI Services, Container Services,
  Financial Services, Gaming Services, Knowledge Services, Media Services, Security Services,
  and Stream Services, as applicable. Insert any new category alphabetically.
- Add `## <Category> Services` comments to Compose volume sections and emit matching
  `# <Category> Services` comments into the generated crontab for enabled jobs.
- Initialize `/etc/crontabs/root` with a header using `>` before appending category comments
  and jobs with `>>`: `# Crontab for database backups` or `# Crontab for filedata backups`.
- Sort service network references and top-level network declarations alphabetically by network
  name, keeping disabled network entries in the same order. Preserve each profile's networking.
- Keep shared secrets and script mounts after the grouped source volumes; keep `gpg-secrets`
  after the grouped top-level source-volume declarations.
- When adding a stateful service, register its backup name, volume name, host profiles, mode,
  retention, and schedule in
  `backupServices/filedata/backup-volumes.conf`. The `default` profile SHALL be included;
  include `local` or `prod` when deployed there. The generator includes only existing volumes.
  Update `path.local` and `path.prod` with destination settings, the credentials-only
  `.env.example` if needed, backup scripts, specs, and operator documentation together.
  Do not enable a service in a profile where it is not deployed.
- Filedata backup modes, retention, and schedules come from `backup-volumes.conf` and are passed
  to the container by the generated Compose override. Specify `sync-crypt` for every volume
  that requires it, including Immich and Paperless; do not configure these policies in the
  environment examples.
- Filedata destination settings come from `path.local` or `path.prod`, which override legacy
  destination values in `.env`. The `local` and `prod` host profiles select their matching
  destination file; `default` requires an explicit `local` or `prod` destination argument.

### Host and Service Setup Scripts

Keep local host provisioning under [`scripts/host/`](scripts/host/) and
service setup and restore scripts beside their services. Invoke host scripts
directly as executable Bash scripts, not with `sh`. Keep disruptive actions such
as rebooting, disabling Wi-Fi, Tailscale enrollment, and Docker restarts separate
from bootstrap. See the [host provisioning guide](README.md#1-provision-the-machine).

Service `setup.sh` scripts:
1. Detect container runtime: `docker` (preferred) → `podman-compose` fallback
2. Create data directories: `mkdir -p`
3. Run optional restore scripts if available
4. Execute `docker compose up -d` (or `podman-compose`)
5. Display service URLs and data locations

### Documentation Standardization
Services include:
- **SERVICE_DOCUMENTATION.md**: Technical reference (start, stop, logs, troubleshooting)
- **RESTORE_GUIDE.md**: Step-by-step recovery procedures
- **restore.sh**: Script-first recovery entrypoint for operators
- **QUICKSTART_GUIDE.md**: Cron schedules, retention periods, common commands

### Restore Script Standard (Mandatory)
Every service directory SHALL include an executable `restore.sh` script.

Rules:
- `restore.sh` SHALL be script-first, meaning normal recovery can be started with `./restore.sh`.
- `restore.sh` SHALL use `#!/usr/bin/env bash` and `set -euo pipefail`.
- `RESTORE_GUIDE.md` SHALL document `restore.sh` as the primary path and keep manual fallback steps.
- For stateless services, `restore.sh` MAY be a no-op helper that explains no persistent state is restored.

### RESTORE_GUIDE Structure Standard (Mandatory)
All service-level `RESTORE_GUIDE.md` files SHALL follow a consistent restore sequence so operators can execute recovery without re-learning each service.

Required section order for every restore guide:
1. **Prerequisites**
2. **Restore Steps** (single numbered flow, no split parts unless technically required)
3. **Verification**
4. **Troubleshooting**
5. **Optional sections**: One-Time Migration, Rollback, Dropbox Download

Flow selection (pick exactly one):
- **filedata + PostgreSQL**
- **filedata-only**
- **PostgreSQL-only**

Common baseline steps (all flows):
1. Navigate to service directory and stop stack (`docker compose down`)
2. Set `PASSPHRASE`
3. Run architecture-specific restore actions (from the selected flow below)
4. Start all services (`docker compose up -d`)
5. Cleanup sensitive shell state (`unset PASSPHRASE`)

Architecture-specific restore actions:

For **filedata + PostgreSQL**:
1. Ensure required external volume(s) exist (`docker volume inspect ... || docker volume create ...`)
2. Restore filedata archive into target volume(s) (prefer direct decrypt + pipe extraction)
3. Create containers without starting (`docker compose create`)
4. Start only database container (`docker start <db-container>`)
5. Restore SQL backup (`gpg ... | docker exec -i <db-container> psql ...`)

For **filedata-only**:
1. Ensure required external volume(s) exist (`docker volume inspect ... || docker volume create ...`)
2. Restore filedata archive into target volume(s) (prefer direct decrypt + pipe extraction)

For **PostgreSQL-only**:
1. Create containers without starting (`docker compose create`)
2. Start only database container (`docker start <db-container>`)
3. Restore SQL backup (`gpg ... | docker exec -i <db-container> psql ...`)

Authoring rules:
- Use explicit step numbers (`### 1.`, `### 2.`, etc.)
- Use actual container and volume names from the service compose file
- Keep command examples copy-paste ready with placeholders only for secrets and backup paths
- Keep verification commands concrete (`docker compose ps`, key DB record checks, service log checks)
- Choose and document exactly one flow based on service architecture: filedata + PostgreSQL, filedata-only, or PostgreSQL-only

---

## 🔟  Integration Points

### Backup Automation
- **Backup services join multiple networks** to access both database and filedata volumes across categories
- **Discord webhooks** notify on backup success/failure (secret mounted at `/run/secrets/discord_webhook`)
- **Retention enforcement**: `find ... -mtime +{days} -delete` within backup scripts

### Service Discovery & Networking
- Container names match service names (DNS resolution within networks)
- NPM routes external traffic to internal services by container name
- Network isolation prevents unauthorized cross-category communication

### Multi-Cloud Strategy
- Dropbox primary cloud target; Invidious/Firefly use `/Apps/invidious`, `/Apps/firefly` paths
- Rclone remotes configurable via environment (Google Drive/OneDrive as fallbacks)
- Filedata retention days per service are in `backupServices/filedata/backup-volumes.conf`;
  database retention is configured through environment variables.

---

## 1️⃣1️⃣  Key Directories for Agents

| Path | Purpose |
|------|---------|
| `docker-compose.yml` (root) | Orchestrates all service categories via `extends` |
| `mediaServices/`, `securityServices/`, etc. | Service category groups with compose files and .env |
| `backupServices/postgres/`, `backupServices/filedata/` | Database and volume backup automation |
| `openspec/specs/` | Authoritative service and infrastructure specifications (replaces the removed `docs/` directory) |
| `openspec/` | OpenSpec experimental workflow for tracked changes/refactoring |
| `<category>/<service>/` | Service-specific configs, scripts, and documentation |

---

## 1️⃣2️⃣  Common Agent Operations

### Working with a Single Service
```bash
# Restart a single service (after editing its config)
docker compose -f mediaServices/docker-compose.yml up -d jellyfin

# View logs for debugging
docker compose -f mediaServices/docker-compose.yml logs -f jellyfin
```

### Running Backups Manually
```bash
# Trigger database backup for invidious
docker exec db-backup /usr/local/bin/backup-script.sh invidious

# Trigger filedata backup
docker exec filedata-backup /backup-script.sh pihole
```

### Restoring from Backup
1. Consult service-specific `RESTORE_GUIDE.md` in the service directory
2. Stop affected services: `docker compose down`
3. Run the restore script(s) provided in the guide
4. Restart services: `docker compose up -d`

---

## 🔒  Agent Git Behavior (Mandatory)

These rules apply to **all agents** regardless of which AI tool is in use (GitHub Copilot, Claude, OpenCode, Cursor, or any other). They are the single source of truth — tool-specific files (`.github/copilot-instructions.md`, `CLAUDE.md`, `OPENCODE.md`) redirect here.

> ⚠️ **CRITICAL: NEVER commit unless the operator explicitly says "commit" in the current message.** A prior "commit" command does NOT carry forward — each commit requires a fresh explicit instruction. After implementing changes, always leave files unstaged and inform the operator. The single exception is amending the most recent commit if the operator says "amend" — all other commits require a new "commit" command.

### Git Safety Rules

| Action | Rule |
|--------|------|
| `git commit` | **Never** run without the operator explicitly saying "commit" in the current message |
| `git push` | **Never** run without the operator explicitly saying "push" in the current message |
| `gh pr create` / open PR | **Never** run without the operator explicitly saying "create PR" or "open a pull request" |

When you finish implementing changes, leave files in the working tree and inform the operator that changes are ready to commit when they choose.

### Commit Grouping Strategy (Mandatory)

Whenever the operator explicitly asks to "commit", assess all worktree changes and group
them by logical concern before staging. Create one commit per logical group. If and only
if every changed file belongs to the same logical group, commit the complete change set
in one commit; otherwise, do not combine unrelated groups into one monolithic commit.

The operator's "commit" instruction applies to the current worktree, but files from
unrelated work MUST NOT be swept into a commit merely because they are also modified.

**Grouping rules (apply in order):**

1. **Security fixes** — compose files where hardcoded secrets were removed + their new `.env.example` files → one commit per service category (e.g., all `mediaServices/` security changes together)
2. **Spec rewrites / OpenSpec artifacts** — `openspec/specs/<category>/spec.md` rewrites and deleted standalone specs → one commit per category spec
3. **Structural / config changes** — Dockerfile, compose structural changes (network additions, volume renames, image pinning) that are not security-driven → one commit per service category
4. **Documentation** — `SERVICE_DOCUMENTATION.md`, `RESTORE_GUIDE.md`, `QUICKSTART_GUIDE.md`, etc. → group all docs changes for a category together
5. **Repository-wide changes** — `AGENTS.md`, `README.md`, root-level scripts, `.github/` files → one commit per file or closely related file set

**Decision heuristic — when unsure how to group:**
- Ask: "Would a reviewer expect these files to change together for the same reason?" If yes → same commit. If no → separate commits.
- Security credential removal and its `.env.example` always travel together.
- Spec absorptions (deleting a standalone spec + updating the parent spec) travel together.
- A single OpenSpec change's artifacts (proposal, design, spec, tasks) may be committed together if they were all written in one pass.

**Commit message format per group:**
```
<type>(<scope>): <subject>

<body explaining what changed and why>
```
Common type/scope examples:
- `fix(security)` — credential externalization
- `spec(<category>)` — spec rewrite / consolidation
- `chore(docs)` — documentation updates
- `chore(repo)` — AGENTS.md, README, root scripts

### Pre-Commit Secret Scan Gate

Before executing **any** `git commit`, scan all staged files for potential secrets. If matches are found, **abort the commit** and report findings.

```bash
# Run this before every commit
git diff --cached -- . ':(exclude)*.example' | grep -En \
  "(password|passwd|secret|token|api_key|apikey|access_key|private_key|auth_token)\s*[=:]\s*['\"]?[A-Za-z0-9/+_\-]{8,}"
```

- **No matches** → proceed with commit
- **Matches found** → abort, report the file(s) and line(s), wait for operator to confirm it's a false positive before continuing

### Pre-Push Secret Scan Gate

Before executing **any** `git push`, scan the outgoing commits with the repository's
pre-push scanner. It scans example files too, while allowing explicit placeholders.
If matches are found or the scan fails, **abort the push** and report findings.

```bash
bash .secret-scanning/scripts/scan-secrets-range.sh
```

- **Scan passes** → proceed with push
- **Matches found** → abort, report the file and line, and recommend removing the
  literal from the affected commits before pushing
- **Scan errors** → abort and resolve the error before pushing

---

## 📐  Spec Format Standard

All spec files in `openspec/specs/` SHALL follow this format. Apply it when creating new specs or when standardizing specs for any service category.

### Template

```markdown
## Requirements

### REQ-NNN: <Requirement Name>
<Normative statement using SHALL or SHALL NOT.>

#### Scenario: <Descriptive scenario name>
- **GIVEN** <precondition or context>
- **WHEN** <triggering action or event>
- **THEN** <primary expected outcome>
- **AND** <additional assertions>
```

### Rules

| Rule | Description |
|------|-------------|
| **Stable identifier** | Every requirement has an ID in the form `REQ-001`, `REQ-002`, etc., scoped within the spec file. IDs are never reused. |
| **Normative language** | Use `SHALL` and `SHALL NOT` only. Never use "should", "must", "may", or similar. |
| **GIVEN is mandatory** | Every scenario must have a `GIVEN` line establishing preconditions. Never skip it. |
| **No changelog headers** | Spec files are timeless statements of behavior. Never use `## ADDED Requirements`, `## MODIFIED Requirements`, or similar changelog headers. Requirements appear as a flat list under `## Requirements`. |

> **Agent tip** — When standardizing specs for a service category, always read the actual `docker-compose.yml` and service files first to ground scenarios in reality. Each scenario should be independently verifiable.

---

*This document is intentionally exhaustive to give agents a single source of truth. Keep it up‑to‑date as tooling and patterns evolve.*

---

## 🔐  Agent File Access Restrictions (Mandatory)

### `.env` Files — NEVER Read or Display

**Agents MUST NEVER read, open, display, or pass the contents of any `.env` file to a tool or model under any circumstances.** These files contain live credentials, API keys, and secrets.

**Prohibited files (pattern):**
- `.env`
- `.env.*` (e.g., `.env.prod`, `.env.acc`, `.env.local`, `.env.staging`)

**Permitted files (safe to read):**
- `.env.example`
- `.env.acc.example`
- `.env.prd.example`
- `.env.local.example`
- `.env.prod.example`
- Any file matching `*.example` — these contain only placeholders, no real credentials

**Enforcement rules:**

| Action | Rule |
|--------|------|
| Tool call targeting `.env` or `.env.*` | **Abort immediately.** Do not proceed. Inform the operator the file is off-limits. |
| Grep / search output that includes `.env` content | **Do not display or process** the matched lines if they originate from a `.env` file. |
| Operator asks to "check what's in .env" | Redirect to the `.env.example` counterpart and explain that live `.env` files cannot be read. |
| `.env` file path appears in shell output | Acknowledge the path only; do not follow it with a read. |

> **Rationale** — `.env` files are excluded from git (`.gitignore`) precisely because they hold secrets. An agent reading one would expose credentials in model context, logs, and potentially chat history.
