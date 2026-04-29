# PostgreSQL Dev Environment — Task Tracker (Slice-Based)

## Status Legend
- `[ ]` Not started
- `[~]` In progress
- `[x]` Complete (built, tested, committed, README updated)
- `[!]` Blocked / needs decision

## Working Agreement
Each slice ends with **all four**: build → test → README update → `git commit`. Do not
mark a slice complete until all four are done. Each slice produces a working,
demonstrable increment.

---

## Slice 0 — Repo Bootstrap

- [x] **0.1** `git init` in `/Users/anshuman/workspace/Postgres`
- [x] **0.2** Create directory skeleton: `config/ initdb/ scripts/ volumes/data/ volumes/logs/`
- [x] **0.3** Write `.gitignore` (ignore `volumes/data/`, `volumes/logs/`, `.env`, `*.local`)
- [x] **0.4** Write `.hadolint.yaml` (basic config — fail on errors, warn on style)
- [x] **0.5** Write `scripts/lint-dockerfile.sh` (runs hadolint on Dockerfile)
- [x] **0.6** Stub `README.md` with title + "Status: Bootstrap" placeholder
- [x] **0.7** Initial commit: `chore: scaffold repo structure`

---

## Slice 1 — Bare PostgreSQL 17 on OL9-slim

**Goal:** prove a minimal PG17 container starts on OL9-slim with default config.

- [x] **1.1** Verify PGDG RHEL9 repo URL and `pgdg-redhat-repo` RPM (per-arch URLs work)
- [x] **1.2** Write minimal `Dockerfile`:
  - `FROM oraclelinux:9-slim`
  - Install PGDG repo, postgresql17-server, postgresql17-contrib
  - Set PATH to include `/usr/pgsql-17/bin`
  - Create postgres user/group, PGDATA dir
  - Simple ENTRYPOINT that runs `initdb` if PGDATA empty, then `postgres`
- [x] **1.3** Set explicit locale `C.UTF-8` and encoding `UTF8` in initdb invocation
- [x] **1.4** Set `ENV TZ=UTC`
- [x] **1.5** Run `scripts/lint-dockerfile.sh` — passes
- [x] **1.6** Build: `docker build -t postgres-dev:s1 .` — PG 17.9 aarch64, 373MB
- [x] **1.7** Run: `docker run --rm -d --name pg-s1 postgres-dev:s1`
- [x] **1.8** Verify: `docker exec pg-s1 psql -U postgres -c 'SELECT version();'` shows PG17.9
- [x] **1.9** Verify: SHOW timezone returns UTC
- [x] **1.10** Verify: SHOW server_encoding returns UTF8
- [x] **1.11** Verify multi-arch: image is arm64 on Apple Silicon host
- [x] **1.12** Update README: "Slice 1 — bare PG17 working" with build/run/connect commands
- [x] **1.13** Commit: `feat(s1): bare postgres 17 on oraclelinux 9-slim`

### S1 Implementation Notes
- `microdnf` URL-install of remote RPM was unreliable; switched to `curl -fsSL` then `dnf install /tmp/pgdg.rpm`
- `curl` is already in OL9-slim base; no need to install `curl-minimal` (causes conflict)
- `dnf` is not in OL9-slim by default; installed via `microdnf install dnf` first
- PGDG repo URL is per-arch: `EL-9-x86_64/...` for amd64, `EL-9-aarch64/...` for arm64
- Build time on arm64: ~6 minutes (most spent on dnf metadata download + dependency resolution)

---

## Slice 2 — Custom Config + Auth + Port

**Goal:** mount custom postgresql.conf and pg_hba.conf, enforce scram-sha-256, listen on 5499.

