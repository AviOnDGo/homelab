#!/usr/bin/env bash
set -euo pipefail

case "${1:-}" in
  -h|--help)
    printf 'Usage: sudo %s\nCreates or enables an 8 GiB /swapfile without touching other swap.\n' "$0"
    exit 0
    ;;
  '') ;;
  *) printf 'Unexpected argument: %s\n' "$1" >&2; exit 2 ;;
esac

if (( EUID != 0 )); then
  printf 'Run this script as root: sudo %s\n' "$0" >&2
  exit 1
fi

fail() { printf '%s\n' "$*" >&2; exit 1; }

swapfile=/swapfile
fstab=/etc/fstab
# Hold the lock until both activation and the fstab update are done.
exec 9>/run/homelab-swap.lock
flock -x 9

# Refuse duplicate or non-automatic entries before touching the swapfile.
entries=$(awk -v path="$swapfile" '
  $1 == path {
    count++
    if ($3 != "swap" || $4 ~ /(^|,)noauto(,|$)/) invalid = 1
  }
  END { if (count > 1 || invalid) exit 1; print count+0 }
' "$fstab") || fail "Inspect $fstab: expected at most one automatic swap entry for $swapfile."
active=$(swapon --show=NAME --noheadings --raw)

if [[ -L $swapfile ]]; then
  fail "Refusing to use a symlink at $swapfile."
elif [[ -e $swapfile ]]; then
  # Verify the existing file is private, has no other hard links, and is already swap.
  [[ -f $swapfile ]] || fail "Refusing to use a non-regular file at $swapfile."
  [[ $(stat -c '%u %a %h %s' -- "$swapfile") == '0 600 1 8589934592' ]] ||
    fail "$swapfile must be a root-owned 8 GiB file with mode 600 and no hard links. Resize or replace it separately."
  [[ $(blkid -p -s TYPE -o value -- "$swapfile") == swap ]] ||
    fail "$swapfile does not have a recognized swap signature. Refusing to format an existing file."
else
  case "$(findmnt -n -o FSTYPE --target /)" in
    ext4|xfs) ;;
    *) fail 'Automatic swapfile creation is supported only on ext4 or XFS.' ;;
  esac
  temporary=$(mktemp /swapfile.XXXXXX)
  trap 'rm -f -- "$temporary"' EXIT
  chmod 600 "$temporary"
  # Writing blocks avoids sparse swapfiles; linking refuses to replace an existing target.
  dd if=/dev/zero of="$temporary" bs=1M count=8192 status=progress
  mkswap "$temporary"
  ln -T -- "$temporary" "$swapfile"
  rm -- "$temporary"
  trap - EXIT
fi

if ! grep -Fxq -- "$swapfile" <<<"$active"; then
  swapon -- "$swapfile"
fi
# Persist the entry only after the kernel accepts the swapfile.
if (( entries == 0 )); then
  printf '\n/swapfile none swap sw 0 0\n' >> "$fstab"
fi
free -h
