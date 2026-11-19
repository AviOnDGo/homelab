#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

if git -C "$repo_root" rev-parse --verify --quiet '@{u}' >/dev/null; then
  commit_range="@{u}..HEAD"
else
  base_ref="$(git -C "$repo_root" show-ref --verify --quiet refs/heads/main && printf main || printf master)"
  merge_base="$(git -C "$repo_root" merge-base HEAD "$base_ref")"
  commit_range="$merge_base..HEAD"
fi

branch="$(git -C "$repo_root" branch --show-current)"
if ! remote="$(git -C "$repo_root" config --get "branch.$branch.remote")"; then
  remote=origin
fi

# Merging another remote branch does not introduce its existing commits to the remote.
git -C "$repo_root" rev-list "$commit_range" --not "--remotes=$remote" |
  while IFS= read -r commit; do
    git -C "$repo_root" show --format= --no-ext-diff --unified=0 \
      --diff-merges=combined "$commit" -- .
  done |
  python3 "$script_dir/scan-secrets-diff.py" "$repo_root/.secretscan-allowlist"

echo "Secret scan passed for push range ($commit_range)."
