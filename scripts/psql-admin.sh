#!/usr/bin/env bash
# Open a psql session as the admin user.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
set -a; source .env; set +a
PGPASSWORD="${POSTGRES_ADMIN_PASSWORD}" exec psql -h localhost -p 5499 -U admin -d postgres "$@"
