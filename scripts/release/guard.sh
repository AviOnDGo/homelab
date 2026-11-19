#!/usr/bin/env bash
set -euo pipefail

fail() {
  printf '::error::%s\n' "$*" >&2
  exit 1
}

baseline_tag=v1.0.0
head=$(git rev-parse HEAD)
[[ ${GITHUB_REF:-} == refs/heads/main && $head == "${GITHUB_SHA:-}" ]] ||
  fail 'Release checks require the exact event commit on main.'

check_tip() {
  local remote_main
  remote_main=$(git ls-remote --exit-code origin refs/heads/main) ||
    fail 'Could not read the remote main branch tip.'
  [[ "${remote_main%%$'\t'*}" == "$head" ]]
}

case "${1:-preflight}" in
  preflight)
    if ! check_tip; then
      echo 'Release run superseded by a newer main commit; use the latest run.'
      echo 'current=false' >> "${GITHUB_OUTPUT:?}"
      exit 0
    fi
    ;;
  verify-tags) ;;
  *) fail 'Unknown release guard mode.' ;;
esac

git fetch --prune --prune-tags --tags origin
[[ ${RELEASE_BASELINE_SHA:-} =~ ^[0-9a-f]{40}$ ]] ||
  fail 'Set RELEASE_BASELINE_SHA to the reviewed v1.0.0 commit before activation.'
[[ $(git cat-file -t "refs/tags/$baseline_tag" 2>/dev/null) == tag ]] ||
  fail 'Missing annotated v1.0.0 tag. Follow the README bootstrap instructions.'
[[ $(git rev-parse "refs/tags/$baseline_tag^{commit}") == "$RELEASE_BASELINE_SHA" ]] &&
  git merge-base --is-ancestor "$RELEASE_BASELINE_SHA" "$head" ||
  fail 'v1.0.0 must match RELEASE_BASELINE_SHA and be an ancestor of the event commit.'

published=$(gh api --paginate "repos/${GITHUB_REPOSITORY:?}/releases?per_page=100" \
  --jq '.[] | select(.draft == false and .prerelease == false) | .tag_name')
tags=$(git tag --merged "$head")
while IFS= read -r tag; do
  [[ $tag =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || continue
  grep -Fxq -- "$tag" <<< "$published" ||
    fail "Tag $tag exists without a published stable GitHub Release. Publish the release for that same tag before retrying; do not move or delete the tag."
done <<< "$tags"

if [[ ${1:-preflight} == preflight ]]; then
  echo 'current=true' >> "${GITHUB_OUTPUT:?}"
fi
