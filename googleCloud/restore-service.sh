#!/usr/bin/env bash
set +x
set -euo pipefail

: "${SERVICE:?Missing service}"
: "${VM_NAME:?Missing VM name}"
: "${PROJECT_ID:?Missing project ID}"
: "${ZONE:?Missing zone}"

case "$SERVICE" in
  npm) service_dir=securityServices/npm ;;
  freshrss) service_dir=knowledgeServices/freshrss ;;
  vaultwarden) service_dir=securityServices/vaultwarden ;;
  watchtower) service_dir=securityServices/watchtower ;;
  *) echo "Unsupported restore service: $SERVICE" >&2; exit 1 ;;
esac

if [[ "$SERVICE" == watchtower ]]; then
  : "${WATCHTOWER_SCHEDULE:?Missing WATCHTOWER_SCHEDULE variable}"

  if [[ "$WATCHTOWER_SCHEDULE" == *$'\n'* || "$WATCHTOWER_SCHEDULE" == *$'\r'* ||
        "$WATCHTOWER_SCHEDULE" == *"'"* || "$WATCHTOWER_SCHEDULE" == *\\* ]]; then
    echo "WATCHTOWER_SCHEDULE cannot contain newlines, single quotes, or backslashes." >&2
    exit 1
  fi

  {
    printf '%s' "$WATCHTOWER_SCHEDULE" | base64 -w0; echo
    tar -C "$service_dir" -cf - restore.sh docker-compose.yml
  } | gcloud compute ssh --quiet "$VM_NAME" \
    --project "$PROJECT_ID" --zone "$ZONE" \
    --command 'sudo bash -c '"'"'
      set +x
      set -euo pipefail
      umask 077
      read -r schedule64
      workdir=$(mktemp -d /tmp/watchtower-restore-workflow.XXXXXXXX)
      trap "rm -rf -- \"\$workdir\"" EXIT
      tar -xf - -C "$workdir"
      schedule=$(printf %s "$schedule64" | base64 -d)
      unset schedule64
      printf "WATCHTOWER_SCHEDULE=\047%s\047\n" "$schedule" > "$workdir/.env"
      unset schedule
      cd "$workdir"
      export COMPOSE_PROJECT_NAME=watchtower
      printf "y\n" | bash ./restore.sh
    '"'"''
  exit
fi

: "${FORCE:?Missing force setting}"
: "${DROPBOX_AUTH_TOKEN:?Missing DROPBOX_AUTH_TOKEN secret}"
: "${DROPBOX_REFRESH_TOKEN:?Missing DROPBOX_REFRESH_TOKEN secret}"
: "${GPG_PASSPHRASE:?Missing GPG_PASSPHRASE secret}"

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
