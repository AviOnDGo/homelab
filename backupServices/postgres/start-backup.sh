#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 || ! "$1" =~ ^(default|local|prod)$ ]] ||
   [[ "$1" == default && ( $# -ne 2 || ! "$2" =~ ^(local|prod)$ ) ]] ||
   [[ "$1" != default && $# -ne 1 ]]; then
  echo "Usage: $0 {local|prod} | default {local|prod}" >&2
  exit 1
fi

profile="$1"
path_profile="${2:-$profile}"
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
config="${script_dir}/backup-databases.conf"
path_file="${script_dir}/path.${path_profile}"
if [[ ! -f "$path_file" ]]; then
  echo "ERROR: Missing destination file ${path_file}." >&2
  exit 1
fi

declare -A destinations=()
while IFS= read -r line || [[ -n "$line" ]]; do
  [[ -z "$line" || "$line" == \#* ]] && continue
  if [[ ! "$line" =~ ^([A-Z][A-Z0-9_]*_DROPBOX_BACKUP_PATH)=(.*)$ ]]; then
    echo "ERROR: Invalid destination entry in ${path_file}." >&2
    exit 1
  fi
  key="${BASH_REMATCH[1]}"
  value="${BASH_REMATCH[2]}"
  if [[ -v "destinations[$key]" || "$value" == *'$'* || "$value" == *'#'* ||
        "$value" == *'"'* || "$value" == *"'"* || "$value" == *\\* ||
        "$value" == *$'\r'* || "$value" == *$'\t'* ||
        "$value" == ' '* || "$value" == *' ' ]]; then
    echo "ERROR: Duplicate or unsupported destination value for ${key} in ${path_file}." >&2
    exit 1
  fi
  destinations["$key"]="$value"
done < "$path_file"

declare -a names=() volumes=() categories=() networks=() retentions=() schedules=()
declare -A seen_names=() seen_volumes=() seen_keys=() selected_networks=()
category=""

while IFS= read -r line || [[ -n "$line" ]]; do
  if [[ "$line" =~ ^#\ (AI|Container|Financial|Gaming|Knowledge|Media|Security|Stream)\ Services$ ]]; then
    category="${BASH_REMATCH[1]} Services"
    continue
  fi
  [[ -z "$line" || "$line" == \#* ]] && continue
  if [[ ! "$line" =~ ^([a-z0-9]+(-[a-z0-9]+)*)\|([a-z0-9_]+)\|([a-z]+(,[a-z]+)*)\|([a-z0-9_]+)\|(-?[0-9]+)\|(([a-zA-Z0-9*/,-]+\ ){4}[a-zA-Z0-9*/,-]+)$ ]]; then
    echo "ERROR: Invalid entry in ${config}: ${line}" >&2
    exit 1
  fi
  name="${BASH_REMATCH[1]}"
  volume="${BASH_REMATCH[3]}"
  profiles="${BASH_REMATCH[4]}"
  network="${BASH_REMATCH[6]}"
  retention="${BASH_REMATCH[7]}"
  schedule="${BASH_REMATCH[8]}"
  if [[ ! "$retention" =~ ^[1-9][0-9]*$ ]]; then
    echo "ERROR: Retention for ${name} must be at least one day." >&2
    exit 1
  fi
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
  [[ -v "entry_profiles[$profile]" ]] || continue
  destination_key="${key}_DROPBOX_BACKUP_PATH"
  if [[ -z "${destinations[$destination_key]:-}" ]]; then
    echo "ERROR: Missing ${destination_key} in ${path_file}." >&2
    exit 1
  fi
  names+=("$name")
  volumes+=("$volume")
  categories+=("$category")
  retentions+=("$retention")
  schedules+=("$schedule")
  selected_networks["$network"]=1
done < "$config"

if (( ${#names[@]} == 0 )); then
  echo "ERROR: No databases selected for profile ${profile}; nothing started." >&2
  exit 1
fi
mapfile -t networks < <(printf '%s\n' "${!selected_networks[@]}" | LC_ALL=C sort)

if ! volume_list="$(docker volume ls --format '{{.Name}}')"; then
  echo "ERROR: Cannot list Docker volumes; no backup deployment was started." >&2
  exit 1
fi
if ! network_list="$(docker network ls --format '{{.Name}}')"; then
  echo "ERROR: Cannot list Docker networks; no backup deployment was started." >&2
  exit 1
fi
missing=0
for volume in "${volumes[@]}"; do
  if ! grep -Fxq -- "$volume" <<< "$volume_list"; then
    echo "ERROR: Required volume ${volume} is missing." >&2
    missing=1
  fi
done
for network in "${networks[@]}"; do
  if ! grep -Fxq -- "$network" <<< "$network_list"; then
    echo "ERROR: Required network ${network} is missing." >&2
    missing=1
  fi
done
if (( missing )); then
  echo "ERROR: No backup deployment was started." >&2
  exit 1
fi

override="$(mktemp "${TMPDIR:-/tmp}/postgres-compose.XXXXXXXX.yml")"
trap 'rm -f -- "$override"' EXIT

{
  printf 'services:\n  db-backup:\n    env_file:\n      - path.%s\n    networks:\n' \
    "$path_profile"
  for network in "${networks[@]}"; do
    printf '      - %s\n' "$network"
  done
  printf '    volumes:\n'
  previous=""
  for ((i = 0; i < ${#names[@]}; i++)); do
    if [[ "${categories[$i]}" != "$previous" ]]; then
      printf '      ## %s\n' "${categories[$i]}"
      previous="${categories[$i]}"
    fi
    printf '      - %s:/var/lib/postgresql/%s:ro\n' "${volumes[$i]}" "${names[$i]}"
  done
  printf '      - gpg-secrets:/run/secrets:ro\n'
  printf '    environment:\n'
  for ((i = 0; i < ${#names[@]}; i++)); do
    key="${names[$i]//-/_}"
    key="${key^^}"
    printf '      %s_CRON_SCHEDULE: "%s"\n' "$key" "${schedules[$i]}"
    printf '      DB_BACKUP_%s_RETENTION_DAYS: "%s"\n' "$key" "${retentions[$i]}"
  done
  cat <<'EOF'
    command:
      - /bin/sh
      - -ec
      - |
        set -f
        echo '# Crontab for database backups' > /etc/crontabs/root
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
    printf '        set -- $${%s:-}\n' "$key"
    printf '        if [ "$$#" -ne 5 ]; then echo "ERROR: %s must have five cron fields" >&2; exit 1; fi\n' "$key"
    printf '        printf "%%s %%s %%s %%s %%s sh /usr/local/bin/backup-script.sh %s\\n" "$$1" "$$2" "$$3" "$$4" "$$5" >> /etc/crontabs/root\n' "$name"
  done
  cat <<'EOF'
        exec crond -f -L /dev/stdout
    healthcheck:
      test: ["CMD-SHELL", "pidof crond >/dev/null"]
      interval: 5s
      timeout: 3s
      retries: 6
      start_period: 10s
networks:
EOF
  for network in "${networks[@]}"; do
    printf '  %s:\n    name: %s\n    external: true\n' "$network" "$network"
  done
  printf 'volumes:\n'
  previous=""
  for ((i = 0; i < ${#names[@]}; i++)); do
    if [[ "${categories[$i]}" != "$previous" ]]; then
      printf '  ## %s\n' "${categories[$i]}"
      previous="${categories[$i]}"
    fi
    printf '  %s:\n    name: %s\n    external: true\n' "${volumes[$i]}" "${volumes[$i]}"
  done
  printf '  gpg-secrets:\n    driver: local\n'
} > "$override"

echo "Starting ${#names[@]} database backup job(s) for ${profile} with ${path_profile} destinations."
docker compose --project-directory "$script_dir" \
  -f "${script_dir}/docker-compose.yml" -f "$override" \
  up --build --force-recreate --wait --wait-timeout 60 db-backup
