# FreshRSS — Restore Guide

This guide covers restoring FreshRSS from a GPG-encrypted filedata backup produced by `backupServices/filedata`.

Two restore paths are supported:
- Workflow-driven restore from GitHub Actions (recommended for GCP VM)
- Script-driven restore on the host via `restore.sh` (fallback when workflow is unavailable)

---

## Prerequisites

- Docker installed and running
- `knowledge_network` Docker network exists
- GPG symmetric key (passphrase) used for encryption — stored in Vaultwarden
- `rclone` configured with the Dropbox remote (if downloading from cloud)

For workflow-driven restore, also ensure:
- GitHub Actions `prod` environment contains the required GCP OIDC variables
- GitHub Actions secrets are set: `DROPBOX_AUTH_TOKEN`, `DROPBOX_REFRESH_TOKEN`, `GPG_PASSPHRASE`
- `DISCORD_WEBHOOK_URL` may be set if you want Discord success/failure notifications from the workflow

---

## Workflow-Driven Restore (GCP)

Use GitHub Actions workflow `.github/workflows/gcp-freshrss-restore.yml` for the standard GCP recovery flow.

### Inputs

- `confirm_restore`: must be `RESTORE_FRESHRSS`
- `dropbox_path`: default `/Apps/freshrss`
- `git_ref`: branch or tag synced to `/tmp/homelab` (default `main`)
- `vm_name`: optional override (defaults to `GCP_VM_NAME` variable or `gcp-debian-free-tier-vm`)

### What the workflow does

1. Validates guard inputs and required secrets.
2. Authenticates to GCP via OIDC (no static key files).
3. SSHes into VM and runs ordered restore sequence:
  - refresh `/tmp/homelab` to selected `git_ref`
  - resolve and download the latest compatible backup from Dropbox
  - stop `filedata-backup` if it is running
  - stop FreshRSS if it is running
  - recreate `freshrss_filedata`
  - stream decrypt and extract into `freshrss_filedata`
  - restart and verify FreshRSS
  - restart `filedata-backup` only if it was running before the restore
4. Attempts a Discord notification on success or failure when `DISCORD_WEBHOOK_URL` is configured.

### Concurrency and safety

- Workflow uses GitHub Actions concurrency group to prevent parallel runs.
- VM-side lock (`/tmp/freshrss-restore.lock`) prevents overlapping destructive operations.

---

## Manual Restore (Script-Driven)

Run `restore.sh` from the repository root. The script handles preflight checks, download, decryption, volume recreation, restart, and health verification automatically.

```bash
cd knowledgeServices/freshrss
./restore.sh
```

To use a non-default Dropbox path:

```bash
DROPBOX_PATH=/Apps/freshrss-alt ./restore.sh
```

To supply the passphrase non-interactively:

```bash
PASSPHRASE=<gpg-passphrase> ./restore.sh
```

The script will:
1. Verify `docker`, `rclone`, `gpg`, and `zstd` are available and the Dropbox remote is reachable.
2. Prompt for the GPG passphrase (or read from `PASSPHRASE` env var).
3. Select the latest archive at `dropbox:/Apps/freshrss` (`freshrss_YYYY-MM-DD_HH-MM-SS.tar.zst.gpg`).
4. Download the archive, stop FreshRSS (with confirmation), wipe and recreate `freshrss_filedata` (with confirmation), and stream-extract the decrypted archive into the volume.
5. Restart FreshRSS and poll `php /var/www/FreshRSS/cli/health.php` for up to 300 seconds to confirm a healthy start.
6. Clean up all temporary files automatically on exit.

---

## Rollback / Abort Procedure

If restore fails after `freshrss_filedata` recreation:

1. Keep FreshRSS stopped to avoid writing partial state:
  ```bash
  docker compose -f knowledgeServices/freshrss/docker-compose.yml down
  ```
2. Inspect failure details:
  - GitHub workflow logs (phase and selected backup path)
  - VM diagnostics from workflow output
  - If the restore succeeded but Discord delivery failed, treat that as an observability warning only; do not rerun the restore solely to recover the notification.
3. Re-run workflow with corrected inputs (recommended), or re-run `./restore.sh` with a known-good backup.
4. Start FreshRSS only after restore completes:
  ```bash
  docker compose -f knowledgeServices/freshrss/docker-compose.yml up -d
  ```

---

## Operations Note: When To Use Which Path

- Use workflow-driven restore when:
  - Target is GCP VM
  - You want audited, repeatable execution with guardrails
  - You need deterministic latest-backup selection, backup-service coordination, and automated verification

- Use script-driven restore (`restore.sh`) when:
  - GitHub Actions is unavailable
  - You are restoring in a non-GCP local environment
  - You need a fast, automated local recovery
