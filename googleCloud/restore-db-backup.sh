#!/usr/bin/env bash
set +x
set -euo pipefail

: "${VM_NAME:?Missing VM name}"
: "${PROJECT_ID:?Missing project ID}"
: "${ZONE:?Missing zone}"
: "${DROPBOX_AUTH_TOKEN:?Missing DROPBOX_AUTH_TOKEN secret}"
: "${DROPBOX_REFRESH_TOKEN:?Missing DROPBOX_REFRESH_TOKEN secret}"
: "${GPG_PASSPHRASE:?Missing GPG_PASSPHRASE secret}"

names=(
  DROPBOX_AUTH_TOKEN DROPBOX_REFRESH_TOKEN GPG_PASSPHRASE DISCORD_WEBHOOK_URL
  FIREFLY_DB_USER FIREFLY_DB_PASSWORD ROMM_DB_USER ROMM_DB_PASSWORD
  PAPERLESS_DB_USER PAPERLESS_DB_PASSWORD IMMICH_DB_USER IMMICH_DB_PASSWORD
  INVIDIOUS_DB_USER INVIDIOUS_DB_PASSWORD FIREFOXSYNC_DB_USER FIREFOXSYNC_DB_PASSWORD
)
for name in "${names[@]}"; do
  value="$(printenv "$name" || true; printf '.')"
  value="${value%.}"
  value="${value%$'\n'}"
  if [[ "$value" == *$'\n'* || "$value" == *$'\r'* ]]; then
    echo "ERROR: ${name} must be a single line." >&2
    exit 1
  fi
  if [[ "$name" == DROPBOX_AUTH_TOKEN || "$name" == DROPBOX_REFRESH_TOKEN ]]; then
    if [[ "$value" == *'"'* || "$value" == *\\* ]]; then
      echo "ERROR: ${name} cannot contain quotes or backslashes." >&2
      exit 1
    fi
  fi
