#!/usr/bin/env bash
# ============================================================================
# Postgres Dev Environment — container entrypoint
#   On first boot (PGDATA empty): runs initdb with explicit locale/encoding.
#   On every boot: execs the CMD (postgres) in the foreground so signals work.
# ============================================================================
set -Eeuo pipefail

if [[ ! -s "${PGDATA}/PG_VERSION" ]]; then
  echo "[entrypoint] initializing new cluster at ${PGDATA}"
  initdb \
    --username=postgres \
    --encoding=UTF8 \
    --locale=C.UTF-8 \
    --pgdata="${PGDATA}"
  echo "[entrypoint] initdb complete"
else
  echo "[entrypoint] existing cluster at ${PGDATA} — skipping initdb"
fi

exec "$@"
