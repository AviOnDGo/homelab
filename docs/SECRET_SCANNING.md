## Secret Scanning Gates

This repository enforces secret scanning at three levels:

1. Pre-commit: scans staged diff (`.secret-scanning/scripts/scan-secrets-staged.sh`)
2. Pre-push: scans commits in push range (`.secret-scanning/scripts/scan-secrets-range.sh`)
3. CI: tests the local gates and runs Gitleaks on `push` and `pull_request`
   (`.github/workflows/secret-scan.yml`)

## Local Hook Setup

Run once per clone from the repository root:

```bash
bash .secret-scanning/install.sh
```

The installer points this clone's local `core.hooksPath` setting at the
repository's `.secret-scanning/hooks` directory. Run it again after cloning or
moving the repository.

The push scanner excludes commits already reachable from remote-tracking branches
for the branch's configured remote (default: `origin`). This prevents an update
from remote `main` from rescanning history already on that remote. Run `git fetch`
before a manual scan to refresh remote-tracking refs. New local commits are still
scanned, including new commits that introduce secret-like values.

## False Positive Handling

If a scan result is confirmed safe:

1. Add a narrowly scoped regex to `.secretscan-allowlist`
2. Include a short rationale in your PR description
3. Prefer changing the source to a clear placeholder instead of expanding allowlist scope

Do not add broad patterns that could hide real secrets.

The local gates share a Python 3.9+ detector and include example files. They
recognize case-insensitive credential fields in JSON/XML as well as shell/YAML
assignments, bearer headers and common token formats. Findings contain only file,
line and field names; values are redacted. Environment references and explicit
placeholders are permitted. Allowlist entries use Python regular expressions;
blank lines and comments do not exempt matches.

Run the focused regression tests with:

```bash
python3 -m unittest discover -s .secret-scanning/tests -v
```

These are heuristic checks, not a complete audit of binary files or private
deployment identifiers. Keep domains, addresses and cloud account details in
private configuration even when a secret scanner does not flag them.

## Env Template Policy

For non-backup services, only `.env.example` is allowed as a tracked env template.
Tracked `.env.backup` files are not allowed.

For backup services, keep the existing dual-template model:

1. Filedata backups: `.env.local.example` and `.env.prod.example`
2. Other backup services: `.env.acc.example` and `.env.prd.example`

Secret-bearing keys in tracked templates must use placeholders or variable references
instead of live credential literals.

## Rollback For Template Normalization

If a template normalization change removes or renames env templates and you need to
restore content while keeping approved naming:

1. Restore prior template content from git history:
	`git show <commit>:<old-path>`
2. Apply restored content into the approved file name:
	non-backup services use `.env.example`; filedata backups use
	`.env.local.example` and `.env.prod.example`; other backup services use
	`.env.acc.example` and `.env.prd.example`.
3. Re-run local secret scan hooks and replace any literal credentials with
	placeholders before committing.
