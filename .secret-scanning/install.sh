#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(git -C "$script_dir/.." rev-parse --show-toplevel)"
hooks_dir="$repo_root/.secret-scanning/hooks"

if [[ ! -x "$hooks_dir/pre-commit" || ! -x "$hooks_dir/pre-push" ]]; then
  echo "Secret-scanning hook files are missing or not executable." >&2
  exit 1
fi

git -C "$repo_root" config --local core.hooksPath "$hooks_dir"
printf 'Configured Git hooks for %s\n' "$repo_root"
printf 'Hook source: %s\n' "$hooks_dir"
