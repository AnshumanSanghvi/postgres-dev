#!/usr/bin/env bash
# =============================================================================
# 03_roles.sh — group roles + login users
# Reads passwords from environment variables and injects them into psql via
# `-v` parameters (so plaintext never appears in shell history or logs).
# Runs in template1 and postgres so the roles exist cluster-wide.
# =============================================================================
set -Eeuo pipefail

: "${POSTGRES_ADMIN_PASSWORD:?POSTGRES_ADMIN_PASSWORD must be set}"
: "${POSTGRES_DEVELOPER_PASSWORD:?POSTGRES_DEVELOPER_PASSWORD must be set}"
: "${POSTGRES_APP_PASSWORD:?POSTGRES_APP_PASSWORD must be set}"

echo "[03_roles] creating group roles + login users"

# Cluster-level objects: roles exist once, visible from every database.
psql -v ON_ERROR_STOP=1 \
     -v admin_pw="${POSTGRES_ADMIN_PASSWORD}" \
     -v dev_pw="${POSTGRES_DEVELOPER_PASSWORD}" \
     -v app_pw="${POSTGRES_APP_PASSWORD}" \
     -U postgres -h /tmp -p 5499 -d postgres <<'EOSQL'

-- Group roles (NOLOGIN; carry privileges, granted to login users via INHERIT)
CREATE ROLE role_developer NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE
                           NOREPLICATION NOBYPASSRLS INHERIT;
CREATE ROLE role_app       NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE
                           NOREPLICATION NOBYPASSRLS INHERIT;

-- Admin user — full superuser. Owns all schema objects from now on.
CREATE ROLE admin LOGIN SUPERUSER CREATEDB CREATEROLE REPLICATION BYPASSRLS
  PASSWORD :'admin_pw';

-- Re-own the app schema to admin (was bootstrap-postgres-owned from 02_schemas.sql)
\c template1
ALTER SCHEMA app OWNER TO admin;
\c postgres
ALTER SCHEMA app OWNER TO admin;

-- Developer user — RLS enforced (NOBYPASSRLS), can read all stats.
CREATE ROLE developer LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE
                            NOREPLICATION NOBYPASSRLS INHERIT
  PASSWORD :'dev_pw'
  IN ROLE role_developer;
GRANT pg_monitor, pg_read_all_stats TO developer;

-- App user — RLS enforced, capped connection count, narrowest privileges
-- (actual GRANTs come in 04_permissions.sql).
CREATE ROLE app LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE
                      NOREPLICATION NOBYPASSRLS INHERIT
  CONNECTION LIMIT 50
  PASSWORD :'app_pw'
  IN ROLE role_app;

EOSQL

echo "[03_roles] done"
