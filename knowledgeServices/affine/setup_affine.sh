#!/usr/bin/env bash
set -euo pipefail

# Detect container runtime
if command -v docker &>/dev/null; then
  COMPOSE="docker compose"
elif command -v podman-compose &>/dev/null; then
  COMPOSE="podman-compose"
else
  echo "ERROR: Docker or podman-compose is required but not found." >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Setting up AFFiNE..."

# 1. Verify knowledge_network exists (created and owned by NPM)
echo "--> Checking knowledge_network..."
if ! docker network inspect knowledge_network >/dev/null 2>&1; then
  echo "ERROR: knowledge_network does not exist." >&2
  echo "       knowledge_network is created and owned by Nginx Proxy Manager." >&2
  echo "       Start NPM first: docker compose up -d in securityServices/npm/" >&2
  exit 1
fi
echo "    knowledge_network: OK"

# 2. Create external named volumes
echo "--> Creating external Docker volumes..."
docker volume inspect affine_filedata >/dev/null 2>&1    || docker volume create affine_filedata
docker volume inspect affine_postgresdata >/dev/null 2>&1 || docker volume create affine_postgresdata
echo "    affine_filedata:      OK"
echo "    affine_postgresdata:  OK"

# 3. Start services
echo "--> Starting AFFiNE stack..."
cd "$SCRIPT_DIR"
$COMPOSE up -d

echo ""
echo "==> AFFiNE setup complete."
echo ""
echo "  Internal port : 3010 (not exposed on host)"
echo "  Access        : Configure an NPM proxy host pointing to affine_server:3010"
echo ""
echo "  Volumes:"
echo "    affine_filedata     — uploaded files, attachments, and runtime state"
echo "    affine_postgresdata — PostgreSQL data directory"
echo ""
echo "  Logs:"
echo "    $COMPOSE logs -f affine"