- [x] **2.1** Write minimal `config/postgresql.conf` (port 5499, listen all, password_encryption=scram-sha-256)
- [x] **2.2** Write `config/pg_hba.conf` (local + host scram-sha-256)
- [x] **2.3** Update Dockerfile/entrypoint to start with `-c config_file=/etc/postgresql/postgresql.conf -c hba_file=/etc/postgresql/pg_hba.conf`
- [x] **2.4** Build & run with `-v ./config:/etc/postgresql:ro -p 5499:5499`
- [x] **2.5** Verify: `psql -h localhost -p 5499 -U postgres` connects with password
- [x] **2.6** Verify: wrong password rejected
- [x] **2.7** Verify: `SHOW password_encryption;` returns `scram-sha-256`
- [x] **2.8** Update README: how to connect with password on 5499; note SSL is disabled
- [x] **2.9** Refactor Dockerfile to step-wise structure (cacheable RUN per logical unit)
- [x] **2.10** Commit: `feat(s2): custom config, scram-sha-256 auth, port 5499`

### S2 Implementation Notes
- Entrypoint now requires `POSTGRES_PASSWORD` on first boot; uses process-substitution `--pwfile` so password never lands on disk
- `initdb --auth-host=scram-sha-256 --auth-local=scram-sha-256` makes the cluster scram-sha-256-only from the start
- Dockerfile reorganized into 4 logical steps (dnf bootstrap → PGDG repo → PG core → fs/entrypoint) to maximize layer caching for future slices
- New working agreements added to PLAN.md: step-wise Dockerfile, skip-on-arch policy

---

## Slice 3 — Docker Compose + Volumes + .env

**Goal:** replace raw `docker run` with compose; persist data/logs across restarts.

- [x] **3.1** Write `compose.yml` with volumes, env_file, mem_limit, healthcheck, no platform pin
- [x] **3.2** Write `.env.example` (bootstrap + admin/dev/app passwords + POSTGRES_DB)
- [x] **3.3** Copy to local `.env` (gitignored)
- [x] **3.4** Write `scripts/up.sh`, `scripts/down.sh`, `scripts/reset.sh`
- [x] **3.5** Test: `scripts/up.sh` brings container up healthy
- [x] **3.6** Test: create a table, `down.sh`, `up.sh`, table still there (verified id=42 persists)
- [x] **3.7** Test: `scripts/reset.sh` wipes data and reinitializes
- [x] **3.8** Test: container memory enforced — `docker inspect` shows 512 MiB
- [x] **3.9** Update README: prerequisites, quick start, volume layout, reset workflow, scripts/
- [x] **3.10** Commit: `feat(s3): docker compose, volumes, env config, helper scripts`

