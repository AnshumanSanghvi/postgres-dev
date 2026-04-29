# PostgreSQL Dev Environment — Implementation Plan

## Goal
A reusable, dockerized PostgreSQL 17 development environment built on OracleLinux 9 Slim,
designed to mirror production RHEL9/OL9 environments. Consumed via `docker compose` by any
project as a sibling checkout or git submodule. Built iteratively in vertical slices —
each slice produces a working, tested, committed increment.

---

## Architecture Decisions (Final)

### Base & Version
- Image: `oraclelinux:9-slim` (multi-arch — pulled per host architecture automatically)
- PostgreSQL: 17 (from official PGDG RHEL9 RPM repo)
- Port (host): `5499`
- Locale: `C.UTF-8`
- Encoding: `UTF8`
- Timezone: `UTC` (container `TZ=UTC`, postgres `timezone='UTC'`, `log_timezone='UTC'`)

### Multi-architecture Support
- Dockerfile uses `TARGETARCH` build arg to handle arch-specific package availability
- All packages from PGDG repos that exist for both arm64 and amd64 install normally
- `pgloader` is x86_64-only on PGDG → on aarch64 we install via QEMU emulation layer or
  build from source; either way the resulting image runs natively
- Compose does NOT pin `platform:` — Docker chooses the right manifest per host

### Authentication
- Method: `scram-sha-256` for all connections
- SSL: disabled (dev environment)

### Memory Budget — enforced via compose limits
- Container limit: 512MB (`mem_limit: 512m`)
- `shared_buffers = 128MB` (25%)
- `effective_cache_size = 384MB` (75%)
- `work_mem = 4MB`
- `maintenance_work_mem = 64MB`
- `max_connections = 50`

### Statement & Connection Timeouts (dev safety)
- `statement_timeout = 60s` — surfaces runaway queries
- `idle_in_transaction_session_timeout = 5min` — kills zombie transactions
- `lock_timeout = 10s`

### WAL Configuration (dev-sized)
- `max_wal_size = 1GB`
- `min_wal_size = 80MB`
- `wal_keep_size = 0`
- `wal_level = logical` (so wal2json / logical replication work)

### Logging
- `log_destination = 'stderr,jsonlog'`
- `logging_collector = on`
- stderr → human-readable text (visible via `docker logs`)
- file → JSON format in `/var/log/postgresql/`
- `log_min_duration_statement = 0` (log all queries — dev only)
- `log_rotation_age = 1d`
- `log_rotation_size = 100MB`
- `log_truncate_on_rotation = on`
- `log_lock_waits = on`, `deadlock_timeout = 1s`
- `log_line_prefix = '%m [%p] %q%u@%d '`

### shared_preload_libraries (load order)
1. `pg_stat_statements`
2. `auto_explain`
3. `pg_cron`
4. `pgaudit`
5. `pg_partman_bgw`
6. `plugin_debugger` (pldebugger)

### Healthcheck
Real-query-based, gated past initdb completion:
```
test: ["CMD-SHELL", "psql -U admin -d postgres -p 5499 -c 'SELECT 1' || exit 1"]
interval: 10s
timeout: 5s
retries: 5
start_period: 60s
```

### Schemas
- `public` — extensions only; CREATE revoked from PUBLIC
- `app` — application tables, owned by `admin`
- `search_path` set at database level (on `template1`, inherited by all new DBs):
  `ALTER DATABASE template1 SET search_path = app, public`

### Role Hierarchy
```
GROUP ROLES (no login):     LOGIN USERS:
  role_admin   ──────────>    admin       (SUPERUSER, CREATEDB, CREATEROLE, REPLICATION)
  role_developer ────────>    developer   (NOSUPERUSER, NOCREATEDB, NOBYPASSRLS, pg_monitor, pg_read_all_stats)
  role_app     ──────────>    app         (NOSUPERUSER, NOCREATEDB, NOBYPASSRLS, conn limit 50)
```

- Admin owns all schema objects; runs all migrations
- Developer: USAGE on all schemas, DML on all tables, can call pg_anonymizer masking functions, RLS enforced, no DDL
- App: USAGE on `app` schema only, DML on `app` tables, subject to RLS, no DDL, no TRUNCATE
- DEFAULT PRIVILEGES set on admin role so future objects auto-grant correctly

### Password Injection Strategy
SQL files cannot read env vars. We use `.sh` init scripts that call `psql -v` to inject
`$POSTGRES_ADMIN_PASSWORD`, `$POSTGRES_DEVELOPER_PASSWORD`, `$POSTGRES_APP_PASSWORD` as
psql variables, then run the actual SQL via `\i` with `:'admin_pw'` substitution.

### pg_cron Multi-Database
- Metadata DB: `postgres`
- Cross-database jobs: `cron.schedule_in_database()`
- `cron.use_background_workers = on`
- `pg_cron_admin` role granted to `role_developer` so devs can schedule jobs
- Document who has USAGE on `cron` schema (default: only superusers and grantees)

### pgaudit
- `pgaudit.log = 'all'`, `log_catalog = on`, `log_relation = on`, `log_statement_once = off`
- Logs all statement classes for all users (admin, developer, app)
- Output → postgres log (stderr text + JSON file)

