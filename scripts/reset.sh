#!/usr/bin/env bash
# Full reset: stop the container, wipe data and logs, re-init from initdb scripts.
# Use this when init scripts in initdb/ have changed and you need them re-run.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

read -r -p "[reset] this will DELETE all data in volumes/data and volumes/logs. Continue? [y/N] " ans
case "$ans" in
  y|Y|yes|YES) ;;
  *) echo "[reset] aborted"; exit 0 ;;
esac

docker compose down --remove-orphans

# We can't `rm -rf volumes/data` directly because contents are owned by the
# postgres UID inside the container. Use a one-shot container to clean.
docker run --rm \
  -v "$(pwd)/volumes/data:/data" \
  -v "$(pwd)/volumes/logs:/logs" \
  --entrypoint sh \
  oraclelinux:9-slim \
  -c 'find /data -mindepth 1 -delete; find /logs -mindepth 1 -delete'

# Recreate gitkeeps so the directory layout stays in git
touch volumes/data/.gitkeep volumes/logs/.gitkeep

echo "[reset] data and logs wiped — run scripts/up.sh to reinitialize"
