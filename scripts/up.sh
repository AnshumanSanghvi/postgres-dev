#!/usr/bin/env bash
# Bring the postgres-dev container up and wait for healthy.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

if [[ ! -f .env ]]; then
  echo "[up] .env not found; copying from .env.example" >&2
  cp .env.example .env
fi

docker compose up -d --build
echo "[up] waiting for healthy..."

for i in {1..30}; do
  status="$(docker inspect -f '{{.State.Health.Status}}' postgres-dev 2>/dev/null || echo "missing")"
  case "$status" in
    healthy) echo "[up] healthy"; exit 0 ;;
    unhealthy) echo "[up] unhealthy" >&2; docker compose logs --tail=30 postgres; exit 1 ;;
  esac
  sleep 2
done

echo "[up] timed out waiting for health" >&2
docker compose logs --tail=50 postgres
exit 1
