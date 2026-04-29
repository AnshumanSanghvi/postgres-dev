-- =============================================================================
-- 00_extensions.sql — CREATE EXTENSION in template1 so all new DBs inherit them
--
-- Note: auto_explain is preload-only (loaded via shared_preload_libraries in
-- postgresql.conf), it has no CREATE EXTENSION. Don't add it here.
-- =============================================================================

\echo '[00_extensions] installing extensions in template1...'

\c template1
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

\echo '[00_extensions] installing extensions in postgres database...'

\c postgres
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

\echo '[00_extensions] done'
