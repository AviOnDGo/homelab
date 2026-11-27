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

    if ! volume_list="$(docker volume ls --format "{{.Name}}")"; then
      echo "ERROR: Cannot list Docker volumes; no backup deployment was started." >&2
      exit 1
    fi
    missing_volumes=()
    available=0
    while IFS="|" read -r name volume profiles mode _; do
      [[ -z "$name" || "$name" == \#* ]] && continue
      if [[ ",$profiles," == *,prod,* ]]; then
        if [[ ! "$volume" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ ]]; then
          echo "ERROR: Invalid production source volume name." >&2
          exit 1
        fi
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
        if grep -Fxq -- "$volume" <<< "$volume_list"; then
          available=$((available + 1))
        else
          echo "WARNING: Production source volume $volume is missing; its backup will not run." >&2
          missing_volumes+=("$volume")
        fi
      fi
    done < "$workdir/backup-volumes.conf"

    notification_failed=0
    if (( ${#missing_volumes[@]} > 0 )); then
      if [[ -z "$DISCORD_WEBHOOK_URL" ]]; then
        echo "WARNING: Discord webhook is not configured; missing volumes were not sent to Discord." >&2
      else
        missing_text="$(printf "%s, " "${missing_volumes[@]}")"
        missing_text="${missing_text%, }"
        webhook="${DISCORD_WEBHOOK_URL//\\/\\\\}"
        webhook="${webhook//\"/\\\"}"
        printf "url = \"%s\"\n" "$webhook" > "$workdir/discord-curl.conf"
        unset webhook
        if ! curl -q --config "$workdir/discord-curl.conf" --fail --silent --show-error \
          --connect-timeout 5 --max-time 15 \
          -H "Content-Type: application/json" \
          --data-binary "{\"content\":\"Filedata backup warning: missing production volumes: ${missing_text}. These volumes will not be backed up. Restore them and rerun the filedata backup workflow.\",\"allowed_mentions\":{\"parse\":[]}}" \
          >/dev/null; then
          echo "ERROR: Failed to send missing-volume alert to Discord." >&2
          notification_failed=1
        fi
      fi
    fi
    if (( available == 0 )); then
      echo "ERROR: No production source volumes are available; no backup deployment was started." >&2
      exit 1
    fi

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
    existing_container="$(docker ps -a --filter "name=^/filedata-backup$" --format "{{.ID}}")"
    if [[ -n "$existing_container" ]]; then
      echo "Replacing existing filedata-backup container."
      docker stop "$existing_container"
      docker rm "$existing_container"
    fi
    bash "$workdir/start-backup.sh" prod
    echo "Filedata backup scheduler is healthy. Verify its crontab and first backup."
    if (( notification_failed )); then
      echo "ERROR: Scheduler started, but the missing-volume Discord alert failed." >&2
      exit 1
    fi
  '"'"''
