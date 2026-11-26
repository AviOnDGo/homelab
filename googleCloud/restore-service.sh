#!/usr/bin/env bash
set +x
set -euo pipefail

: "${SERVICE:?Missing service}"
: "${FORCE:?Missing force setting}"
: "${VM_NAME:?Missing VM name}"
: "${PROJECT_ID:?Missing project ID}"
: "${ZONE:?Missing zone}"
: "${DROPBOX_AUTH_TOKEN:?Missing DROPBOX_AUTH_TOKEN secret}"
: "${DROPBOX_REFRESH_TOKEN:?Missing DROPBOX_REFRESH_TOKEN secret}"
: "${GPG_PASSPHRASE:?Missing GPG_PASSPHRASE secret}"

case "$SERVICE" in
  npm) service_dir=securityServices/npm ;;
  freshrss) service_dir=knowledgeServices/freshrss ;;
  *) echo "Unsupported restore service: $SERVICE" >&2; exit 1 ;;
esac
case "$FORCE" in
  false) mode=--if-missing ;;
  true) mode=--force ;;
  *) echo "Force must be true or false." >&2; exit 1 ;;
esac
if [[ "$GPG_PASSPHRASE" == *$'\n'* ]]; then
  echo "GPG_PASSPHRASE must be a single line." >&2
  exit 1
fi

{
  printf '%s' "$DROPBOX_AUTH_TOKEN" | base64 -w0; echo
  printf '%s' "$DROPBOX_REFRESH_TOKEN" | base64 -w0; echo
  printf '%s' "$GPG_PASSPHRASE" | base64 -w0; echo
  tar -C "$service_dir" -cf - restore.sh docker-compose.yml
} | gcloud compute ssh --quiet "$VM_NAME" \
  --project "$PROJECT_ID" --zone "$ZONE" \
  --command 'sudo bash -c '"'"'
    set +x
    set -euo pipefail
    umask 077
    read -r token64
    read -r refresh64
    read -r pass64
    workdir=$(mktemp -d /tmp/service-restore-workflow.XXXXXXXX)
    trap "rm -rf -- \"\$workdir\"" EXIT
    tar -xf - -C "$workdir"
    if ! command -v rclone >/dev/null || ! command -v zstd >/dev/null; then
      apt-get update
      apt-get install -y --no-install-recommends rclone zstd
    fi
    export token="$(printf %s "$token64" | base64 -d)"
    export refresh="$(printf %s "$refresh64" | base64 -d)"
    export PASSPHRASE="$(printf %s "$pass64" | base64 -d)"
    unset token64 refresh64 pass64
    export RCLONE_CONFIG="$workdir/rclone.conf"
    export RCLONE_CONFIG_DROPBOX_TYPE=dropbox
    export RCLONE_CONFIG_DROPBOX_TOKEN="$(jq -cn \
      "{access_token:env.token,token_type:\"bearer\",refresh_token:env.refresh,expiry:\"1970-01-01T00:00:00Z\"}")"
    unset token refresh
    export COMPOSE_PROJECT_NAME="$2"
    bash "$workdir/restore.sh" "$1"
  '"'"' _ '"$mode"' '"$SERVICE"
