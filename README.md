# Postgres Dev Environment

A reusable, dockerized PostgreSQL 17 development environment built on OracleLinux 9
Slim. Designed to mirror production RHEL9/OL9 environments, with a curated set of
extensions, dev-tuned configuration, and CLI tooling baked in.

**Status:** S1 — bare PG17 image working. See [TASKS.md](TASKS.md) for slice progress.

---

## What works today (after S1)
- PostgreSQL 17 server + contrib on `oraclelinux:9-slim`
- Multi-arch: pulls native architecture automatically (tested on arm64)
- Locale `C.UTF-8`, encoding `UTF8`, timezone `UTC`
- Default `initdb` configuration (no custom users/config yet — those come in S2+)

## Build & run (S1)
```bash
# Build for your host architecture
docker build -t postgres-dev:s1 .

# Run in foreground (Ctrl-C to stop)
docker run --rm --name pg-s1 postgres-dev:s1

# Or detach and connect
docker run --rm -d --name pg-s1 postgres-dev:s1
docker exec -it pg-s1 psql -U postgres
docker stop pg-s1
```

## Quick verification
```bash
docker exec pg-s1 psql -U postgres -c 'SELECT version();'
# → PostgreSQL 17.9 on <arch>-unknown-linux-gnu, ...

docker exec pg-s1 psql -U postgres -tAc "SHOW timezone;"           # UTC
docker exec pg-s1 psql -U postgres -tAc "SHOW server_encoding;"    # UTF8
```

---

## Documents
- [PLAN.md](PLAN.md) — architecture and design decisions
- [TASKS.md](TASKS.md) — slice-by-slice implementation tracker
