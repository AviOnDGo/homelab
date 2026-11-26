#!/usr/bin/env bash
set -euo pipefail

case "${1:-}" in
  -h|--help)
    printf 'Usage: %s [--no-verify]\nInstalls rclone and writes a Dropbox-only rclone config.\n' "$0"
    printf 'Requires DROPBOX_AUTH_TOKEN and DROPBOX_REFRESH_TOKEN.\n'
    exit 0
    ;;
  ''|--no-verify) ;;
  *) printf 'Unexpected argument: %s\n' "$1" >&2; exit 2 ;;
esac

remote=${DROPBOX_REMOTE:-dropbox}
token=${DROPBOX_AUTH_TOKEN:-}
refresh=${DROPBOX_REFRESH_TOKEN:-}
if [[ -z $token || -z $refresh ]]; then
  printf 'Set both DROPBOX_AUTH_TOKEN and DROPBOX_REFRESH_TOKEN.\n' >&2
  exit 1
fi

# Skip apt when rclone came from elsewhere, so a newer binary is not replaced.
command -v rclone >/dev/null || sudo apt-get install -y rclone

config=${RCLONE_CONFIG:-$(rclone config file | tail -n 1)}
mkdir -p -- "$(dirname -- "$config")"
if [[ -f $config ]]; then
  mv -f -- "$config" "$config.bak"
fi
umask 077
# printf is a builtin, so the tokens never appear in a process argument list.
printf '[%s]\ntype = dropbox\ntoken = {"access_token":"%s","token_type":"bearer","refresh_token":"%s","expiry":"1970-01-01T00:00:00Z"}\n' \
  "$remote" "$token" "$refresh" >"$config"

if [[ ${1:-} != --no-verify ]]; then
  rclone lsd "$remote:" >/dev/null
fi
printf 'rclone remote %s is configured in %s.\n' "$remote" "$config"
