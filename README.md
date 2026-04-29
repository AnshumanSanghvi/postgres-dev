# Postgres Dev Environment

A reusable, dockerized PostgreSQL 17 development environment built on OracleLinux 9
Slim. Designed to mirror production RHEL9/OL9 environments, with a curated set of
extensions, dev-tuned configuration, and CLI tooling baked in.

**Status:** S12 — all extensions installed (14 total). See
[TASKS.md](TASKS.md) for slice progress.

---

## Prerequisites
- Docker Desktop (Mac/Windows) or Docker Engine 24+ (Linux)
- Docker Compose v2 (`docker compose` subcommand)
- ~1 GB disk for image + data

## Quick start
```bash
git clone <this repo> postgres-dev && cd postgres-dev
cp .env.example .env          # adjust passwords if you want
scripts/up.sh                 # builds image, starts container, waits for healthy
PGPASSWORD=postgres psql -h localhost -p 5499 -U postgres
```

When done:
```bash
scripts/down.sh               # stops container; data and logs preserved
scripts/reset.sh              # full reset: stop + wipe volumes + reinit
```

## What works today (after S3)
- PostgreSQL 17 server + contrib on `oraclelinux:9-slim`, multi-arch (amd64 + arm64)
- Locale `C.UTF-8`, encoding `UTF8`, timezone `UTC`
- `scram-sha-256` authentication, port `5499`, SSL disabled
- docker compose orchestration with bind-mounted `data/`, `logs/`, `config/`
- 512 MiB memory limit enforced
- Healthcheck via `pg_isready` (will switch to real-query check once admin user exists in S9)
- Helper scripts: `up.sh`, `down.sh`, `reset.sh`
- Data persists across `down/up`; container survives Docker restart

## Volume layout
| Host path           | Container path                | Purpose                          |
|---------------------|-------------------------------|----------------------------------|
| `./volumes/data/`   | `/var/lib/pgsql/data`         | PGDATA (cluster files)           |
| `./volumes/logs/`   | `/var/log/postgresql`         | postgres log files (S6+)         |
| `./config/`         | `/etc/postgresql` (read-only) | postgresql.conf, pg_hba.conf     |
| `./initdb/`         | `/docker-entrypoint-initdb.d` (read-only) | first-boot init scripts (S5+) |

## Resetting the environment
Init scripts in `initdb/` only run on first boot (when PGDATA is empty). To re-run
them after edits:
```bash
scripts/reset.sh              # confirms before deleting
scripts/up.sh                 # rebuilds and reinitializes
```

## Users & roles (S9)

Three login users, each backed by a group role for cleaner privilege
management. **Default passwords below are dev-only — override via `.env`.**

| User        | Password    | Role attributes                                                            | Use                              |
|-------------|-------------|----------------------------------------------------------------------------|----------------------------------|
| `admin`     | `admin`     | SUPERUSER, CREATEDB, CREATEROLE, REPLICATION, BYPASSRLS                    | DBA tasks, migrations, owns objs |
| `developer` | `developer` | NOSUPERUSER, RLS enforced, member of `pg_monitor` + `pg_read_all_stats`    | day-to-day dev queries           |
| `app`       | `app`       | NOSUPERUSER, RLS enforced, conn limit 50                                   | application connections          |

Group roles `role_developer` and `role_app` are NOLOGIN containers for the
permissions wired up in S10.

Connect via helper scripts (read passwords from `.env` automatically):
```bash
scripts/psql-admin.sh
scripts/psql-developer.sh
scripts/psql-app.sh
```

Or directly:
```bash
PGPASSWORD=admin psql -h localhost -p 5499 -U admin -d postgres
```

**Override passwords:** edit `.env` (gitignored) before first `up.sh`. After
first boot the passwords are baked into the cluster — to change them, either
`scripts/reset.sh` (wipes data) or `ALTER ROLE admin PASSWORD '...'` etc.

## Extensions

