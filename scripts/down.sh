#!/usr/bin/env bash
# Stop the postgres-dev container. Data and logs in ./volumes/ are preserved.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
docker compose down "$@"
