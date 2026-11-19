#!/usr/bin/env bash
set -euo pipefail

case "${1:-}" in
  -h|--help)
    printf 'Usage: %s\nRun as your normal user. Installs Docker, SSH and Tailscale.\n' "$0"
    exit 0
    ;;
  '') ;;
  *) printf 'Unexpected argument: %s\n' "$1" >&2; exit 2 ;;
esac

# Use sudo only for privileged steps so Docker access goes to the invoking user.
if (( EUID == 0 )); then
  printf 'Run bootstrap as the non-root user who should get Docker access.\n' >&2
  exit 1
fi

# Find the helpers relative to this script, not the caller's working directory.
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
operator=$(id -un)
if [[ ! -d /run/systemd/system ]]; then
  printf 'Bootstrap requires a host running systemd.\n' >&2
  exit 1
fi

# Install Docker first: its package provides the group used below.
"$script_dir/configure-docker.sh"
if [[ $(dpkg-query -W -f='${db:Status-Status} ' build-essential curl git 2>/dev/null) != 'installed installed installed ' ]]; then
  sudo apt-get --error-on=any update
  sudo apt-get install -y build-essential curl git
fi
# Match the whole group name and keep the user's other memberships.
groups=$(id -nG "$operator")
if [[ " $groups " != *' docker '* ]]; then
  sudo usermod -aG docker "$operator"
  printf 'Log out and back in for Docker group membership to take effect.\n'
fi

"$script_dir/configure-ssh.sh"
"$script_dir/configure-tailscale.sh"
printf 'Bootstrap finished. No reboot or network reconfiguration was requested.\n'