### pg_anonymizer
- `CREATE EXTENSION anon` followed by `SELECT anon.init()` (loads fake-data dictionaries)
- Developer granted USAGE on schema `anon` and EXECUTE on its functions

### Extension Version Pinning
All PGDG extension packages installed with explicit version pins
(e.g., `pgaudit17_17-17.0-1PGDG.rhel9`). Pinning is documented in the Dockerfile via
build args so updates are intentional, not accidental.

### Volume Mounts
```
./volumes/data/    →  /var/lib/pgsql/data          (PGDATA)
./volumes/logs/    →  /var/log/postgresql           (log files)
./config/          →  /etc/postgresql               (postgresql.conf, pg_hba.conf, .psqlrc)
./initdb/          →  /docker-entrypoint-initdb.d   (init scripts; first-boot only)
```

### Container UX Polish
- `.psqlrc` baked into image at `/var/lib/pgsql/.psqlrc` — heavily commented; referenced in README
- `ENV PAGER=pspg` so psql/pgcli use it automatically
- `ENV LESS=-iMRSx4` for sane `less` behavior

---

## Repo Structure
```
postgres-dev/
├── config/
│   ├── postgresql.conf
│   ├── pg_hba.conf
│   └── psqlrc                   # commented .psqlrc, mounted as /var/lib/pgsql/.psqlrc
├── initdb/
│   ├── 00_extensions.sql        # CREATE EXTENSION in template1
│   ├── 01_anon_init.sh          # SELECT anon.init() (post-install)
│   ├── 02_schemas.sql
│   ├── 03_roles.sh              # creates roles + users with env-var passwords
│   ├── 04_permissions.sql
│   ├── 05_pgaudit.sql
│   └── 06_pg_cron.sql
├── scripts/
│   ├── up.sh                    # docker compose up + wait for healthy
│   ├── down.sh                  # docker compose down
│   ├── reset.sh                 # full reset: down + remove volumes/data + up
│   ├── psql-admin.sh            # psql as admin
│   ├── psql-developer.sh        # psql as developer
│   ├── psql-app.sh              # psql as app
│   ├── pgcli-admin.sh           # pgcli as admin
│   ├── logs.sh                  # tail JSON logs with jq pretty-print
│   ├── backup.sh                # pg_dump convenience
│   ├── restore.sh               # pg_restore convenience
│   ├── pgbadger-report.sh       # generate pgbadger HTML from logs
│   └── lint-dockerfile.sh       # run hadolint
├── volumes/                     # gitignored
│   ├── data/
│   └── logs/
├── Dockerfile
├── compose.yml
├── .env.example
├── .gitignore
├── .hadolint.yaml               # hadolint config
├── PLAN.md
├── TASKS.md
└── README.md
```

---

## Extensions (Final List)

### From `postgresql17-contrib`
- pg_stat_statements, auto_explain (preload only — no CREATE EXTENSION), pg_buffercache, pg_prewarm
- tablefunc, plpython3u

### Separate PGDG packages (RHEL9, version-pinned)
| Package        | Extension      |
|----------------|----------------|
| pg_cron_17     | pg_cron        |
| pgaudit17_17   | pgaudit        |
| pg_partman17   | pg_partman     |
| pg_squeeze17   | pg_squeeze     |
| hypopg_17      | hypopg         |
| pg_hint_plan_17 | pg_hint_plan  |
| wal2json17     | wal2json       |
| pldebugger17   | pldebugger     |

### Special install
- `pgtap` — likely PGDG `pgtap_17`; fall back to source from theory/pgtap if unavailable
- `pg_anonymizer` — DALIBO RPM if available; else source build; init via `SELECT anon.init()`

### CLI tools in image
- `pgcli`, `pg_activity` (pip)
- `pgbadger` (PGDG or EPEL or Perl)
- `pspg` (PGDG extras / EPEL / source)
- `sqitch` (PGDG / cpanm App::Sqitch)
- `pgloader` (PGDG x86_64; emulation/source on arm64)
- `pgbench` (built into postgresql17 server package)

### OS utilities
procps-ng, less, vim-minimal, iputils, bind-utils, lsof, jq, tar, gzip, findutils, strace, curl

---

## Iterative Build Strategy

Work proceeds in **vertical slices**. Each slice is self-contained: it builds, runs, and
verifies a thin working subset. After each slice:
1. Run `docker build` and the slice-specific test commands
2. Update README.md to reflect what's now usable
3. `git commit` with a descriptive message

This produces frequent, testable checkpoints rather than one giant build at the end.
TASKS.md lists all 15 slices in order.

---

## Working Agreements (apply throughout)

- **Test before commit** — every slice ends with the container running and the slice's
  verification commands passing.
- **README is a deliverable, not an afterthought** — every slice updates the README to
  reflect new capability.
- **Passwords belong in README** — this is a dev environment. Default passwords are
  documented openly. Users override via `.env` if they want different ones.
- **Pin everything** — extension package versions, base image digest where practical,
  pip versions for pgcli/pg_activity. Reproducibility > "latest".
- **Lint the Dockerfile** — `scripts/lint-dockerfile.sh` runs hadolint; should pass on
  every slice.
- **No image publishing** — git repo + docker compose only.
