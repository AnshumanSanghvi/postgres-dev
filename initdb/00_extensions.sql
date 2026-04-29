-- =============================================================================
-- 00_extensions.sql — CREATE EXTENSION in template1 so all new DBs inherit them
--
-- Note: auto_explain is preload-only (loaded via shared_preload_libraries in
-- postgresql.conf), it has no CREATE EXTENSION. Don't add it here.
-- =============================================================================

\echo '[00_extensions] installing extensions in template1...'

\c template1
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
CREATE EXTENSION IF NOT EXISTS pgaudit;
CREATE EXTENSION IF NOT EXISTS pg_partman;
CREATE EXTENSION IF NOT EXISTS pldbgapi;        -- pldebugger

\echo '[00_extensions] installing extensions in postgres database...'

\c postgres
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
CREATE EXTENSION IF NOT EXISTS pgaudit;
CREATE EXTENSION IF NOT EXISTS pg_partman;
CREATE EXTENSION IF NOT EXISTS pldbgapi;
-- pg_cron MUST be installed in cron.database_name (= 'postgres'). Schemas in
-- other databases can use cron.schedule_in_database() to dispatch jobs there.
CREATE EXTENSION IF NOT EXISTS pg_cron;

\echo '[00_extensions] done'
