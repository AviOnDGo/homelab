#!/usr/bin/env bash
set -euo pipefail

# The toolkit exposes a working host driver to Docker; it cannot replace the driver.
if ! command -v apt-get >/dev/null || ! command -v dockerd >/dev/null ||
    ! command -v nvidia-smi >/dev/null || ! nvidia-smi -L; then
  printf 'Install Docker Engine and a working NVIDIA host driver on a Debian-based host first.\n' >&2
  exit 1
fi

if ! command -v nvidia-ctk >/dev/null; then
  sudo apt-get --error-on=any update
  sudo apt-get install -y ca-certificates curl gpg
  keyring=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
  repository=/etc/apt/sources.list.d/nvidia-container-toolkit.list
  # Preserve an existing APT source, and scope the new key to NVIDIA's repository.
  if [[ ! -e $repository ]]; then
    work=$(mktemp -d)
    trap 'rm -f -- "$work/key" "$work/list"; rmdir -- "$work"' EXIT
    curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | gpg --dearmor > "$work/key"
    curl -fsSL https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list |
      sed "s#^deb https://#deb [signed-by=$keyring] https://#" > "$work/list"
    sudo install -m 0644 "$work/key" "$keyring"
    sudo install -m 0644 "$work/list" "$repository"
    sudo apt-get --error-on=any update
  fi
  sudo apt-get install -y nvidia-container-toolkit
fi
# Write the runtime configuration without restarting Docker and disrupting workloads.
sudo nvidia-ctk runtime configure --runtime=docker
printf 'Docker runtime configured. Restart Docker during a maintenance window, then verify GPU access.\n'