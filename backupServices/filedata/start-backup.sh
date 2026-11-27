#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 || ! "$1" =~ ^(default|local|prod)$ ]]; then
  echo "Usage: $0 {default|local|prod}" >&2
  exit 1
fi

profile="$1"
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
config="${script_dir}/backup-volumes.conf"

# Listing once distinguishes an unavailable Docker daemon from a missing volume.
if ! volume_list="$(docker volume ls --format '{{.Name}}')"; then
  echo "ERROR: Cannot list Docker volumes; no backup deployment was started." >&2
  exit 1
fi

declare -a names=() volumes=() categories=()
declare -A seen_names=() seen_volumes=() seen_keys=()
category=""
missing=0

while IFS= read -r line || [[ -n "$line" ]]; do
  if [[ "$line" =~ ^#\ (AI|Container|Financial|Gaming|Knowledge|Media|Security|Stream)\ Services$ ]]; then
    category="${BASH_REMATCH[1]} Services"
    continue
  fi
  [[ -z "$line" || "$line" == \#* ]] && continue
  if [[ ! "$line" =~ ^([a-z0-9]+(-[a-z0-9]+)*)\|([a-z0-9_]+)\|([a-z]+(,[a-z]+)*)$ ]]; then
    echo "ERROR: Invalid entry in ${config}: ${line}" >&2
    exit 1
  fi
  name="${BASH_REMATCH[1]}"
  volume="${BASH_REMATCH[3]}"
  profiles="${BASH_REMATCH[4]}"
  key="${name//-/_}"
  key="${key^^}"
  if [[ -z "$category" || -v "seen_names[$name]" || -v "seen_volumes[$volume]" ||
        -v "seen_keys[$key]" ]]; then
    echo "ERROR: Missing category or duplicate backup entry: ${name}" >&2
    exit 1
  fi
  seen_names["$name"]=1
  seen_volumes["$volume"]=1
  seen_keys["$key"]=1

  unset entry_profiles
  declare -A entry_profiles=()
  IFS=',' read -r -a profile_names <<< "$profiles"
  for entry_profile in "${profile_names[@]}"; do
    if [[ ! "$entry_profile" =~ ^(default|local|prod)$ ||
          -v "entry_profiles[$entry_profile]" ]]; then
      echo "ERROR: Invalid host profiles for ${name}: ${profiles}" >&2
      exit 1
    fi
    entry_profiles["$entry_profile"]=1
  done
  if [[ ! -v 'entry_profiles[default]' ]]; then
    echo "ERROR: ${name} must include the default profile." >&2
    exit 1
  fi
  [[ -v "entry_profiles[$profile]" ]] || continue
  if ! grep -Fxq -- "$volume" <<< "$volume_list"; then
    echo "WARNING: Expected volume ${volume} is missing; skipping ${name}." >&2
    missing=$((missing + 1))
    continue
  fi
  names+=("$name")
  volumes+=("$volume")
  categories+=("$category")
done < "$config"

if (( ${#names[@]} == 0 )); then
  echo "ERROR: No existing volumes selected for profile ${profile}; nothing started." >&2
  exit 1
fi

override="$(mktemp "${TMPDIR:-/tmp}/filedata-compose.XXXXXXXX.yml")"
trap 'rm -f -- "$override"' EXIT

# The override contains no credentials; Compose resolves schedules from its environment.
{
  printf 'services:\n  filedata-backup:\n    volumes:\n'
  previous=""
  for ((i = 0; i < ${#names[@]}; i++)); do
    if [[ "${categories[$i]}" != "$previous" ]]; then
      printf '      ## %s\n' "${categories[$i]}"
      previous="${categories[$i]}"
    fi
    printf '      - %s:/backup-sources/%s:ro\n' "${volumes[$i]}" "${names[$i]}"
  done
  printf '    environment:\n'
  for name in "${names[@]}"; do
    key="${name//-/_}"
    key="${key^^}_CRON_SCHEDULE"
    printf '      %s: "${%s:?%s is required}"\n' "$key" "$key" "$key"
  done
  cat <<'EOF'
    command:
      - /bin/sh
      - -ec
      - |
        # Prevent cron wildcards from expanding while schedules are split into fields.
        set -f
        /usr/local/bin/configure-rclone.sh
        echo '# Crontab for filedata backups' > /etc/crontabs/root
EOF
  previous=""
  for ((i = 0; i < ${#names[@]}; i++)); do
    name="${names[$i]}"
    key="${name//-/_}"
    key="${key^^}_CRON_SCHEDULE"
    if [[ "${categories[$i]}" != "$previous" ]]; then
      printf "        echo '# %s' >> /etc/crontabs/root\n" "${categories[$i]}"
      previous="${categories[$i]}"
    fi
    # Double dollars defer expansion to the container instead of Compose.
    printf '        set -- $${%s}\n' "$key"
    printf '        if [ "$$#" -ne 5 ]; then echo "ERROR: %s must have five cron fields" >&2; exit 1; fi\n' "$key"
    printf '        printf "%%s %%s %%s %%s %%s /bin/bash /usr/local/bin/backup-script.sh %s >> /var/log/cron_%s.log 2>&1\\n" "$$1" "$$2" "$$3" "$$4" "$$5" >> /etc/crontabs/root\n' "$name" "$name"
  done
  cat <<'EOF'
        touch /var/log/cron.log
        crond -L /var/log/cron.log
        tail -f /var/log/cron.log
    healthcheck:
      test: ["CMD-SHELL", "pidof crond >/dev/null"]
      interval: 5s
      timeout: 3s
      retries: 6
      start_period: 10s
volumes:
EOF
  previous=""
  for ((i = 0; i < ${#volumes[@]}; i++)); do
    if [[ "${categories[$i]}" != "$previous" ]]; then
      printf '  ## %s\n' "${categories[$i]}"
      previous="${categories[$i]}"
    fi
    printf '  %s:\n    external: true\n    name: %s\n' "${volumes[$i]}" "${volumes[$i]}"
  done
} > "$override"

echo "Starting ${#names[@]} backup job(s) for ${profile}; ${missing} missing volume(s) skipped."
docker compose --project-directory "$script_dir" \
  -f "${script_dir}/docker-compose.yml" -f "$override" \
  up --build --force-recreate --wait --wait-timeout 60 filedata-backup
