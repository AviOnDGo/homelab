#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

branch="$(git -C "$repo_root" branch --show-current)"
if ! remote="$(git -C "$repo_root" config --get "branch.$branch.remote")"; then
  remote=origin
fi

if git -C "$repo_root" rev-parse --verify --quiet '@{u}' >/dev/null; then
  commit_range="@{u}..HEAD"
else
  remote_branch="refs/remotes/$remote/$branch"
  if git -C "$repo_root" rev-parse --verify --quiet "$remote_branch" >/dev/null; then
    commit_range="$remote_branch..HEAD"
  else
    remote_head="refs/remotes/$remote/HEAD"
    if git -C "$repo_root" rev-parse --verify --quiet "$remote_head" >/dev/null; then
      commit_range="$remote_head..HEAD"
    else
      commit_range="HEAD"
    fi
  fi
fi

# Merging another remote branch does not introduce its existing commits to the remote.
git -C "$repo_root" rev-list "$commit_range" --not "--remotes=$remote" |
  while IFS= read -r commit; do
    git -C "$repo_root" show --format= --no-ext-diff --unified=0 \
      --diff-merges=combined "$commit" -- .
  done |
  python3 "$script_dir/scan-secrets-diff.py" "$repo_root/.secretscan-allowlist"

echo "Secret scan passed for push range ($commit_range)."
