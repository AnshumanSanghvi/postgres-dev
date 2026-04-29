-- =============================================================================
-- 02_schemas.sql — schema layout
-- Creates the `app` schema in template1 (so all future databases inherit it
-- because CREATE DATABASE clones template1) and locks down `public`.
-- search_path is set cluster-wide via postgresql.conf (so it applies to every
-- database, including ones created later by users).
-- =============================================================================

\echo '[02_schemas] configuring template1...'

\c template1

-- Lock down public: revoke CREATE from PUBLIC role. USAGE remains so that
-- extensions installed in public stay accessible to all roles.
REVOKE CREATE ON SCHEMA public FROM PUBLIC;

-- Application schema, owned by the bootstrap superuser. Will be re-owned by
-- `admin` user once 03_roles.sh runs (S9).
CREATE SCHEMA IF NOT EXISTS app;

\echo '[02_schemas] configuring postgres database...'

\c postgres

REVOKE CREATE ON SCHEMA public FROM PUBLIC;
CREATE SCHEMA IF NOT EXISTS app;

\echo '[02_schemas] done'