### pg_stat_statements (S7)
Tracks aggregate query performance. Loaded via `shared_preload_libraries` and
created in `template1` so every database inherits it.

```sql
SELECT calls, mean_exec_time::int AS mean_ms, substr(query,1,80)
FROM pg_stat_statements
ORDER BY mean_exec_time DESC
LIMIT 10;
```

Reset accumulated stats: `SELECT pg_stat_statements_reset();` (admin only —
`developer` has read access via `pg_read_all_stats`).

### auto_explain (S7)
Logs the EXPLAIN plan for any query that runs ≥ 1s. Output goes to the
postgres log files (`volumes/logs/postgresql-*.json`) in JSON format —
filterable with `jq`. No `CREATE EXTENSION` needed; preload-only.

```bash
# Find auto_explain entries from today's JSON log:
jq -r 'select(.message | startswith("duration:")) | .message' \
  volumes/logs/postgresql-$(date -u +%Y-%m-%d).json
```

Tunable in `config/postgresql.conf` (`auto_explain.log_min_duration`, etc.).

### pg_cron (S11)
Cron-style job scheduler inside postgres. Metadata lives in the `postgres`
database (`cron.database_name`). Jobs can run in any database via
`cron.schedule_in_database()`.

`role_developer` has full DML on `cron.job` and EXECUTE on the cron schema, so
developers can schedule jobs without superuser:

```sql
-- As developer, schedule a job in the postgres database:
SELECT cron.schedule('cleanup-temp', '0 3 * * *', $$ DELETE FROM app.tmp WHERE created_at < now() - interval '7 days' $$);

-- As developer, schedule a job in any database (cross-database):
SELECT cron.schedule_in_database('refresh-mv', '*/10 * * * *', $$ REFRESH MATERIALIZED VIEW app.daily_summary $$, 'analytics_db');

-- See your jobs:
SELECT * FROM cron.job;
SELECT * FROM cron.job_run_details ORDER BY start_time DESC LIMIT 10;
```

### pgaudit (S11)
Logs every statement executed by every user, in addition to the normal postgres
log line. Output goes to both stderr and the JSON log file with `AUDIT:` prefix.

Filter to audit entries only:
```bash
jq -r 'select(.message | startswith("AUDIT:")) | .message' \
  volumes/logs/postgresql-$(date -u +%Y-%m-%d).json
```

### pg_partman (S11)
Time-based and serial-based partitioned table management. Background worker
(`pg_partman_bgw`) runs maintenance every hour as the `admin` user (configured
in `postgresql.conf`).

```sql
-- Create a partitioned parent table, then let pg_partman manage children:
CREATE TABLE app.events (id bigserial, ts timestamptz NOT NULL, payload jsonb)
  PARTITION BY RANGE (ts);
SELECT partman.create_parent('app.events', 'ts', 'native', 'daily');
```

### pldebugger (S11)
Server-side debugging API for PL/pgSQL functions. Loaded via
`shared_preload_libraries = '...,plugin_debugger'` and exposed as the
`pldbgapi` extension. Use a client like pgAdmin or DBeaver to step through
function execution.

### pg_buffercache + pg_prewarm (S12)
Inspect and prewarm the shared buffer cache.
```sql
SELECT count(*) AS buffers FROM pg_buffercache;            -- inspect
SELECT pg_prewarm('app.large_table');                      -- preload into cache
```

### pg_squeeze (S12)
Online table compaction (removes bloat without exclusive locks).
```sql
SELECT squeeze.squeeze_table('app', 'big_table', NULL, NULL, NULL);
```

### hypopg (S12)
Test indexes hypothetically — no real index is built, but the planner pretends
it exists for `EXPLAIN`. Iteration speed for index design.
```sql
SELECT hypopg_create_index('CREATE INDEX ON app.orders(customer_id)');
EXPLAIN SELECT * FROM app.orders WHERE customer_id = 42;   -- planner uses hypothetical
SELECT hypopg_reset();                                     -- discard all hypotheticals
```

