# Postgres Dev Environment

A reusable, dockerized PostgreSQL 17 development environment built on OracleLinux 9
Slim. Designed to mirror production RHEL9/OL9 environments, with a curated set of
extensions, dev-tuned configuration, and CLI tooling baked in.

**Status:** S8 — schemas, locked-down public, cluster-wide search_path. See
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
