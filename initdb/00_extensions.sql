-- =============================================================================
-- 00_extensions.sql — CREATE EXTENSION in template1 so all new DBs inherit them
--
-- Note: auto_explain is preload-only (loaded via shared_preload_libraries in
-- postgresql.conf), it has no CREATE EXTENSION. Don't add it here.
-- =============================================================================

-- Convenience: bundle of extensions that go in every database.
-- (pg_cron is special — only in postgres database, see below.)
-- (wal2json is an output plugin used by logical decoding — no CREATE EXTENSION.)

\echo '[00_extensions] installing extensions in template1...'

\c template1

-- Observability / audit
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
CREATE EXTENSION IF NOT EXISTS pgaudit;
CREATE EXTENSION IF NOT EXISTS pg_buffercache;
CREATE EXTENSION IF NOT EXISTS pg_prewarm;

-- Partitioning + maintenance
CREATE EXTENSION IF NOT EXISTS pg_partman;
CREATE EXTENSION IF NOT EXISTS pg_squeeze;

-- Query planning helpers
CREATE EXTENSION IF NOT EXISTS hypopg;
CREATE EXTENSION IF NOT EXISTS pg_hint_plan;

-- Procedural / utility
CREATE EXTENSION IF NOT EXISTS plpython3u;       -- untrusted Python (superuser only)
CREATE EXTENSION IF NOT EXISTS pldbgapi;         -- pldebugger
CREATE EXTENSION IF NOT EXISTS tablefunc;
CREATE EXTENSION IF NOT EXISTS pgtap;            -- SQL unit testing

\echo '[00_extensions] installing extensions in postgres database...'

\c postgres

CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
CREATE EXTENSION IF NOT EXISTS pgaudit;
CREATE EXTENSION IF NOT EXISTS pg_buffercache;
CREATE EXTENSION IF NOT EXISTS pg_prewarm;
CREATE EXTENSION IF NOT EXISTS pg_partman;
CREATE EXTENSION IF NOT EXISTS pg_squeeze;
CREATE EXTENSION IF NOT EXISTS hypopg;
CREATE EXTENSION IF NOT EXISTS pg_hint_plan;
CREATE EXTENSION IF NOT EXISTS plpython3u;
CREATE EXTENSION IF NOT EXISTS pldbgapi;
CREATE EXTENSION IF NOT EXISTS tablefunc;
CREATE EXTENSION IF NOT EXISTS pgtap;

-- pg_cron MUST be installed in cron.database_name (= 'postgres'). Cross-database
-- jobs are scheduled via cron.schedule_in_database().
CREATE EXTENSION IF NOT EXISTS pg_cron;

\echo '[00_extensions] done'
