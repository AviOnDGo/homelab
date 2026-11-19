#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=/dev/null
source /etc/os-release
codename=${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}
if [[ ${ID:-} != ubuntu || ! $codename =~ ^[a-z]+$ ]]; then
  printf 'Docker setup requires Ubuntu with an identifiable release codename.\n' >&2
  exit 1
fi

# Leave an existing Engine in place rather than switching package sources under it.
if command -v dockerd >/dev/null; then
  if docker compose version >/dev/null 2>&1 && getent group docker >/dev/null; then
    printf 'Docker Engine, Compose and the Docker group are already present.\n'
    exit 0
  fi
  printf 'Docker Engine already exists but Compose or the Docker group is missing. Repair the existing installation before rerunning.\n' >&2
  exit 1
fi

sudo apt-get --error-on=any update
sudo apt-get install -y ca-certificates curl
# Reuse either supported APT source format rather than adding a duplicate entry.
if [[ ! -e /etc/apt/sources.list.d/docker.sources && ! -e /etc/apt/sources.list.d/docker.list ]]; then
  key=$(mktemp)
  trap 'rm -f -- "$key"' EXIT
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o "$key"
  sudo install -d -m 0755 /etc/apt/keyrings
  # APT can read this key without trusting it for unrelated repositories.
  sudo install -m 0644 "$key" /etc/apt/keyrings/docker.asc
  arch=$(dpkg --print-architecture)
  printf 'Types: deb\nURIs: https://download.docker.com/linux/ubuntu\nSuites: %s\nComponents: stable\nArchitectures: %s\nSigned-By: /etc/apt/keyrings/docker.asc\n' \
    "$codename" "$arch" | sudo tee /etc/apt/sources.list.d/docker.sources >/dev/null
  sudo apt-get --error-on=any update
fi

sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
docker compose version