#!/usr/bin/env bash
# ============================================================================
# Postgres Dev Environment — container entrypoint
#   On first boot (PGDATA empty): runs initdb with explicit locale/encoding,
#   sets the postgres superuser password from $POSTGRES_PASSWORD, and writes
#   pg_hba.conf to require scram-sha-256.
#   On every boot: execs the CMD (postgres) in the foreground so signals work.
# ============================================================================
set -Eeuo pipefail

if [[ ! -s "${PGDATA}/PG_VERSION" ]]; then
  : "${POSTGRES_PASSWORD:?POSTGRES_PASSWORD must be set on first boot}"

  echo "[entrypoint] initializing new cluster at ${PGDATA}"

  # Use a process-substitution pwfile so the password never lands on disk.
  initdb \
    --username=postgres \
    --pwfile=<(printf '%s' "${POSTGRES_PASSWORD}") \
    --auth-host=scram-sha-256 \
    --auth-local=scram-sha-256 \
    --encoding=UTF8 \
    --locale=C.UTF-8 \
    --pgdata="${PGDATA}"

  echo "[entrypoint] initdb complete"
else
  echo "[entrypoint] existing cluster at ${PGDATA} — skipping initdb"
fi

exec "$@"
