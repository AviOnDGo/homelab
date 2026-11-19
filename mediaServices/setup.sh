#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Setup shared media directories
mkdir -p "${HOME}/.media/.downloads/complete" \
	"${HOME}/.media/.downloads/incomplete" \
	"${HOME}/.media/.watch" \
	"${HOME}/.media/Movies" \
	"${HOME}/.media/TVSeries" \
	"${HOME}/.media/Music"

sudo chown -R 0:0 "${SCRIPT_DIR}/immich"

# Transmission requires an operator-managed credentials file.
if [[ ! -f "${SCRIPT_DIR}/transmission/.env" ]]; then
	echo "Create mediaServices/transmission/.env from .env.example before setup." >&2
	exit 1
fi

# Create the external config volumes before starting each standalone stack.
for service in jackett radarr sonarr transmission; do
	docker volume create "${service}_filedata" >/dev/null
	docker compose -f "${SCRIPT_DIR}/${service}/docker-compose.yml" up -d
done