### S3 Implementation Notes
- **PGDATA moved to subdirectory** `/var/lib/pgsql/data/pgdata` so `.gitkeep` at the bind-mount root doesn't trip initdb's "directory not empty" check
- **Bind-mount UID problem on Mac**: Docker Desktop virtiofs restricts `chown` from inside container. Solution: entrypoint runs as root, detects host UID/GID from the bind mount, uses `usermod`/`groupmod -o` to align the in-container postgres user to those IDs, then drops to postgres via `runuser`. Works on Linux (chown succeeds anyway) and Mac (no chown needed)
- `/run/postgresql` (image-internal, not bind-mounted) must be chowned to the now-aligned postgres UID so the unix socket lock file can be written
- `reset.sh` deletes data via a one-shot helper container (host can't `rm -rf` files owned by container postgres UID)
- Stale containers/networks from prior runs need cleanup before restart; could add `docker compose down --remove-orphans` to up.sh in future

---

## Slice 4 — OS Utilities + Bash UX

**Goal:** add terminal utilities to the image for in-container debugging.

- [ ] **4.1** Add to Dockerfile: procps-ng, less, vim-minimal, iputils, bind-utils, lsof, jq, tar, gzip, findutils, strace, curl
- [ ] **4.2** Set `ENV LESS=-iMRSx4`
- [ ] **4.3** Build & run
- [ ] **4.4** Test: each utility resolves on PATH (`which X` for each)
- [ ] **4.5** Update README: list of in-container utilities
- [ ] **4.6** Commit: `feat(s4): add os utilities for in-container debugging`

---

## Slice 5 — Memory Tuning, Timeouts, WAL, Resource Polish

**Goal:** dev-tuned postgresql.conf — full settings.

- [ ] **5.1** Update `config/postgresql.conf`:
  - `shared_buffers = 128MB`, `effective_cache_size = 384MB`, `work_mem = 4MB`, `maintenance_work_mem = 64MB`
  - `max_connections = 50`
  - `statement_timeout = 60s`, `idle_in_transaction_session_timeout = 5min`, `lock_timeout = 10s`
  - `max_wal_size = 1GB`, `min_wal_size = 80MB`, `wal_keep_size = 0`, `wal_level = logical`
  - `timezone = 'UTC'`, `log_timezone = 'UTC'`
- [ ] **5.2** Restart container, verify all settings via `SHOW` queries
- [ ] **5.3** Test: long-running query gets killed by `statement_timeout`
- [ ] **5.4** Test: idle transaction killed by `idle_in_transaction_session_timeout` (lower temporarily for test)
- [ ] **5.5** Update README: document each tunable and how to override per-project
- [ ] **5.6** Commit: `feat(s5): memory, timeout, and wal configuration`

---

## Slice 6 — Logging (stderr text + JSON file + rotation)

**Goal:** dual-format logging with rotation.

- [ ] **6.1** Update `config/postgresql.conf`:
  - `log_destination = 'stderr,jsonlog'`
  - `logging_collector = on`
  - `log_directory = '/var/log/postgresql'`
  - `log_filename = 'postgresql-%Y-%m-%d.json'`
  - `log_min_duration_statement = 0`
  - `log_rotation_age = 1d`, `log_rotation_size = 100MB`, `log_truncate_on_rotation = on`
  - `log_lock_waits = on`, `deadlock_timeout = 1s`
  - `log_line_prefix = '%m [%p] %q%u@%d '`
- [ ] **6.2** Ensure `/var/log/postgresql` has correct permissions in Dockerfile
- [ ] **6.3** Restart, run a query, confirm:
  - Text appears in `docker compose logs postgres` (stderr)
  - JSON appears in `./volumes/logs/postgresql-*.json`
- [ ] **6.4** Add `scripts/logs.sh` — tails JSON file with `jq` pretty-printing
- [ ] **6.5** Update README: log layout, formats, where to find them, how to use scripts/logs.sh
- [ ] **6.6** Commit: `feat(s6): dual stderr+json logging with rotation`

---

## Slice 7 — First Extensions: pg_stat_statements + auto_explain

**Goal:** introduce `shared_preload_libraries` and per-query observability.

- [ ] **7.1** Update Dockerfile to ensure contrib package present (already from S1)
- [ ] **7.2** Update `config/postgresql.conf`:
  - `shared_preload_libraries = 'pg_stat_statements,auto_explain'`
  - `pg_stat_statements.track = 'all'`, `pg_stat_statements.max = 10000`
  - `auto_explain.log_min_duration = 1000`, `log_analyze = on`, `log_buffers = on`, `log_format = 'json'`
- [ ] **7.3** Write `initdb/00_extensions.sql`:
  - `\c template1`
  - `CREATE EXTENSION IF NOT EXISTS pg_stat_statements;`
  - (auto_explain has no CREATE EXTENSION — preload only)
- [ ] **7.4** Reset volumes, fresh boot, verify:
  - `SHOW shared_preload_libraries;`
  - `SELECT count(*) FROM pg_stat_statements;`
  - Slow query (`SELECT pg_sleep(2)`) shows up in `auto_explain` JSON output
- [ ] **7.5** Test: new database inherits pg_stat_statements (`CREATE DATABASE testdb; \c testdb; \dx`)
- [ ] **7.6** Update README: pg_stat_statements + auto_explain example queries
- [ ] **7.7** Commit: `feat(s7): pg_stat_statements + auto_explain`

---

## Slice 8 — Schemas + search_path

**Goal:** create `app` schema, lock down `public`, set DB-level search_path.

- [ ] **8.1** Write `initdb/02_schemas.sql`:
  - `REVOKE CREATE ON SCHEMA public FROM PUBLIC;`
  - `CREATE SCHEMA IF NOT EXISTS app;`
  - `ALTER DATABASE template1 SET search_path = app, public;`
  - `ALTER DATABASE postgres SET search_path = app, public;`
- [ ] **8.2** Reset, verify:
  - `\dn+` shows `app` and `public` with correct ownership
  - New DB: `\c testdb; SHOW search_path;` returns `app, public`
- [ ] **8.3** Test: non-superuser cannot CREATE in public
- [ ] **8.4** Update README: schema strategy, why public is locked down, how to add custom schemas
- [ ] **8.5** Commit: `feat(s8): app schema + locked-down public + search_path`

---

## Slice 9 — Roles + Login Users (with shell password injection)

**Goal:** create admin/developer/app users with env-var-injected passwords.

- [ ] **9.1** Write `initdb/03_roles.sh` (shebang, set -e):
  ```bash
  psql -v ON_ERROR_STOP=1 \
    -v admin_pw="${POSTGRES_ADMIN_PASSWORD}" \
    -v dev_pw="${POSTGRES_DEVELOPER_PASSWORD}" \
    -v app_pw="${POSTGRES_APP_PASSWORD}" \
    -U "$POSTGRES_USER" -d postgres <<-'EOSQL'
      -- group roles
      CREATE ROLE role_developer NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS INHERIT;
      CREATE ROLE role_app       NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS INHERIT;
      -- login users
      CREATE ROLE admin     LOGIN SUPERUSER CREATEDB CREATEROLE REPLICATION BYPASSRLS PASSWORD :'admin_pw';
      CREATE ROLE developer LOGIN PASSWORD :'dev_pw' IN ROLE role_developer;
      CREATE ROLE app       LOGIN CONNECTION LIMIT 50 PASSWORD :'app_pw' IN ROLE role_app;
      -- built-in monitoring grants
      GRANT pg_monitor, pg_read_all_stats TO developer;
  EOSQL
  ```
- [ ] **9.2** Make script executable in Dockerfile (`chmod +x` during COPY)
- [ ] **9.3** Make sure `.env` is loaded by compose (already done in S3)
- [ ] **9.4** Reset, verify each user can connect:
  - `psql -h localhost -p 5499 -U admin -W` (password from .env)
  - same for developer and app
- [ ] **9.5** Test: wrong password rejected for all
- [ ] **9.6** Test: `SELECT current_user, session_user;` returns expected role
- [ ] **9.7** Add `scripts/psql-admin.sh`, `psql-developer.sh`, `psql-app.sh` (read .env, connect)
- [ ] **9.8** Update README: **document users + default passwords**, role attributes table, how to override via .env
- [ ] **9.9** Update healthcheck in compose.yml to use `admin` user now that it exists
- [ ] **9.10** Commit: `feat(s9): admin/developer/app users with env-var passwords`

---

## Slice 10 — Permissions + DEFAULT PRIVILEGES

**Goal:** wire up grants so admin can create objects and developer/app inherit access.

- [ ] **10.1** Write `initdb/04_permissions.sql`:
  - Schema USAGE: `role_developer` on app+public; `role_app` on app only
  - Existing-object grants: developer DML+TRUNCATE on all tables in app+public, EXECUTE on functions; app DML on app tables, USAGE on app sequences
  - DEFAULT PRIVILEGES set FOR ROLE admin in schemas app and public, granting to role_developer and role_app appropriately
  - GRANT CONNECT ON DATABASE postgres TO role_developer, role_app
- [ ] **10.2** Reset, verify the test matrix:
  - As admin: `CREATE TABLE app.t1(id serial, name text);`
  - As developer: SELECT/INSERT/UPDATE/DELETE/TRUNCATE on app.t1 ✓
  - As developer: `CREATE TABLE app.t2(id int);` ✗ (should fail)
  - As app: SELECT/INSERT/UPDATE/DELETE on app.t1 ✓
  - As app: TRUNCATE app.t1 ✗
  - As app: `SELECT * FROM public.pg_stat_statements;` ✗
- [ ] **10.3** Test RLS enforcement: admin creates table with policy, developer/app see filtered rows
- [ ] **10.4** Update README: permissions matrix, DEFAULT PRIVILEGES explanation
- [ ] **10.5** Commit: `feat(s10): role grants and default privileges`

---

## Slice 11 — pg_cron + pgaudit + pg_partman_bgw + pldebugger (preload extensions)

**Goal:** add the four extensions that need shared_preload_libraries entries.

- [ ] **11.1** Verify exact PGDG package names + versions for OL9/PG17:
  - `pg_cron_17`, `pgaudit17_17`, `pg_partman17`, `pldebugger17`
- [ ] **11.2** Add packages to Dockerfile with version pins
- [ ] **11.3** Run `scripts/lint-dockerfile.sh`
- [ ] **11.4** Update `config/postgresql.conf`:
  - `shared_preload_libraries = 'pg_stat_statements,auto_explain,pg_cron,pgaudit,pg_partman_bgw,plugin_debugger'`
  - `cron.database_name = 'postgres'`, `cron.use_background_workers = on`
  - `pgaudit.log = 'all'`, `pgaudit.log_catalog = on`, `pgaudit.log_relation = on`, `pgaudit.log_statement_once = off`
  - `pg_partman_bgw.dbname = 'postgres'`, `pg_partman_bgw.interval = 3600`, `pg_partman_bgw.role = 'admin'`
- [ ] **11.5** Add to `initdb/00_extensions.sql` (in template1):
  - `CREATE EXTENSION pg_cron;`
  - `CREATE EXTENSION pgaudit;`
  - `CREATE EXTENSION pg_partman;`
  - `CREATE EXTENSION pldbgapi;`  (pldebugger)
- [ ] **11.6** Write `initdb/06_pg_cron.sql`:
  - GRANT USAGE ON SCHEMA cron TO role_developer
  - GRANT pg_cron_admin role to role_developer (or appropriate cron grants)
  - Document who can call `cron.schedule_in_database()`
- [ ] **11.7** Reset and verify each loaded:
  - `SHOW shared_preload_libraries;` — all 6
  - `\dx` — pg_cron, pgaudit, pg_partman, pldbgapi all present
  - Schedule a test cron job via `cron.schedule_in_database()`, observe it run
  - Run a query as `app` and confirm pgaudit logs it
- [ ] **11.8** Update README: usage example for each (cron job, pgaudit log inspection, partman parent table, pldebugger session)
- [ ] **11.9** Commit: `feat(s11): pg_cron, pgaudit, pg_partman, pldebugger`

---

## Slice 12 — Remaining Extensions (no preload required)

**Goal:** add pg_buffercache, pg_prewarm, pg_squeeze, hypopg, pg_hint_plan, wal2json, plpython3u, pgtap, tablefunc.

- [ ] **12.1** Verify PGDG package names + versions: `pg_squeeze17`, `hypopg_17`, `pg_hint_plan_17`, `wal2json17`, `pgtap_17` (or source)
- [ ] **12.2** Install in Dockerfile with version pins; lint passes
- [ ] **12.3** Add to `initdb/00_extensions.sql` (in template1):
  - pg_buffercache, pg_prewarm, pg_squeeze, hypopg, pg_hint_plan, wal2json, plpython3u, pgtap, tablefunc
- [ ] **12.4** Reset, verify `\dx` shows all
- [ ] **12.5** Smoke-test each:
  - `SELECT * FROM pg_buffercache LIMIT 1;`
  - `SELECT pg_prewarm('app.t1');`
  - `SELECT hypopg_create_index('CREATE INDEX ON app.t1(id)');`
  - `EXPLAIN (FORMAT JSON) SELECT 1;` with hint
  - wal2json: confirm decodable replication slot
  - `DO $$ BEGIN PERFORM 1; END $$ LANGUAGE plpython3u;`
  - pgtap: `SELECT pass('basic');`
  - `SELECT * FROM crosstab('SELECT 1,1,1');` (tablefunc)
- [ ] **12.6** Update README: usage example for each
- [ ] **12.7** Commit: `feat(s12): pg_buffercache, pg_prewarm, pg_squeeze, hypopg, pg_hint_plan, wal2json, plpython3u, pgtap, tablefunc`

---

## Slice 13 — pg_anonymizer

**Goal:** install pg_anonymizer, run anon.init(), grant access to developer.

- [ ] **13.1** Verify install path: DALIBO RPM for OL9/PG17 if available; else source build
- [ ] **13.2** Install in Dockerfile with version pin
- [ ] **13.3** Add to `initdb/00_extensions.sql`: `CREATE EXTENSION anon CASCADE;`
- [ ] **13.4** Write `initdb/01_anon_init.sh`:
  ```bash
  psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d template1 -c "SELECT anon.init();"
  ```
- [ ] **13.5** Update `initdb/04_permissions.sql`:
  - GRANT USAGE ON SCHEMA anon TO role_developer
  - GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA anon TO role_developer
  - ALTER DEFAULT PRIVILEGES … in schema anon
- [ ] **13.6** Reset and verify:
  - `\dx` shows `anon`
  - As developer: `SELECT anon.partial_email('foo@bar.com', 2, '*****', 2);` returns masked email
- [ ] **13.7** Update README: pg_anonymizer usage with masking example
- [ ] **13.8** Commit: `feat(s13): pg_anonymizer with developer access`

---

## Slice 14 — CLI Tools (pgcli, pg_activity, pgbadger, pspg, sqitch, pgloader)

**Goal:** add all CLI tools to the image.

- [ ] **14.1** Install pgcli + pg_activity via pip (pin versions)
- [ ] **14.2** Install pspg (PGDG/EPEL/source)
- [ ] **14.3** Install pgbadger (PGDG/EPEL/Perl)
- [ ] **14.4** Install sqitch (PGDG package or `cpanm App::Sqitch`)
- [ ] **14.5** Install pgloader — handle arch:
  - On amd64 (`TARGETARCH=amd64`): install PGDG `pgloader` RPM directly
  - On arm64 (`TARGETARCH=arm64`): install via QEMU emulation OR source build
  - Document that on arm64 pgloader runs slower under emulation
- [ ] **14.6** Set `ENV PAGER=pspg`
- [ ] **14.7** Run hadolint
- [ ] **14.8** Build on both architectures (or at least document amd64 was tested)
- [ ] **14.9** Verify each CLI runs: `pgcli --version`, `pg_activity --version`, `pspg --version`, `pgbadger --version`, `sqitch --version`, `pgloader --version`, `pgbench --version`
- [ ] **14.10** Add `scripts/pgcli-admin.sh`, `scripts/pgbadger-report.sh`
- [ ] **14.11** Update README: list tools + one-line description + invocation example for each
- [ ] **14.12** Commit: `feat(s14): cli tools (pgcli, pg_activity, pgbadger, pspg, sqitch, pgloader)`

---

## Slice 15 — `.psqlrc` + UX polish + Final README

**Goal:** in-container UX polish and documentation completeness.

- [ ] **15.1** Write `config/psqlrc` (heavily commented):
  ```
  -- Show timing for every query
  \timing on
  -- Display NULL as a visible glyph rather than empty
  \pset null '∅'
  -- Cleaner prompt: user@db (transaction marker)#
  \set PROMPT1 '%n@%/%R%# '
  \set PROMPT2 '  > '
  -- Use pspg as pager (set globally via PAGER env, but explicit here too)
  \setenv PAGER pspg
  -- Verbose error reporting
  \set VERBOSITY verbose
  -- Default to expanded display only when output is wide
  \x auto
  -- History per database (one history file per db, kept under ~/.psql_history.<db>)
  \set HISTFILE ~/.psql_history- :DBNAME
  -- Don't store duplicate history entries
  \set HISTCONTROL ignoredups
  ```
- [ ] **15.2** Mount or copy `.psqlrc` to `/var/lib/pgsql/.psqlrc` in image, owned by postgres user
- [ ] **15.3** Test: `\timing` is on automatically when connecting
- [ ] **15.4** Test: NULL displayed as `∅`
- [ ] **15.5** README: comprehensive final pass — covering all sections below
- [ ] **15.6** Commit: `feat(s15): psqlrc and ux polish`

### Required README Sections (final state)
- [ ] Title + one-paragraph description
- [ ] Prerequisites (Docker, docker compose v2, ~1GB disk)
- [ ] Quick start (5 commands max)
- [ ] **Default users + passwords table** (admin/admin, developer/developer, app/app — note this is dev-only, override via .env)
- [ ] Connection examples for each user (psql + pgcli)
- [ ] Volume layout
- [ ] Resetting the environment (full procedure)
- [ ] Updating config without rebuild
- [ ] Architecture support note (auto-detect; pgloader emulation on arm64)
- [ ] **Sample `docker-compose.override.yml`** snippet showing how a downstream project consumes this
- [ ] Permissions matrix (admin/developer/app columns × CONNECT/SCHEMA USAGE/CREATE/DML/DDL/RLS rows)
- [ ] **Reference to `.psqlrc`** (where it is, what it does)
- [ ] Extension list with one usage example each:
  - pg_stat_statements, auto_explain, pg_cron (incl. cross-db schedule_in_database example), pgaudit (where logs go, sample entry), pg_partman, pg_squeeze, pg_buffercache, pg_prewarm, hypopg, pg_hint_plan, wal2json, plpython3u, pgtap, tablefunc, pg_anonymizer
- [ ] CLI tools list with example invocation each
- [ ] **pgbench prerequisites** (note: needs `pgbench -i` as admin or pre-existing tables; app user cannot init)
- [ ] **pg_cron access doc** — exactly who has USAGE on cron schema, who can call `cron.schedule_in_database`, example
- [ ] Logging guide (where stderr goes vs JSON file, how to use scripts/logs.sh, pgbadger report)
- [ ] Troubleshooting (common errors)

---

## Slice 16 — Final Integration Test

- [ ] **16.1** Full reset: `scripts/reset.sh`
- [ ] **16.2** All extensions present in fresh DB (`CREATE DATABASE foo; \c foo; \dx`)
- [ ] **16.3** All three users connect with documented default passwords
- [ ] **16.4** RLS enforced for developer and app
- [ ] **16.5** Logs in both formats (stderr + JSON)
- [ ] **16.6** pg_cron cross-DB job runs successfully
- [ ] **16.7** pgaudit captures all-user queries
- [ ] **16.8** pg_anonymizer masking works for developer
- [ ] **16.9** Data persists across `down/up`
- [ ] **16.10** Config edit takes effect after restart, no rebuild
- [ ] **16.11** `pgbadger /var/log/postgresql/*.log` produces an HTML report
- [ ] **16.12** hadolint clean
- [ ] **16.13** Final commit: `chore(s16): final integration test pass`

---

## Cross-Cutting Risks & Resolutions

| # | Risk | Resolved In | Mitigation |
|---|------|------------|-----------|
| R1 | pg_anonymizer no PGDG RPM for OL9/PG17 | S13 | Source build from DALIBO repo |
| R2 | pgtap no PGDG package for PG17 | S12 | pgxn install or source |
| R3 | sqitch missing in OL9 default repos | S14 | `cpanm App::Sqitch` fallback |
| R4 | pgloader x86_64-only on PGDG | S14 | Emulation on arm64 OR source build |
| R5 | pspg may not be in OL9 default repos | S14 | EPEL or source |
| R6 | plugin_debugger.so name verification | S11 | Verify with `find /usr/pgsql-17/lib -name '*.so'` after install |
| R7 | Init scripts only run on first boot | S3 | Documented reset workflow in README |
| R8 | auto_explain ≠ CREATE EXTENSION | S7 | Preload only; do NOT add to 00_extensions.sql |
| R9 | pg_anonymizer needs `SELECT anon.init()` | S13 | Separate `01_anon_init.sh` script |
| R10 | Extension version pinning churn | All | Pin via build args; document upgrade procedure |
