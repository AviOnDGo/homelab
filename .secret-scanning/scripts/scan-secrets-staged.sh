#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

git -C "$repo_root" diff --cached --no-ext-diff --unified=0 -- . |
  python3 "$script_dir/scan-secrets-diff.py" "$repo_root/.secretscan-allowlist"

echo "Secret scan passed for staged changes."
