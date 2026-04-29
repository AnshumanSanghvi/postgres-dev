# Postgres Dev Environment

A reusable, dockerized PostgreSQL 17 development environment built on OracleLinux 9
Slim. Designed to mirror production RHEL9/OL9 environments, with a curated set of
extensions, dev-tuned configuration, and CLI tooling baked in.

**Status:** S3 — docker compose, volumes, helper scripts. See [TASKS.md](TASKS.md)
for slice progress.

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

---

## Documents
- [PLAN.md](PLAN.md) — architecture and design decisions
- [TASKS.md](TASKS.md) — slice-by-slice implementation tracker
