#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=/dev/null
source /etc/os-release
# /dev/dxg confirms WSL GPU passthrough is exposed to this distribution.
if [[ ${ID:-} != ubuntu || ${VERSION_CODENAME:-} != noble ]] ||
    ! grep -qi microsoft /proc/sys/kernel/osrelease || [[ ! -c /dev/dxg ]]; then
  printf 'This AMD ROCm installer requires Ubuntu 24.04 on WSL with GPU passthrough. Install native Linux drivers separately.\n' >&2
  exit 1
fi

if ! command -v amdgpu-install >/dev/null; then
  work=$(mktemp -d)
  package="$work/amdgpu-install.deb"
  trap 'rm -f -- "$package"; rmdir -- "$work"' EXIT
  # Allow APT's unprivileged downloader to traverse the temporary directory.
  chmod 0755 "$work"
  curl -fsSL https://repo.radeon.com/amdgpu-install/6.3.4/ubuntu/noble/amdgpu-install_6.3.60304-1_all.deb -o "$package"
  sudo apt-get install -y "$package"
fi
# WSL uses the Windows host GPU driver, so it does not need a Linux DKMS module.
sudo amdgpu-install -y --usecase=wsl,rocm --no-dkms
rocminfo