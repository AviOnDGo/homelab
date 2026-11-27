#!/usr/bin/env bash
set +x
set -euo pipefail

: "${VM_NAME:?Missing VM name}"
: "${PROJECT_ID:?Missing project ID}"
: "${ZONE:?Missing zone}"
: "${DROPBOX_AUTH_TOKEN:?Missing DROPBOX_AUTH_TOKEN secret}"
: "${DROPBOX_REFRESH_TOKEN:?Missing DROPBOX_REFRESH_TOKEN secret}"
: "${GPG_PASSPHRASE:?Missing GPG_PASSPHRASE secret}"

for name in DROPBOX_AUTH_TOKEN DROPBOX_REFRESH_TOKEN GPG_PASSPHRASE DISCORD_WEBHOOK_URL; do
  value="${!name:-}"
  if [[ "$value" == *$'\n'* || "$value" == *$'\r'* ]]; then
    echo "$name must be a single line." >&2
    exit 1
  fi
done

for name in DROPBOX_AUTH_TOKEN DROPBOX_REFRESH_TOKEN; do
  value="${!name}"
  if [[ "$value" == *\"* || "$value" == *\\* ]]; then
    echo "$name cannot contain quotes or backslashes in the rclone configuration." >&2
    exit 1
  fi
done

{
  for name in DROPBOX_AUTH_TOKEN DROPBOX_REFRESH_TOKEN GPG_PASSPHRASE DISCORD_WEBHOOK_URL; do
    printf '%s' "${!name:-}" | base64 -w0
    echo
  done
  tar -C backupServices/filedata -cf - \
    Dockerfile .dockerignore docker-compose.yml backup-volumes.conf start-backup.sh \
    filedata-backup-script.sh configure-rclone.sh path.prod
} | gcloud compute ssh --quiet "$VM_NAME" \
  --project "$PROJECT_ID" --zone "$ZONE" \
  --command 'sudo bash -c '"'"'
    set +x
    set -euo pipefail
    umask 077
    for name in DROPBOX_AUTH_TOKEN DROPBOX_REFRESH_TOKEN GPG_PASSPHRASE DISCORD_WEBHOOK_URL; do
      read -r encoded
      value="$(printf %s "$encoded" | base64 -d)"
      export "$name=$value"
    done
    unset encoded value
    workdir=$(mktemp -d /tmp/filedata-backup-workflow.XXXXXXXX)
    trap "rm -rf -- \"\$workdir\"" EXIT
    tar -xf - -C "$workdir"
    export COMPOSE_PROJECT_NAME=filedata-backup-gcp

    while IFS="|" read -r name volume profiles mode _; do
      [[ -z "$name" || "$name" == \#* ]] && continue
      if [[ ",$profiles," == *,prod,* ]]; then
        if [[ "$mode" != archive ]]; then
          echo "ERROR: Production backup $name requires unsupported mode $mode." >&2
          exit 1
        fi
        key="${name//-/_}"
        key="${key^^}"
        if ! grep -Eq "^${key}_DROPBOX_PATH=.+" "$workdir/path.prod"; then
          echo "ERROR: Production Dropbox destination missing for $name." >&2
          exit 1
        fi
        if ! docker volume inspect "$volume" >/dev/null; then
          echo "ERROR: Required production source volume $volume is missing." >&2
          exit 1
        fi
      fi
    done < "$workdir/backup-volumes.conf"

    # Use a private temporary env-file without changing an existing host configuration.
    : > "$workdir/workflow-input"
    for name in DROPBOX_AUTH_TOKEN DROPBOX_REFRESH_TOKEN GPG_PASSPHRASE DISCORD_WEBHOOK_URL; do
      value="${!name}"
      value="${value//\\/\\\\}"
      value="${value//\"/\\\"}"
      value="${value//\$/\$\$}"
      printf "%s=\"%s\"\n" "$name" "$value" >> "$workdir/workflow-input"
    done
    unset value DROPBOX_AUTH_TOKEN DROPBOX_REFRESH_TOKEN GPG_PASSPHRASE DISCORD_WEBHOOK_URL
    sed -i "s/^      - \\.env$/      - workflow-input/" "$workdir/docker-compose.yml"
    if ! grep -Fxq "      - workflow-input" "$workdir/docker-compose.yml"; then
      echo "ERROR: Cannot configure the temporary Compose env file." >&2
      exit 1
    fi

    docker build -t homelab/filedata-backup:local "$workdir"
    secrets_volume="${COMPOSE_PROJECT_NAME}_gpg-secrets"
    if docker volume inspect "$secrets_volume" >/dev/null 2>&1; then
      if ! docker run --rm --entrypoint /bin/sh \
        -v "$secrets_volume:/run/secrets:ro" homelab/filedata-backup:local \
        -c "test ! -e /run/secrets/gpg-passphrase"; then
        echo "ERROR: Existing GPG secret volume overrides the supplied passphrase; resolve it before retrying." >&2
        exit 1
      fi
    fi
    bash "$workdir/start-backup.sh" prod
    echo "Filedata backup scheduler is healthy. Verify its crontab and first backup."
  '"'"''
