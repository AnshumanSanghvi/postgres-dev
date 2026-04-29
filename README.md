# Postgres Dev Environment

A reusable, dockerized PostgreSQL 17 development environment built on OracleLinux 9
Slim. Designed to mirror production RHEL9/OL9 environments, with a curated set of
extensions, dev-tuned configuration, and CLI tooling baked in.

**Status:** S2 — custom config, scram-sha-256 auth, port 5499. See [TASKS.md](TASKS.md)
for slice progress.

---

## What works today (after S2)
- PostgreSQL 17 server + contrib on `oraclelinux:9-slim`, multi-arch (amd64 + arm64)
- Locale `C.UTF-8`, encoding `UTF8`, timezone `UTC`
- Custom `postgresql.conf` and `pg_hba.conf` mounted from `./config/` — change without rebuild
- `scram-sha-256` authentication enforced for all connections
- Listens on port `5499` (avoids conflict with local postgres on 5432)
- SSL disabled (dev only)

## Build & run
```bash
docker build -t postgres-dev:s2 .

# Run with mounted config, port forwarded, password set
docker run --rm -d --name pg \
  -v "$(pwd)/config:/etc/postgresql:ro" \
  -e POSTGRES_PASSWORD=testpass123 \
  -p 5499:5499 \
  postgres-dev:s2

# Connect from host
PGPASSWORD=testpass123 psql -h localhost -p 5499 -U postgres

# Or from inside the container
docker exec -e PGPASSWORD=testpass123 -it pg psql -U postgres -p 5499

# Stop
docker stop pg
```

## Verification
```bash
# Auth method, port, SSL state
PGPASSWORD=testpass123 psql -h localhost -p 5499 -U postgres -tAc \
  "SELECT current_setting('port'), current_setting('password_encryption'), current_setting('ssl');"
# → 5499|scram-sha-256|off

# pg_hba rules in effect
PGPASSWORD=testpass123 psql -h localhost -p 5499 -U postgres -c \
  "SELECT type, database[1], user_name[1], address, auth_method FROM pg_hba_file_rules ORDER BY rule_number;"
```

## Editing config without rebuilding
The container mounts `./config/` read-only at `/etc/postgresql/`. After editing
`postgresql.conf` or `pg_hba.conf` on the host, simply restart the container:
```bash
docker restart pg
```
No image rebuild needed.

---

## Documents
- [PLAN.md](PLAN.md) — architecture and design decisions
- [TASKS.md](TASKS.md) — slice-by-slice implementation tracker
