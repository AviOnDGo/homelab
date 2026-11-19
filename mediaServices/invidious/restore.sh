#!/usr/bin/env bash
# restore.sh - Restore Invidious PostgreSQL from latest Dropbox backup
# Usage: [PASSPHRASE=<gpg-passphrase>] [DROPBOX_PATH=/Apps/invidious] ./restore.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="${SCRIPT_DIR}/docker-compose.yml"
ENV_FILE="${SCRIPT_DIR}/.env"
VOLUME_NAME="invidious_postgresdata"
DB_CONTAINER="invidious-db"
DB_USER="${DB_USER:-kemal}"
DB_NAME="${DB_NAME:-invidious}"
DROPBOX_REMOTE="${DROPBOX_REMOTE:-dropbox}"
DROPBOX_PATH="${DROPBOX_PATH:-/App_acc/invidious}"
TMP_DIR="/tmp/invidious-restore-$$"

cleanup() {
    rm -rf "${TMP_DIR}"
    unset PASSPHRASE
}
trap cleanup EXIT

info()  { echo "[INFO]  $*"; }
warn()  { echo "[WARN]  $*"; }
error() { echo "[ERROR] $*" >&2; }

wait_for_pg_ready() {
    local attempts=60
    local i

    for ((i = 1; i <= attempts; i++)); do
        if docker exec "${DB_CONTAINER}" pg_isready -U "${DB_USER}" -d "${DB_NAME}" >/dev/null 2>&1; then
            return 0
        fi
        sleep 1
    done

    return 1
}

ask_existing_volume_action() {
    local choice

    >&2 echo
    >&2 echo "[WARN]  Volume '${VOLUME_NAME}' already exists."
    >&2 echo "[WARN]  Remove and recreate it before restore? [Y/n]"
    read -r -p "Remove and recreate volume? [Y/n]: " choice

    case "${choice:-Y}" in
        Y|y|YES|Yes|yes|"")
            echo "recreate"
            ;;
        N|n|NO|No|no)
            echo "skip"
            ;;
        *)
            >&2 echo "[WARN]  Invalid selection '${choice}'. Using default: remove and recreate."
            echo "recreate"
            ;;
    esac
}

if [[ ! -f "${ENV_FILE}" ]]; then
    error ".env file not found at ${ENV_FILE}. .env is required to restore this service."
    exit 1
fi

info "Running preflight checks..."
for cmd in docker rclone gpg zstd; do
    if ! command -v "${cmd}" >/dev/null 2>&1; then
        error "Required tool not found: ${cmd}"
        exit 1
    fi
done

if ! docker info >/dev/null 2>&1; then
    error "Cannot connect to Docker daemon."
    exit 1
fi

if ! rclone lsd "${DROPBOX_REMOTE}:" >/dev/null 2>&1; then
    error "Cannot reach rclone remote '${DROPBOX_REMOTE}'."
    error "Run 'rclone config' and verify the remote before retrying."
    exit 1
fi

info "Preflight checks passed."

if [[ -z "${PASSPHRASE:-}" ]]; then
    read -r -s -p "Enter GPG passphrase: " PASSPHRASE
    echo
fi

if [[ -z "${PASSPHRASE:-}" ]]; then
    error "Passphrase cannot be empty."
    exit 1
fi

info "Looking for latest backup in ${DROPBOX_REMOTE}:${DROPBOX_PATH} ..."
LATEST_FILE=$(rclone lsf "${DROPBOX_REMOTE}:${DROPBOX_PATH}" --files-only 2>/dev/null \
    | grep -E '\.sql\.zst\.gpg$' \
    | sort \
    | tail -n 1 \
    || true)

if [[ -z "${LATEST_FILE}" ]]; then
    error "No Invidious backup files found at ${DROPBOX_REMOTE}:${DROPBOX_PATH}."
    error "Expected at least one *.sql.zst.gpg file."
    exit 1
fi

mkdir -p "${TMP_DIR}"
info "Downloading latest backup: ${LATEST_FILE}"
rclone copy "${DROPBOX_REMOTE}:${DROPBOX_PATH}/${LATEST_FILE}" "${TMP_DIR}" --progress
LOCAL_BACKUP="${TMP_DIR}/${LATEST_FILE}"

if [[ ! -s "${LOCAL_BACKUP}" ]]; then
    error "Downloaded backup is missing or empty: ${LOCAL_BACKUP}"
    exit 1
fi

if docker volume inspect "${VOLUME_NAME}" >/dev/null 2>&1; then
    ACTION=$(ask_existing_volume_action)

    if [[ "${ACTION}" == "skip" ]]; then
        info "Keeping existing volume. Skipping restore by operator choice."
        info "Starting full Invidious stack..."
        docker compose -f "${COMPOSE_FILE}" up -d
        info "Skip-restore completed."
        exit 0
    fi
else
    ACTION="recreate"
fi

if [[ "${ACTION}" == "recreate" ]]; then
    info "Stopping Invidious stack before restore..."
    docker compose -f "${COMPOSE_FILE}" down

    if docker volume inspect "${VOLUME_NAME}" >/dev/null 2>&1; then
        info "Removing existing volume '${VOLUME_NAME}'..."
        docker volume rm "${VOLUME_NAME}" >/dev/null
    fi

    info "Creating volume '${VOLUME_NAME}'..."
    docker volume create "${VOLUME_NAME}" >/dev/null

    info "Creating Invidious containers..."
    docker compose -f "${COMPOSE_FILE}" create

    info "Starting database container '${DB_CONTAINER}'..."
    docker start "${DB_CONTAINER}" >/dev/null

    info "Waiting for PostgreSQL readiness..."
    if ! wait_for_pg_ready; then
        error "PostgreSQL did not become ready in '${DB_CONTAINER}'."
        error "Stack is intentionally left down for manual inspection."
        exit 1
    fi

    info "Restoring database from ${LATEST_FILE} ..."
    gpg --batch --yes --passphrase "${PASSPHRASE}" -d "${LOCAL_BACKUP}" \
        | zstd -d \
        | docker exec -i "${DB_CONTAINER}" psql -U "${DB_USER}" -d "${DB_NAME}"

    info "Verifying PostgreSQL readiness after restore..."
    if ! docker exec "${DB_CONTAINER}" pg_isready -U "${DB_USER}" -d "${DB_NAME}" >/dev/null 2>&1; then
        error "Readiness check failed after restore."
        error "Stack is intentionally left down for manual inspection."
        exit 1
    fi

    info "Starting full Invidious stack..."
    docker compose -f "${COMPOSE_FILE}" up -d

    echo
    echo "=============================================="
    echo " Invidious restore completed successfully"
    echo " Restored file: ${LATEST_FILE}"
    echo "=============================================="
fi