### pg_hint_plan (S12)
Force specific query plans via SQL comment hints. Auto-loaded per session via
`session_preload_libraries`.
```sql
/*+ SeqScan(t) */ SELECT * FROM app.t WHERE id = 42;
/*+ IndexScan(t orders_customer_idx) */ SELECT * FROM app.orders t;
```

### wal2json (S12)
WAL-to-JSON output plugin for logical replication / change data capture. Not a
`CREATE EXTENSION` — used at slot creation time:
```sql
SELECT pg_create_logical_replication_slot('cdc_slot', 'wal2json');
SELECT * FROM pg_logical_slot_peek_changes('cdc_slot', NULL, NULL);
SELECT pg_drop_replication_slot('cdc_slot');
```

### plpython3u (S12)
Untrusted Python procedural language. Superuser-only to create functions.
```sql
DO $$ plpy.notice('hello from python ' || sys.version) $$ LANGUAGE plpython3u;
```

### tablefunc (S12)
Pivot tables and `connectby()` recursive queries.
```sql
SELECT * FROM crosstab($$
  VALUES ('row1','a',1),('row1','b',2),('row2','a',3),('row2','b',4)
$$) AS ct(rowname text, a int, b int);
```

### pgtap (S12)
Unit testing framework for SQL.
```sql
BEGIN;
SELECT plan(3);
SELECT has_table('app','orders','orders table exists');
SELECT col_not_null('app','orders','id','id is NOT NULL');
SELECT pass('arbitrary assertion');
SELECT * FROM finish();
ROLLBACK;
```

## Permissions matrix (S10)

| Action                                  | admin | developer | app   |
|-----------------------------------------|-------|-----------|-------|
| CONNECT to databases                    | ✓     | ✓         | ✓     |
| USAGE on `app` schema                   | ✓     | ✓         | ✓     |
| USAGE on `public` schema (for extns)    | ✓     | ✓         | ✓     |
| CREATE in `app` (DDL)                   | ✓     | ✗         | ✗     |
| CREATE in `public` (DDL)                | ✓     | ✗         | ✗     |
| SELECT/INSERT/UPDATE/DELETE on `app.*`  | ✓     | ✓         | ✓     |
| TRUNCATE on `app.*`                     | ✓     | ✓         | ✗     |
| SELECT on `public.*` (non-extn tables)  | ✓     | ✓         | ✗     |
| Use sequences in `app`                  | ✓     | ✓         | ✓ (USAGE only) |
| BYPASSRLS                               | ✓     | ✗         | ✗     |
| EXPLAIN/pg_stat_*                       | ✓     | ✓         | ✗     |
| pg_anonymizer masking functions         | ✓     | ✓ (S13)   | ✗     |

**DEFAULT PRIVILEGES** are set on the `admin` role: every table/sequence/function
admin creates from now on auto-grants the rights above to `role_developer` and
`role_app`. So a fresh `CREATE TABLE app.foo (...)` is immediately usable by
developer and app without an explicit GRANT.

## Schemas (S8)
| Schema   | Purpose                                                      |
|----------|--------------------------------------------------------------|
| `app`    | application tables; default target for ad-hoc work           |
| `public` | extensions only — `CREATE` revoked from PUBLIC; `USAGE` kept |

`search_path` is `"$user", app, public` cluster-wide (in `postgresql.conf`),
so every database — existing and future — inherits it. The `app` schema is
created in `template1`, so any database created via `CREATE DATABASE foo`
also gets it.

To add per-project schemas, run `CREATE SCHEMA myschema` in your database;
adjust search_path on a per-database or per-role basis if needed.

## Logs (S6)
Postgres writes every event in two formats simultaneously:

| File                                                    | Format     | Use                                     |
|---------------------------------------------------------|------------|-----------------------------------------|
| `volumes/logs/postgresql-YYYY-MM-DD.log`                | Plain text | `tail -f` for human reading             |
| `volumes/logs/postgresql-YYYY-MM-DD.json`               | JSON       | `jq`-friendly; pipe to log aggregators  |

