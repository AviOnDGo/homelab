#!/usr/bin/env bash
set -euo pipefail

if [[ ! -d /run/systemd/system ]] || ! command -v apt-get >/dev/null; then
  printf 'SSH setup requires a Debian-based host running systemd.\n' >&2
  exit 1
fi

# Check package status: dpkg can still know about a removed package.
if ! dpkg-query -W -f='${db:Status-Status}\n' openssh-server 2>/dev/null | grep -Fxq installed; then
  sudo apt-get --error-on=any update
  sudo apt-get install -y openssh-server
fi
# Start rather than restart so a rerun leaves a running SSH daemon alone.
sudo systemctl start ssh