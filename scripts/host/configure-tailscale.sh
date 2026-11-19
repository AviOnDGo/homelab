#!/usr/bin/env bash
set -euo pipefail

if ! command -v tailscale >/dev/null; then
  if [[ ! -d /run/systemd/system ]] || ! command -v apt-get >/dev/null; then
    printf 'Tailscale setup requires a Debian-based host running systemd.\n' >&2
    exit 1
  fi
  if ! command -v curl >/dev/null; then
    printf 'Install curl before running Tailscale setup.\n' >&2
    exit 1
  fi
  # Download completely before handing the installer to a privileged shell.
  installer=$(mktemp)
  trap 'rm -f -- "$installer"' EXIT
  curl -fsSL https://tailscale.com/install.sh -o "$installer"
  sudo sh "$installer"
fi
tailscale version
# Enrollment is separate so rerunning this script leaves existing tailnet settings alone.
printf 'To enroll a new host, run sudo tailscale up separately.\n'