Helper:
```bash
scripts/logs.sh        # tail -F today's JSON log, jq-formatted
scripts/logs.sh 50     # last 50 lines instead of follow
```

Rotation: daily or 100 MB (whichever first), `log_truncate_on_rotation=on`.
Live `docker logs postgres-dev` shows entrypoint output and the collector handoff
at startup; thereafter postgres' stderr is captured by the logging collector and
written to the files above.

## Tuned settings (after S5)
| Setting                              | Value     | Why                                       |
|--------------------------------------|-----------|-------------------------------------------|
| `shared_buffers`                     | 128 MB    | ~25% of 512 MiB container                 |
| `effective_cache_size`               | 384 MB    | ~75% (planner hint, not allocated)        |
| `work_mem`                           | 4 MB      | per-sort/hash; conservative for dev       |
| `maintenance_work_mem`               | 64 MB     | vacuum, create index                      |
| `max_connections`                    | 50        | matches dev workload                      |
| `statement_timeout`                  | 60 s      | abort runaway queries                     |
| `idle_in_transaction_session_timeout`| 5 min     | kill zombie transactions                  |
| `lock_timeout`                       | 10 s      | cap waits on row/table locks              |
| `wal_level`                          | logical   | required for wal2json / logical repl      |
| `max_wal_size` / `min_wal_size`      | 1 GB / 80 MB | dev-sized to limit disk usage         |

To override per-project, edit `config/postgresql.conf` and `docker compose restart postgres`.

## Editing config without rebuilding
`./config/` is mounted read-only. After editing `postgresql.conf` or `pg_hba.conf`:
```bash
docker compose restart postgres
```
No image rebuild needed.

## How the entrypoint handles bind-mount permissions
Bind mounts on Docker Desktop for Mac (virtiofs) restrict `chown` across the
host/container boundary. The entrypoint detects the host UID/GID from the
bind-mounted PGDATA directory and aligns the in-container `postgres` user to
match — no chown required on Mac, and a no-op on Linux where the chown succeeds
naturally.

## Helper scripts
| Script                     | Purpose                                       |
|----------------------------|-----------------------------------------------|
| `scripts/up.sh`            | build + start + wait for healthy              |
| `scripts/down.sh`          | stop the container (preserves data)           |
| `scripts/reset.sh`         | wipe data and logs, force reinit on next up   |
| `scripts/lint-dockerfile.sh` | run hadolint against Dockerfile             |
| `scripts/logs.sh [N]`      | tail JSON logs (jq-formatted)                 |
| `scripts/psql-admin.sh`    | open psql as `admin`                          |
| `scripts/psql-developer.sh`| open psql as `developer`                      |
| `scripts/psql-app.sh`      | open psql as `app`                            |

## In-container utilities (added in S4)
For ad-hoc debugging inside the container:

| Tool      | Use                                                    |
|-----------|--------------------------------------------------------|
| `ps`/`top`| process inspection (procps-ng)                         |
| `less`    | paged log/file viewing (`LESS=-iMRSx4` set in image)   |
| `vi`      | edit configs in-container (`vim-minimal` package)      |
| `ping`    | basic reachability (`iputils`)                         |
| `dig`     | DNS lookups (`bind-utils`)                             |
| `lsof`    | open files/sockets per process                         |
| `jq`      | inspect JSON output, parse JSONB query results         |
| `tar` / `gzip` | exports for `pg_dump`                             |
| `find`    | locate files (`findutils`)                             |
| `strace`  | last-resort syscall tracing                            |
| `curl`    | network reachability tests                             |

Note: package is `vim-minimal`, which provides `vi` (no `vim` binary).

---

## Documents
- [PLAN.md](PLAN.md) — architecture and design decisions
- [TASKS.md](TASKS.md) — slice-by-slice implementation tracker
