-- =============================================================================
-- 04_permissions.sql — schema/object grants and DEFAULT PRIVILEGES
--
-- Strategy: admin owns all schema objects. DEFAULT PRIVILEGES on the admin
-- role ensure every table/sequence/function admin creates is automatically
-- granted to role_developer (DML on all schemas) and role_app (DML on app only).
-- =============================================================================

\echo '[04_permissions] applying grants in template1...'

\c template1

-- Database-level CONNECT
GRANT CONNECT ON DATABASE template1 TO role_developer, role_app;

-- ----- Schema USAGE -----
-- USAGE on public is already granted to PUBLIC (we only revoked CREATE in 02_).
GRANT USAGE ON SCHEMA app TO role_developer, role_app;

-- ----- Existing object grants in `app` -----
-- (No tables exist yet, but be explicit so future-rerun is idempotent.)
GRANT SELECT, INSERT, UPDATE, DELETE, TRUNCATE
  ON ALL TABLES IN SCHEMA app TO role_developer;
GRANT USAGE, SELECT, UPDATE
  ON ALL SEQUENCES IN SCHEMA app TO role_developer;
GRANT EXECUTE
  ON ALL FUNCTIONS IN SCHEMA app TO role_developer;

GRANT SELECT, INSERT, UPDATE, DELETE
  ON ALL TABLES IN SCHEMA app TO role_app;          -- no TRUNCATE for app
GRANT USAGE
  ON ALL SEQUENCES IN SCHEMA app TO role_app;       -- no SELECT/UPDATE on sequences

-- ----- Existing object grants in `public` (developer only) -----
GRANT SELECT, INSERT, UPDATE, DELETE, TRUNCATE
  ON ALL TABLES IN SCHEMA public TO role_developer;
GRANT USAGE, SELECT, UPDATE
  ON ALL SEQUENCES IN SCHEMA public TO role_developer;
GRANT EXECUTE
  ON ALL FUNCTIONS IN SCHEMA public TO role_developer;

-- ----- DEFAULT PRIVILEGES (FOR ROLE admin) -----
-- Cover any future objects admin creates so we don't have to re-grant manually.
ALTER DEFAULT PRIVILEGES FOR ROLE admin IN SCHEMA app
  GRANT SELECT, INSERT, UPDATE, DELETE, TRUNCATE ON TABLES TO role_developer;
ALTER DEFAULT PRIVILEGES FOR ROLE admin IN SCHEMA app
  GRANT USAGE, SELECT, UPDATE ON SEQUENCES TO role_developer;
ALTER DEFAULT PRIVILEGES FOR ROLE admin IN SCHEMA app
  GRANT EXECUTE ON FUNCTIONS TO role_developer;

ALTER DEFAULT PRIVILEGES FOR ROLE admin IN SCHEMA app
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO role_app;   -- no TRUNCATE
ALTER DEFAULT PRIVILEGES FOR ROLE admin IN SCHEMA app
  GRANT USAGE ON SEQUENCES TO role_app;

ALTER DEFAULT PRIVILEGES FOR ROLE admin IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE, DELETE, TRUNCATE ON TABLES TO role_developer;
ALTER DEFAULT PRIVILEGES FOR ROLE admin IN SCHEMA public
  GRANT USAGE, SELECT, UPDATE ON SEQUENCES TO role_developer;
ALTER DEFAULT PRIVILEGES FOR ROLE admin IN SCHEMA public
  GRANT EXECUTE ON FUNCTIONS TO role_developer;

\echo '[04_permissions] applying grants in postgres database...'

\c postgres

GRANT CONNECT ON DATABASE postgres TO role_developer, role_app;

GRANT USAGE ON SCHEMA app TO role_developer, role_app;

GRANT SELECT, INSERT, UPDATE, DELETE, TRUNCATE
  ON ALL TABLES IN SCHEMA app TO role_developer;
GRANT USAGE, SELECT, UPDATE
  ON ALL SEQUENCES IN SCHEMA app TO role_developer;
GRANT EXECUTE
  ON ALL FUNCTIONS IN SCHEMA app TO role_developer;

GRANT SELECT, INSERT, UPDATE, DELETE
  ON ALL TABLES IN SCHEMA app TO role_app;
GRANT USAGE
  ON ALL SEQUENCES IN SCHEMA app TO role_app;

GRANT SELECT, INSERT, UPDATE, DELETE, TRUNCATE
  ON ALL TABLES IN SCHEMA public TO role_developer;
GRANT USAGE, SELECT, UPDATE
  ON ALL SEQUENCES IN SCHEMA public TO role_developer;
GRANT EXECUTE
  ON ALL FUNCTIONS IN SCHEMA public TO role_developer;

ALTER DEFAULT PRIVILEGES FOR ROLE admin IN SCHEMA app
  GRANT SELECT, INSERT, UPDATE, DELETE, TRUNCATE ON TABLES TO role_developer;
ALTER DEFAULT PRIVILEGES FOR ROLE admin IN SCHEMA app
  GRANT USAGE, SELECT, UPDATE ON SEQUENCES TO role_developer;
ALTER DEFAULT PRIVILEGES FOR ROLE admin IN SCHEMA app
  GRANT EXECUTE ON FUNCTIONS TO role_developer;

ALTER DEFAULT PRIVILEGES FOR ROLE admin IN SCHEMA app
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO role_app;
ALTER DEFAULT PRIVILEGES FOR ROLE admin IN SCHEMA app
  GRANT USAGE ON SEQUENCES TO role_app;

ALTER DEFAULT PRIVILEGES FOR ROLE admin IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE, DELETE, TRUNCATE ON TABLES TO role_developer;
ALTER DEFAULT PRIVILEGES FOR ROLE admin IN SCHEMA public
  GRANT USAGE, SELECT, UPDATE ON SEQUENCES TO role_developer;
ALTER DEFAULT PRIVILEGES FOR ROLE admin IN SCHEMA public
  GRANT EXECUTE ON FUNCTIONS TO role_developer;

\echo '[04_permissions] done'
