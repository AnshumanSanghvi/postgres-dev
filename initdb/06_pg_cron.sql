-- =============================================================================
-- 06_pg_cron.sql — pg_cron access for the developer role
--
-- pg_cron's `cron` schema lives only in the database named by
-- `cron.database_name` (postgres in our config). To allow developers to
-- schedule jobs without superuser, we grant them USAGE + DML on cron.job.
--
-- Cross-database scheduling: from inside the postgres database, call
--   SELECT cron.schedule_in_database('job_name', '*/5 * * * *', $$SELECT 1$$, 'mydb');
-- Job runs in 'mydb' but metadata lives in postgres.
-- =============================================================================

\echo '[06_pg_cron] granting pg_cron access to role_developer...'

\c postgres

-- Schema USAGE: lets developer reference cron.* objects.
GRANT USAGE ON SCHEMA cron TO role_developer;

-- Job table: developer can list, schedule, modify, and remove jobs.
GRANT SELECT, INSERT, UPDATE, DELETE ON cron.job TO role_developer;
GRANT SELECT, INSERT, UPDATE, DELETE ON cron.job_run_details TO role_developer;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA cron TO role_developer;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA cron TO role_developer;

-- Future objects pg_cron creates (e.g. on minor version upgrade) inherit grants.
ALTER DEFAULT PRIVILEGES IN SCHEMA cron
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO role_developer;
ALTER DEFAULT PRIVILEGES IN SCHEMA cron
  GRANT EXECUTE ON FUNCTIONS TO role_developer;

\echo '[06_pg_cron] done'