done
unset value

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
{
  for name in "${names[@]}"; do
    value="$(printenv "$name" || true; printf '.')"
    value="${value%.}"
    value="${value%$'\n'}"
    printf '%s\n' "$name"
    printf '%s' "$value" | base64 -w0
    printf '\n'
  done
  tar -C "$root/backupServices/postgres" -cf - \
    Dockerfile .dockerignore docker-compose.yml backup-databases.conf \
    start-backup.sh db-backup-script.sh path.prod
} | gcloud compute ssh --quiet "$VM_NAME" \
  --project "$PROJECT_ID" --zone "$ZONE" \
  --command 'sudo bash -c '"'"'
    set +x
    set -euo pipefail
    umask 077
    names=(
      DROPBOX_AUTH_TOKEN DROPBOX_REFRESH_TOKEN GPG_PASSPHRASE DISCORD_WEBHOOK_URL
      FIREFLY_DB_USER FIREFLY_DB_PASSWORD ROMM_DB_USER ROMM_DB_PASSWORD
      PAPERLESS_DB_USER PAPERLESS_DB_PASSWORD IMMICH_DB_USER IMMICH_DB_PASSWORD
      INVIDIOUS_DB_USER INVIDIOUS_DB_PASSWORD FIREFOXSYNC_DB_USER FIREFOXSYNC_DB_PASSWORD
    )
    for expected in "${names[@]}"; do
      read -r name
      read -r encoded
      if [[ "$name" != "$expected" ]]; then
        echo "ERROR: Unexpected credential input." >&2
        exit 1
      fi
      value="$(printf %s "$encoded" | base64 -d)"
      export "$name=$value"
    done
    unset expected name encoded value
    workdir=$(mktemp -d /tmp/db-backup-workflow.XXXXXXXX)
    trap "rm -rf -- \"\$workdir\"" EXIT
    tar -xf - -C "$workdir"
    export COMPOSE_PROJECT_NAME=db-backup-gcp

    if ! volume_list="$(docker volume ls --format "{{.Name}}")"; then
      echo "ERROR: Cannot list Docker volumes; no backup deployment was started." >&2
      exit 1
    fi
    if ! network_list="$(docker network ls --format "{{.Name}}")"; then
      echo "ERROR: Cannot list Docker networks; no backup deployment was started." >&2
      exit 1
    fi

    missing=()
    available=0
    while IFS= read -r line || [[ -n "$line" ]]; do
      if [[ "$line" =~ ^([a-z0-9]+(-[a-z0-9]+)*)\|([a-z0-9_]+)\|([a-z]+(,[a-z]+)*)\|([a-z0-9_]+)\|(-?[0-9]+)\|(([a-zA-Z0-9*/,-]+\ ){4}[a-zA-Z0-9*/,-]+)$ ]]; then
        name="${BASH_REMATCH[1]}"
        volume="${BASH_REMATCH[3]}"
        profiles="${BASH_REMATCH[4]}"
        network="${BASH_REMATCH[6]}"
        if [[ ",$profiles," == *,prod,* ]]; then
          if ! grep -Fxq -- "$volume" <<< "$volume_list" ||
             ! grep -Fxq -- "$network" <<< "$network_list"; then
            echo "WARNING: Skipping ${name}: volume ${volume} or network ${network} is missing." >&2
            missing+=("$name")
            profiles=",${profiles},"
            profiles="${profiles/,prod,/,}"
            profiles="${profiles#,}"
            profiles="${profiles%,}"
            line="${name}|${volume}|${profiles}|${network}|${BASH_REMATCH[7]}|${BASH_REMATCH[8]}"
          else
            key="${name//-/_}"
            key="${key^^}"
            for suffix in USER PASSWORD; do
              if [[ -z "$(printenv "${key}_DB_${suffix}" || true)" ]]; then
                echo "ERROR: Missing ${key}_DB_${suffix} for production database ${name}." >&2
                exit 1
              fi
            done
            available=$((available + 1))
          fi
        fi
      fi
      printf "%s\n" "$line" >> "$workdir/filtered-registry"
    done < "$workdir/backup-databases.conf"

    notification_failed=0
    if (( ${#missing[@]} )); then
      if [[ -z "$DISCORD_WEBHOOK_URL" ]]; then
        echo "WARNING: Discord webhook is not configured; skipped databases were not sent to Discord." >&2
      else
        missing_text="$(printf "%s, " "${missing[@]}")"
        missing_text="${missing_text%, }"
        webhook="${DISCORD_WEBHOOK_URL//\\/\\\\}"
        webhook="${webhook//\"/\\\"}"
        printf "url = \"%s\"\n" "$webhook" > "$workdir/discord-curl.conf"
        unset webhook
        if ! curl -q --config "$workdir/discord-curl.conf" --fail --silent --show-error \
          --connect-timeout 5 --max-time 15 -H "Content-Type: application/json" \
          --data-binary "{\"content\":\"Database backup warning: skipped production databases: ${missing_text}. Restore their resources and rerun the database backup workflow.\",\"allowed_mentions\":{\"parse\":[]}}" \
          >/dev/null; then
          echo "ERROR: Failed to send skipped-database alert to Discord." >&2
          notification_failed=1
        fi
      fi
    fi
    if (( available == 0 )); then
      echo "ERROR: No production databases are available; no backup deployment was started." >&2
      exit 1
    fi
    mv "$workdir/filtered-registry" "$workdir/backup-databases.conf"

    for name in "${names[@]}"; do
      value="$(printenv "$name" || true)"
      value="${value//\\/\\\\}"
      value="${value//\"/\\\"}"
      value="${value//\$/\$\$}"
      printf "%s=\"%s\"\n" "$name" "$value" >> "$workdir/workflow-input"
    done
    unset value
    sed -i "s/^    env_file: .env$/    env_file: workflow-input/" "$workdir/docker-compose.yml"
    if ! grep -Fxq "    env_file: workflow-input" "$workdir/docker-compose.yml"; then
      echo "ERROR: Cannot configure the temporary Compose input." >&2
      exit 1
    fi

    docker_cli="$(command -v docker)"
    mkdir "$workdir/preflight-bin"
    cat > "$workdir/preflight-bin/docker" <<"EOF"
#!/usr/bin/env bash
if [[ "$1" == compose ]]; then
  exec "$DOCKER_CLI" "${@:1:7}" config -q
fi
exec "$DOCKER_CLI" "$@"
EOF
    chmod 700 "$workdir/preflight-bin/docker"
    export DOCKER_CLI="$docker_cli"
    PATH="$workdir/preflight-bin:$PATH" bash "$workdir/start-backup.sh" prod
    unset DOCKER_CLI

    docker build -t homelab/db-backup:local "$workdir"
    secrets_volume="${COMPOSE_PROJECT_NAME}_gpg-secrets"
    if docker volume inspect "$secrets_volume" >/dev/null 2>&1; then
      if ! docker run --rm --entrypoint /bin/sh \
        -v "$secrets_volume:/run/secrets:ro" homelab/db-backup:local \
        -c "test ! -e /run/secrets/gpg-passphrase"; then
        echo "ERROR: Existing GPG secret volume overrides the supplied passphrase." >&2
        exit 1
      fi
    fi
    existing_container="$(docker ps -a --filter "name=^/db-backup$" --format "{{.ID}}")"
    if [[ -n "$existing_container" ]]; then
      echo "Replacing existing db-backup container."
      docker stop "$existing_container"
      docker rm "$existing_container"
    fi
    bash "$workdir/start-backup.sh" prod
    echo "Database backup scheduler is healthy. Verify its crontab and first backup."
    if (( notification_failed )); then
      echo "ERROR: Scheduler started, but the skipped-database Discord alert failed." >&2
      exit 1
    fi
  '"'"''
