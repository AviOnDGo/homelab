#!/usr/bin/env bash

set -euo pipefail

RCLONE_CONFIG="${RCLONE_CONFIG:-/root/.config/rclone/rclone.conf}"
RCLONE_CONFIG_DIR="$(dirname "${RCLONE_CONFIG}")"

mkdir -p "${RCLONE_CONFIG_DIR}"
touch "${RCLONE_CONFIG}"
chmod 600 "${RCLONE_CONFIG}"

require_value() {
  local name="$1"
  local value="$2"
  [[ -n "${value}" ]]
}

write_dropbox() {
  require_value DROPBOX_AUTH_TOKEN "${DROPBOX_AUTH_TOKEN:-}" || return 0
  require_value DROPBOX_REFRESH_TOKEN "${DROPBOX_REFRESH_TOKEN:-}" || return 0

  cat >>"${RCLONE_CONFIG}" <<EOF
[${DROPBOX_REMOTE:-dropbox}]
type = dropbox
token = {"access_token":"${DROPBOX_AUTH_TOKEN}","token_type":"bearer","refresh_token":"${DROPBOX_REFRESH_TOKEN}","expiry":"1970-01-01T00:00:00Z"}
EOF
}

write_crypt() {
  local name="$1"
  local remote="$2"
  local password="$3"
  local password2="${4:-}"

  cat >>"${RCLONE_CONFIG}" <<EOF
[${name}]
type = crypt
remote = ${remote}
filename_encryption = standard
directory_name_encryption = true
password = $(rclone obscure "${password}")
EOF

  if [[ -n "${password2}" ]]; then
    printf 'password2 = %s\n' "$(rclone obscure "${password2}")" >>"${RCLONE_CONFIG}"
  fi
}

write_mega() {
  require_value MEGA_USER "${MEGA_USER:-}" || return 0
  require_value MEGA_PASS "${MEGA_PASS:-}" || return 0

  cat >>"${RCLONE_CONFIG}" <<EOF
[mega]
type = mega
user = ${MEGA_USER}
pass = $(rclone obscure "${MEGA_PASS}")
use_https = true
EOF

  if [[ -n "${RCLONE_CRYPT_PASSWORD:-}" ]]; then
    write_crypt mega-crypt mega: "${RCLONE_CRYPT_PASSWORD}" "${RCLONE_CRYPT_PASSWORD2:-}"
  fi
}

write_gdrive() {
  require_value GOOGLE_DRIVE_ACCESS_TOKEN "${GOOGLE_DRIVE_ACCESS_TOKEN:-}" || return 0
  require_value GOOGLE_DRIVE_REFRESH_TOKEN "${GOOGLE_DRIVE_REFRESH_TOKEN:-}" || return 0

  cat >>"${RCLONE_CONFIG}" <<EOF
[${GDRIVE_REMOTE:-gdrive}]
type = drive
scope = drive
token = {"access_token":"${GOOGLE_DRIVE_ACCESS_TOKEN}","token_type":"Bearer","refresh_token":"${GOOGLE_DRIVE_REFRESH_TOKEN}","expiry":"1970-01-01T00:00:00Z"}
EOF

  local client_id="${GOOGLE_DRIVE_CLIENT_ID:-}"
  local client_secret="${GOOGLE_DRIVE_CLIENT_SECRET:-}"
  if [[ -n "${client_id}" || -n "${client_secret}" ]]; then
    if [[ -z "${client_id}" || -z "${client_secret}" ]]; then
      echo "ERROR: GOOGLE_DRIVE_CLIENT_ID and GOOGLE_DRIVE_CLIENT_SECRET must both be set" >&2
      return 1
    fi

    printf 'client_id = %s\nclient_secret = %s\n' \
      "${client_id}" "${client_secret}" >>"${RCLONE_CONFIG}"
  fi

  if [[ -n "${RCLONE_CRYPT_PASSWORD:-}" ]]; then
    write_crypt "${GDRIVE_CRYPT_REMOTE:-gdrive-crypt}" "${GDRIVE_REMOTE:-gdrive}:" \
      "${RCLONE_CRYPT_PASSWORD}" "${RCLONE_CRYPT_PASSWORD2:-}"
  fi
}

write_filen() {
  local email="${FILEN_EMAIL:-}"
  local password="${FILEN_PASSWORD:-}"
  local api_key="${FILEN_API_KEY:-}"

  if [[ -z "${email}" && -z "${password}" && -z "${api_key}" ]]; then
    return 0
  fi

  if [[ -z "${email}" || -z "${password}" || -z "${api_key}" ]]; then
    echo "ERROR: FILEN_EMAIL, FILEN_PASSWORD, and FILEN_API_KEY must all be set" >&2
    return 1
  fi

  if [[ -z "${RCLONE_CRYPT_PASSWORD:-}" ]]; then
    echo "ERROR: RCLONE_CRYPT_PASSWORD is required for the Filen crypt remote" >&2
    return 1
  fi

  cat >>"${RCLONE_CONFIG}" <<EOF
[filen]
type = filen
email = ${email}
password = $(rclone obscure "${password}")
api_key = $(rclone obscure "${api_key}")
EOF

  write_crypt filen-crypt filen: "${RCLONE_CRYPT_PASSWORD}" "${RCLONE_CRYPT_PASSWORD2:-}"
}

write_dropbox
write_mega
write_gdrive
write_filen
chmod 600 "${RCLONE_CONFIG}"
