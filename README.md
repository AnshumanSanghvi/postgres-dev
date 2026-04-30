# Postgres Dev Environment

A reusable, dockerized PostgreSQL 17 development environment built on
OracleLinux 9 Slim. Designed to mirror production RHEL9/OL9 environments,
with a curated set of extensions, dev-tuned configuration, and CLI tooling
baked in.

**Status:** S15 — `.psqlrc` and final UX polish complete.

---

> **New here?** Once the environment is running, jump to
> [`docs/playbook.md`](docs/playbook.md) for scenario-based recipes that show
> what each extension and tool actually unlocks day-to-day.

## Table of contents
- [Prerequisites](#prerequisites)
- [Quick start](#quick-start)
- [Default users & passwords](#users--roles)
- [Connecting](#connecting)
- [Volume layout](#volume-layout)
- [Resetting the environment](#resetting-the-environment)
- [Editing config without rebuilding](#editing-config-without-rebuilding)
- [Architecture support](#architecture-support)
- [Consuming this in another project](#consuming-this-in-another-project)
- [Permissions matrix](#permissions-matrix-s10)
- [`.psqlrc` (interactive psql defaults)](#psqlrc-s15)
- [Schemas](#schemas-s8)
- [Tuned settings](#tuned-settings-after-s5)
- [Logs](#logs-s6)
- [Extensions](#extensions)
- [CLI tools](#cli-tools-s14)
- [Helper scripts](#helper-scripts)
- [In-container utilities](#in-container-utilities-added-in-s4)
- [Troubleshooting](#troubleshooting)

---

## Prerequisites
- Docker Desktop (Mac/Windows) or Docker Engine 24+ (Linux)
- Docker Compose v2 (`docker compose` subcommand)
- ~1.5 GB disk for image + data

## Quick start
```bash
git clone <this repo> postgres-dev && cd postgres-dev
cp .env.example .env          # adjust passwords if you want
scripts/up.sh                 # builds image, starts container, waits for healthy
scripts/psql-admin.sh         # opens psql as admin (.psqlrc auto-applied)
```

When done:
```bash
scripts/down.sh               # stop the container; data and logs preserved
scripts/reset.sh              # full reset: stop + wipe volumes + reinit on next up
```

---

## Users & roles

**Default passwords below are dev-only — override via `.env` before first boot.**

| User        | Password    | Role attributes                                                            | Use                              |
|-------------|-------------|----------------------------------------------------------------------------|----------------------------------|
| `admin`     | `admin`     | SUPERUSER, CREATEDB, CREATEROLE, REPLICATION, BYPASSRLS                    | DBA tasks, migrations, owns objs |
| `developer` | `developer` | NOSUPERUSER, RLS enforced, member of `pg_monitor` + `pg_read_all_stats`    | day-to-day dev queries           |
| `app`       | `app`       | NOSUPERUSER, RLS enforced, conn limit 50                                   | application connections          |

Group roles `role_developer` and `role_app` are NOLOGIN containers for the
permissions wired in `initdb/04_permissions.sql`.

To change passwords:
1. **Before first boot**: edit `.env`, then `scripts/up.sh`.
2. **After first boot**: `ALTER ROLE admin PASSWORD '...'` (or `scripts/reset.sh` to wipe).

---

## Connecting

Helper scripts read passwords from `.env` automatically:
```bash
scripts/psql-admin.sh
scripts/psql-developer.sh
scripts/psql-app.sh
```

Or directly from the host:
```bash
PGPASSWORD=admin psql -h localhost -p 5499 -U admin -d postgres
```

Or from inside the container (gets full `.psqlrc` UX — pspg pager, NULL as ∅,
prompt with timing, macro shortcuts):
```bash
docker exec -it -e PGPASSWORD=admin postgres-dev psql -U admin -p 5499 -d postgres
```

---

## Volume layout
| Host path           | Container path                            | Purpose                          |
|---------------------|-------------------------------------------|----------------------------------|
| `./volumes/data/`   | `/var/lib/pgsql/data`                     | PGDATA (cluster files)           |
| `./volumes/logs/`   | `/var/log/postgresql`                     | text + JSON log files            |
| `./config/`         | `/etc/postgresql` (read-only)             | `postgresql.conf`, `pg_hba.conf` |
| `./initdb/`         | `/docker-entrypoint-initdb.d` (read-only) | first-boot init scripts          |

PGDATA is a *subdirectory* of the bind mount (`pgdata/`) so `.gitkeep` and
similar files at the mount root don't trip `initdb`'s "directory not empty"
check.

---

## Resetting the environment

Init scripts in `initdb/` only run on first boot (when PGDATA is empty). To
re-run them after edits:
```bash
scripts/reset.sh              # confirms before wiping
scripts/up.sh
```

`reset.sh` deletes data via a one-shot helper container (the host can't
`rm -rf` files owned by the container's postgres UID).

---

## Editing config without rebuilding
`./config/` is mounted read-only. After editing `postgresql.conf` or
`pg_hba.conf`:
```bash
docker compose restart postgres
```
No image rebuild needed. Init scripts in `./initdb/` likewise update without
rebuilding, but only re-run after a `reset.sh`.

---

## Architecture support
The image is multi-arch — Docker pulls the matching manifest per host
architecture automatically (no `platform:` pin in `compose.yml`). Verified on
`linux/arm64` (Apple Silicon) and `linux/amd64`.

Bind mounts on Docker Desktop for Mac (virtiofs) restrict `chown` across the
host/container boundary. The entrypoint detects the host UID/GID from the
bind-mounted PGDATA directory and aligns the in-container `postgres` user to
match — no chown required on Mac, and a no-op on Linux.

---

## Consuming this in another project

Two patterns:

### A. Sibling checkout + compose override
Clone this repo as a sibling of your project; in your project, write a
`docker-compose.override.yml` that extends the postgres-dev service:

```yaml
# my-project/docker-compose.override.yml
services:
  postgres:
    extends:
      file: ../postgres-dev/compose.yml
      service: postgres
    # Project-specific overrides:
    environment:
      POSTGRES_DB: my_project_db
    volumes:
      - ./db/initdb:/docker-entrypoint-initdb.d/project:ro  # extra init scripts
```

### B. Direct compose include (Compose v2.20+)
```yaml
# my-project/compose.yml
include:
  - ../postgres-dev/compose.yml
services:
  app:
    depends_on:
      postgres:
        condition: service_healthy
```

Either way: edit `.env` in `postgres-dev/` to set passwords, then `up.sh`
from there (or via your own orchestration).

---

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
| Schedule pg_cron jobs                   | ✓     | ✓         | ✗     |

`DEFAULT PRIVILEGES` are set on the `admin` role — every table/sequence/function
admin creates auto-grants the right access to `role_developer` and `role_app`.
A fresh `CREATE TABLE app.foo (...)` is immediately usable by developer and app
without an explicit GRANT.

---

## `.psqlrc` (S15)
A heavily-commented `.psqlrc` is baked into the image at `/etc/psqlrc` and
loaded via `PSQLRC=/etc/psqlrc`, so every interactive psql session inside the
container picks it up regardless of which user `docker exec` runs as.

Source: [`config/psqlrc`](config/psqlrc) — edit and rebuild to change.

What it sets:
- `\timing on` (wall-clock duration after every query)
- `\pset null '∅'` (NULL is unmistakable)
- `\x auto` (auto-expanded display when rows are wider than terminal)
- Unicode line style with bordered tables
- `VERBOSITY verbose` (full error codes)
- `ON_ERROR_STOP on` (don't power through broken `\i` scripts)
- `PAGER=pspg --no-mouse` (tabular pager)
- Per-database history files (no cross-DB history pollution)

It also defines variable-shortcut macros — invoke as `:name` (no semicolon):
- `:settings` — non-default `pg_settings`
- `:locks` — granted/blocked locks per relation
- `:activity` — pretty-printed `pg_stat_activity`
- `:sizes` — per-table total size, sorted desc
- `:slow` — top 20 slow queries from `pg_stat_statements`

---

## Schemas (S8)

| Schema   | Purpose                                                      |
|----------|--------------------------------------------------------------|
| `app`    | application tables; default target for ad-hoc work           |
| `public` | extensions only — `CREATE` revoked from PUBLIC; `USAGE` kept |

`search_path` is `"$user", app, public` cluster-wide (in `postgresql.conf`),
so every database — existing and future — inherits it. The `app` schema is
created in `template1`, so any database created via `CREATE DATABASE foo`
also gets it.

---

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

Override per-project: edit `config/postgresql.conf`, then `docker compose
restart postgres`.

---

## Logs (S6)
Postgres writes every event in two formats simultaneously:

| File                                                    | Format     | Use                                     |
|---------------------------------------------------------|------------|-----------------------------------------|
| `volumes/logs/postgresql-YYYY-MM-DD.log`                | Plain text | `tail -f` for human reading             |
| `volumes/logs/postgresql-YYYY-MM-DD.json`               | JSON       | `jq`-friendly; pipe to log aggregators  |

```bash
scripts/logs.sh        # tail -F today's JSON log, jq-formatted
scripts/logs.sh 50     # last 50 lines instead of follow
docker exec postgres-dev pgbadger /var/log/postgresql/*.log -o /tmp/r.html  # html report
```

Rotation: daily or 100 MB (whichever first), `log_truncate_on_rotation=on`.

---

## Extensions

14 extensions installed and CREATEd in `template1` so every new database
inherits them. Versions verified on `linux/arm64`.

| Extension            | Purpose                                                |
|----------------------|--------------------------------------------------------|
| pg_stat_statements   | aggregate query performance stats                      |
| auto_explain         | log JSON plans for slow queries (≥ 1 s)                |
| pg_buffercache       | inspect shared buffer cache                            |
| pg_prewarm           | preload tables/indexes into cache                      |
| pg_cron              | job scheduler                                          |
| pgaudit              | structured audit log of every statement                |
| pg_partman           | partition management (time/serial-based)               |
| pg_squeeze           | online table compaction (no exclusive lock)            |
| hypopg               | hypothetical indexes for `EXPLAIN`                     |
| pg_hint_plan         | force query plans via `/*+ … */` comment hints         |
| wal2json             | WAL → JSON output plugin (CDC, logical replication)    |
| plpython3u           | untrusted Python procedural language                   |
| pldebugger (pldbgapi)| step-debugger for PL/pgSQL                             |
| tablefunc            | crosstab pivots, recursive `connectby()`               |
| pgtap                | unit testing framework for SQL                         |

### pg_stat_statements
```sql
SELECT calls, mean_exec_time::int AS mean_ms, substr(query,1,80)
FROM pg_stat_statements
ORDER BY mean_exec_time DESC LIMIT 10;
SELECT pg_stat_statements_reset();    -- admin only; developer has read access
```

### auto_explain
```bash
jq -r 'select(.message | startswith("duration:")) | .message' \
  volumes/logs/postgresql-$(date -u +%Y-%m-%d).json
```

### pg_cron
Metadata lives in the `postgres` database; jobs can run in any database.
**`role_developer` has full DML on `cron.job` and EXECUTE on the `cron`
schema** — developers can schedule jobs without superuser.

```sql
-- in current DB:
SELECT cron.schedule('cleanup-temp', '0 3 * * *',
  $$ DELETE FROM app.tmp WHERE created_at < now() - interval '7 days' $$);

-- cross-database:
SELECT cron.schedule_in_database('refresh-mv', '*/10 * * * *',
  $$ REFRESH MATERIALIZED VIEW app.daily_summary $$, 'analytics_db');

-- inspect:
SELECT * FROM cron.job;
SELECT * FROM cron.job_run_details ORDER BY start_time DESC LIMIT 10;
```

### pgaudit
Logs every statement (DDL/DML/READ/WRITE/FUNCTION/etc.) from every user.
Output goes to both stderr text and the JSON log file with `AUDIT:` prefix.
```bash
jq -r 'select(.message | startswith("AUDIT:")) | .message' \
  volumes/logs/postgresql-$(date -u +%Y-%m-%d).json
```

### pg_partman + bgw
Background worker runs maintenance every hour as `admin`.
```sql
CREATE TABLE app.events (id bigserial, ts timestamptz NOT NULL, payload jsonb)
  PARTITION BY RANGE (ts);
SELECT partman.create_parent('app.events', 'ts', 'native', 'daily');
```

### pg_squeeze
```sql
SELECT squeeze.squeeze_table('app', 'big_table', NULL, NULL, NULL);
```

### pg_buffercache + pg_prewarm
```sql
SELECT count(*) AS buffers FROM pg_buffercache;
SELECT pg_prewarm('app.large_table');
```

### hypopg
Test indexes without building them:
```sql
SELECT hypopg_create_index('CREATE INDEX ON app.orders(customer_id)');
EXPLAIN SELECT * FROM app.orders WHERE customer_id = 42;
SELECT hypopg_reset();
```

### pg_hint_plan
Auto-loaded per session via `session_preload_libraries`.
```sql
/*+ SeqScan(t) */ SELECT * FROM app.t WHERE id = 42;
/*+ IndexScan(t orders_customer_idx) */ SELECT * FROM app.orders t;
```

### wal2json
Output plugin (no `CREATE EXTENSION`):
```sql
SELECT pg_create_logical_replication_slot('cdc_slot', 'wal2json');
SELECT * FROM pg_logical_slot_peek_changes('cdc_slot', NULL, NULL);
SELECT pg_drop_replication_slot('cdc_slot');
```

### plpython3u
Superuser-only; untrusted (full Python access):
```sql
DO $$ plpy.notice('hello from python ' || sys.version) $$ LANGUAGE plpython3u;
```

### pldebugger
Step-debugger API for PL/pgSQL. Use a client like pgAdmin or DBeaver to
attach and step through function execution.

### tablefunc
```sql
SELECT * FROM crosstab($$
  VALUES ('row1','a',1),('row1','b',2),('row2','a',3),('row2','b',4)
$$) AS ct(rowname text, a int, b int);
```

### pgtap
```sql
BEGIN;
SELECT plan(3);
SELECT has_table('app','orders','orders table exists');
SELECT col_not_null('app','orders','id','id is NOT NULL');
SELECT pass('arbitrary assertion');
SELECT * FROM finish();
ROLLBACK;
```

---

## CLI tools (S14)
Baked into the image; accessible via `docker exec`:

| Tool          | Use                                                                                | Invocation                                                            |
|---------------|------------------------------------------------------------------------------------|-----------------------------------------------------------------------|
| `pgcli`       | enhanced psql with autocomplete + syntax highlighting                              | `docker exec -it postgres-dev pgcli -U admin -d postgres`             |
| `pg_activity` | top-style live view of postgres queries                                            | `docker exec -it postgres-dev pg_activity -U admin`                   |
| `pgbadger`    | parse log files into HTML performance reports                                      | `docker exec postgres-dev pgbadger /var/log/postgresql/*.log -o /tmp/report.html` |
| `pspg`        | tabular pager for psql; auto-used via `PAGER=pspg`                                 | (implicit via `.psqlrc`)                                              |
| `sqitch`      | SQL-native database migration management                                           | `docker exec -it postgres-dev sqitch --help`                          |
| `pgbench`     | built-in load testing                                                              | see below                                                             |

### pgbench prerequisites
`pgbench -i` needs CREATE TABLE rights, so initialize as `admin`:
```bash
docker exec -e PGPASSWORD=admin postgres-dev pgbench -i -U admin -p 5499 -d postgres
docker exec -e PGPASSWORD=admin postgres-dev pgbench -c 4 -j 2 -T 10 -U admin -p 5499 postgres
```
Initialization runs as admin; subsequent runs work for any role with DML
(developer or app).

---

## Helper scripts
| Script                       | Purpose                                       |
|------------------------------|-----------------------------------------------|
| `scripts/up.sh`              | build + start + wait for healthy              |
| `scripts/down.sh`            | stop the container (preserves data)           |
| `scripts/reset.sh`           | wipe data and logs, force reinit on next up   |
| `scripts/lint-dockerfile.sh` | run hadolint against Dockerfile               |
| `scripts/logs.sh [N]`        | tail JSON logs (jq-formatted)                 |
| `scripts/psql-admin.sh`      | open psql as `admin`                          |
| `scripts/psql-developer.sh`  | open psql as `developer`                      |
| `scripts/psql-app.sh`        | open psql as `app`                            |

---

## In-container utilities (added in S4)

| Tool      | Use                                                  |
|-----------|------------------------------------------------------|
| `ps`/`top`| process inspection (procps-ng)                       |
| `less`    | paged log/file viewing (`LESS=-iMRSx4` set in image) |
| `vi`      | edit configs in-container (vim-minimal)              |
| `ping`    | basic reachability (iputils)                         |
| `dig`     | DNS lookups (bind-utils)                             |
| `lsof`    | open files/sockets per process                       |
| `jq`      | inspect JSON output, parse JSONB query results       |
| `tar`/`gzip` | exports for `pg_dump`                             |
| `find`    | locate files (findutils)                             |
| `strace`  | last-resort syscall tracing                          |
| `curl`    | network reachability tests                           |

Note: package is `vim-minimal`, which provides `vi` only (no `vim` binary).

---

## Troubleshooting

### Init scripts didn't re-run
By design — they only execute when PGDATA is empty. Run `scripts/reset.sh`.

### `permission denied` for postgres on bind-mount data
Docker Desktop Mac restricts `chown` across virtiofs. The entrypoint handles
this automatically by aligning the in-container postgres UID/GID to the host's.
If you see this error after upgrading Docker Desktop, run `scripts/reset.sh`.

### Connection refused from host
Check the port: it's **5499**, not 5432. The container's healthcheck
authenticates as `admin`, so if your `.env` doesn't have
`POSTGRES_ADMIN_PASSWORD`, the healthcheck will fail and `up.sh` times out.

### "container name `postgres-dev` already in use"
Stale container from a crashed run:
```bash
docker rm -f postgres-dev
docker network rm postgres_default 2>/dev/null
scripts/up.sh
```

### pgbadger says "command not found" inside the container
You may have an older image. Rebuild:
```bash
docker compose build --no-cache
scripts/up.sh
```

### `.psqlrc` settings (timing, ∅, macros) don't appear
`psql -c "..."` deliberately skips `.psqlrc`. Use heredoc or interactive
mode (`docker exec -it ... psql ...`).

---

## Documents
- **[docs/playbook.md](docs/playbook.md)** — scenario-based recipes ("an endpoint got slower
  after deploy", "should I add this index?", "stream changes downstream") that walk through
  the right combination of extensions and tools for each common situation. **Start here once
  the environment is up.**
- [docs/pg_optimization_decision_tree.html](docs/pg_optimization_decision_tree.html) —
  interactive decision tree for general-purpose PostgreSQL performance tuning
  (open in a browser).
- [docs/PLAN.md](docs/PLAN.md) — architecture and design decisions
- [docs/TASKS.md](docs/TASKS.md) — slice-by-slice implementation tracker
- [config/psqlrc](config/psqlrc) — interactive psql defaults (commented)
