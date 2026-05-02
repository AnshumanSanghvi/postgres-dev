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

- [x] **4.1** Add to Dockerfile: procps-ng, less, vim-minimal, iputils, bind-utils, lsof, jq, tar, gzip, findutils, strace (curl already in base)
- [x] **4.2** Set `ENV LESS=-iMRSx4`
- [x] **4.3** Build & run
- [x] **4.4** Test: each utility resolves (use `command -v`, not `which`, since `which` itself is not in OL9-slim base)
- [x] **4.5** Update README: list of in-container utilities
- [x] **4.6** Commit: `feat(s4): add os utilities for in-container debugging`

### S4 Notes
- `vim-minimal` installs `vi` only; no `vim` binary
- `which` package is not in OL9-slim base; using shell built-in `command -v` instead
- curl is already present in OL9-slim base, no install needed

---

## Slice 5 — Memory Tuning, Timeouts, WAL, Resource Polish

**Goal:** dev-tuned postgresql.conf — full settings.

- [x] **5.1** Update `config/postgresql.conf` with memory/timeout/WAL settings
- [x] **5.2** Restart container, verify all settings via `pg_settings` query
- [x] **5.3** Test: `SET LOCAL statement_timeout='500ms'; SELECT pg_sleep(2)` → cancelled
- [x] **5.4** Test: `idle_in_transaction_session_timeout='1s'` + sleep 3 → connection terminated
- [x] **5.5** Update README: tunables table + per-project override pattern
- [x] **5.6** Commit: `feat(s5): memory, timeout, and wal configuration`

---

## Slice 6 — Logging (stderr text + JSON file + rotation)

**Goal:** dual-format logging with rotation.

- [x] **6.1** Update `config/postgresql.conf` with logging settings (log_filename uses `.log`; postgres replaces extension to `.json` for jsonlog destination)
- [x] **6.2** `/var/log/postgresql` already chowned by entrypoint (S3)
- [x] **6.3** Restart, run a query — both `postgresql-YYYY-MM-DD.log` and `.json` files appear
- [x] **6.4** Add `scripts/logs.sh` — tails today's JSON file with jq pretty-printing
- [x] **6.5** Update README: log layout, formats, helper script, collector handoff caveat
- [x] **6.6** Commit: `feat(s6): dual stderr+json logging with rotation`

### S6 Notes
- Postgres replaces (not appends) the file extension for jsonlog: `.log` → `.json`
- With `logging_collector=on`, `docker logs` only shows pre-handoff output; live tailing must be done from the volume-mounted files
- `scripts/logs.sh` jq-formats: `timestamp [severity] user@db message`

---

## Slice 7 — First Extensions: pg_stat_statements + auto_explain

**Goal:** introduce `shared_preload_libraries` and per-query observability.

- [x] **7.1** Contrib package already present from S1
- [x] **7.2** Update postgresql.conf: shared_preload_libraries, pg_stat_statements.track/max, auto_explain.log_min_duration/log_analyze/log_buffers/log_format/log_nested_statements
- [x] **7.3** Write `initdb/00_extensions.sql` — pg_stat_statements in template1 and postgres (auto_explain is preload-only)
- [x] **7.4** Reset, verify shared_preload_libraries shows both, pg_stat_statements is collecting (3 sleep calls + init script queries visible)
- [x] **7.5** Verify new DB inherits pg_stat_statements (CREATE DATABASE testdb_s7; \dx)
- [x] **7.6** Update README: pg_stat_statements + auto_explain examples and jq filter
- [x] **7.7** Commit: `feat(s7): pg_stat_statements + auto_explain`

### S7 Notes
- auto_explain has NO `CREATE EXTENSION` — listing it in shared_preload_libraries is sufficient. Putting it in 00_extensions.sql would error.
- `auto_explain.log_format = json` matches the jsonlog log file format so plans are first-class JSON entries
- pg_stat_statements installs in `public` schema (default extension schema)

---

## Slice 8 — Schemas + search_path

**Goal:** create `app` schema, lock down `public`, set cluster-wide search_path.

- [x] **8.1** Write `initdb/02_schemas.sql` — REVOKE CREATE on public, CREATE SCHEMA app in template1 + postgres
- [x] **8.2** Set `search_path = '"$user", app, public'` in postgresql.conf (cluster-wide, inherited by every DB)
- [x] **8.3** Update entrypoint to run init scripts on first boot (temporary postgres start, run files in alphabetical order, stop)
- [x] **8.4** Reset, verify: template1 has app schema + search_path
- [x] **8.5** Verify new DB (`CREATE DATABASE testdb`) inherits both
- [x] **8.6** Verify non-superuser cannot CREATE in public (got permission denied error as expected)
- [x] **8.7** Update README: schema strategy
- [x] **8.8** Commit: `feat(s8): app schema + locked-down public + cluster search_path`

### S8 Notes
- **`ALTER DATABASE template1 SET search_path` does NOT propagate** to new databases — per-database settings are not cloned. Set search_path cluster-wide in postgresql.conf instead.
- Init script runner added to entrypoint: starts postgres temporarily on local socket only (`listen_addresses=''`), runs `*.sh`/`*.sql`/`*.sql.gz` files in alphabetical order with `ON_ERROR_STOP=1`, then stops with fast shutdown

---

## Slice 9 — Roles + Login Users (with shell password injection)

**Goal:** create admin/developer/app users with env-var-injected passwords.

- [x] **9.1** Write `initdb/03_roles.sh` using `psql -v admin_pw=...` for password injection
- [x] **9.2** Made executable in repo (chmod +x); init runner picks it up via `.sh` case
- [x] **9.3** `.env` loaded by compose (S3 already)
- [x] **9.4** Reset, verify each user connects
- [x] **9.5** Test: wrong password rejected
- [x] **9.6** Test: SUPERUSER/non-SUPERUSER attribute correct per user
- [x] **9.7** Add `scripts/psql-admin.sh`, `psql-developer.sh`, `psql-app.sh` (read .env)
- [x] **9.8** Update README: users + default passwords table, override via .env
- [x] **9.9** Update healthcheck to real-query as admin (with $$ to escape compose env interpolation)
- [x] **9.10** Commit: `feat(s9): admin/developer/app users with env-var passwords`

### S9 Notes
- `admin` re-owns the `app` schema after creation (was bootstrap-postgres-owned from 02_schemas.sql)
- `pg_monitor` + `pg_read_all_stats` granted directly to `developer` (verified: can read pg_stat_activity for all sessions)
- Helper scripts source `.env` so callers don't need to remember passwords; pass through extra args to psql

---

## Slice 10 — Permissions + DEFAULT PRIVILEGES

**Goal:** wire up grants so admin can create objects and developer/app inherit access.

- [x] **10.1** Write `initdb/04_permissions.sql` — USAGE, existing-object grants, DEFAULT PRIVILEGES (in template1 and postgres)
- [x] **10.2** Reset and run full test matrix — all 9 cases pass:
  - T1 admin DDL ✓ T2 developer DML ✓ T3 developer no DDL ✓
  - T4 app DML ✓ T5 app no TRUNCATE ✓ T6 app no DDL ✓
  - T7 DEFAULT PRIVILEGES auto-grants future objects ✓
  - T8 app blocked from public.* tables ✓
  - T9 RLS enforced for developer + app, BYPASSRLS works for admin ✓
- [x] **10.3** Update README: full permissions matrix, DEFAULT PRIVILEGES explanation
- [x] **10.4** Commit: `feat(s10): role grants and default privileges`

### S10 Notes
- USAGE on `public` is granted to PUBLIC by default (we only revoked CREATE in 02_); so app can call public extension functions even though it can't read public tables
- DEFAULT PRIVILEGES `FOR ROLE admin` only fires for objects admin creates — verified by creating `public.future` as admin and confirming developer auto-inherits SELECT
- pg_anonymizer access for developer is deferred to S13 (when extension is installed)

---

## Slice 11 — pg_cron + pgaudit + pg_partman_bgw + pldebugger (preload extensions)

**Goal:** add the four extensions that need shared_preload_libraries entries.

- [x] **11.1** Verified PGDG arm64 package names: pg_cron_17 (1.6.7), pgaudit_17 (17.1), pg_partman_17 (5.4.3), pldebugger_17 (1.8) — all available
- [x] **11.2** Added with version pins to Dockerfile (Step 5)
- [x] **11.3** hadolint passes
- [x] **11.4** postgresql.conf: shared_preload_libraries with all 6, cron.*, pgaudit.*, pg_partman_bgw.* settings
- [x] **11.5** 00_extensions.sql: CREATE EXTENSION pg_cron, pgaudit, pg_partman, pldbgapi (note: pldebugger extension is named `pldbgapi`)
- [x] **11.6** 06_pg_cron.sql: USAGE on cron schema, full DML on cron.job + cron.job_run_details, EXECUTE on functions, DEFAULT PRIVILEGES, all granted to role_developer
- [x] **11.7** Reset and verify: shared_preload_libraries shows all 6, \dx shows 4 new extensions, developer scheduled pg_cron job successfully, pgaudit emitting AUDIT entries to JSON log
- [x] **11.8** README: usage examples for pg_cron (incl. cross-database), pgaudit (jq filter), pg_partman (parent table + bgw), pldebugger
- [x] **11.9** Commit: `feat(s11): pg_cron, pgaudit, pg_partman, pldebugger`

### S11 Notes
- pldebugger's CREATE EXTENSION name is `pldbgapi` (not `pldebugger`)
- pgaudit version 17.1 matches PG17 — the `pgaudit_17` package is the correct one for PG17 (older `pgaudit17_17` naming was for PG17 paired with older pgaudit major; this scheme changed)
- pg_partman_bgw with role=admin emits warnings on very first boot until admin user is created by 03_roles.sh; harmless and self-correcting on next postgres restart

---

## Slice 12 — Remaining Extensions (no preload required)

**Goal:** add pg_buffercache, pg_prewarm, pg_squeeze, hypopg, pg_hint_plan, wal2json, plpython3u, pgtap, tablefunc.

- [x] **12.1** Verified arm64 packages: pg_squeeze_17 (1.9.1), hypopg_17 (1.4.1), pg_hint_plan_17 (1.7.1), wal2json_17 (2.6), pgtap_17 (1.3.4 noarch), postgresql17-plpython3 (17.9)
- [x] **12.2** Installed via new Dockerfile Step 6, version-pinned, lint clean
- [x] **12.3** 00_extensions.sql: CREATE EXTENSION for 12 extensions in template1 + postgres (pg_cron only in postgres)
- [x] **12.4** Reset, `\dx` shows all 14 extensions (incl. plpgsql)
- [x] **12.5** Smoke-tested each: buffercache count, prewarm, hypopg flips Seq → Bitmap Index Scan, pg_hint_plan SeqScan hint, plpython3u notice, crosstab pivot, pgtap plan/pass/ok/finish, pg_squeeze loaded, wal2json slot creates and drops cleanly
- [x] **12.6** Updated README with usage example for each
- [x] **12.7** Commit: `feat(s12): pg_buffercache, pg_prewarm, pg_squeeze, hypopg, pg_hint_plan, wal2json, plpython3u, pgtap, tablefunc`

### S12 Notes
- **pg_squeeze requires `shared_preload_libraries`** — added to the list (now 7 entries)
- **wal2json is an output plugin, not a regular extension** — no `CREATE EXTENSION`. Used via `pg_create_logical_replication_slot('slot','wal2json')`
- **pg_hint_plan loaded via `session_preload_libraries`** — auto-loads on every connection so hints work without manual `LOAD`
- All 14 extensions inherit into newly-created databases via template1

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

## Slice 14 — CLI Tools (pgcli, pg_activity, pgbadger, pspg, sqitch — pgloader excluded)

**Goal:** add all CLI tools to the image. (pgloader excluded per user decision.)

- [x] **14.1** pgcli via pip (4.1.0 pinned)
- [x] **14.2** pg_activity via pip (3.6.1 pinned)
- [x] **14.3** pspg via PGDG (5.8.16, arm64 binary)
- [x] **14.4** pgbadger via PGDG (13.2) — needs Oracle EPEL for `perl-Text-CSV_XS`; install must be in a separate dnf transaction after `oracle-epel-release-el9` (single-transaction misses newly-enabled repo)
- [x] **14.5** sqitch via cpanm (App::Sqitch 1.6.1) — heavy build (~5 min on arm64)
- [x] **14.6** ~~pgloader~~ — EXCLUDED per user decision
- [x] **14.7** Set `ENV PAGER=pspg`
- [x] **14.8** hadolint clean
- [x] **14.9** Verified all 6: pgcli, pg_activity, pgbadger, pspg, sqitch, pgbench
- [x] **14.10** Commit: `feat(s14): cli tools (pgcli, pg_activity, pgbadger, pspg, sqitch)`

### S14 Notes (took several iterations to get right)
- **PGDG `pgcli`/`pg_activity` packages have unmet deps on OL9-slim** (`python3-setproctitle`, `python3-cli-helpers`, `python3.12-humanize`). Use pip install instead.
- **pgbadger needs `perl-Text-CSV_XS` from EPEL.** Two dnf transactions required: first to install `oracle-epel-release-el9`, then a fresh dnf invocation (with newly-loaded repo metadata) installs pgbadger. Combining into one transaction silently fails.
- **`dnf -y remove gcc make` after cpanm prunes pgbadger's perl deps** because OL9 default `clean_requirements_on_remove=True` pulls anything tagged "auto-installed" — including pgbadger's transitive perl deps. Solution: keep build deps in image (~150MB heavier, acceptable for dev).
- **cpanm `--notest` drops some runtime deps** (e.g. Sub::Exporter::Util, Data::OptList). Run with tests for full dependency tree.
- All 5 tool versions verified at the END of step 6e via smoke-test chain — silent install failures fail the build loudly.
- Image size: 1.13 GB (was 373 MB at S1)

---

## Slice 15 — `.psqlrc` + UX polish + Final README

**Goal:** in-container UX polish and documentation completeness.

- [x] **15.1** Write `config/psqlrc` (heavily commented): timing, NULL=∅, prompt with transaction marker, pspg pager, history per DB, verbosity verbose, ON_ERROR_STOP, plus :settings/:locks/:activity/:sizes/:slow macros
- [x] **15.2** Copy to `/etc/psqlrc` in image, set `ENV PSQLRC=/etc/psqlrc` (so any user via `docker exec` picks it up — `~/.psqlrc` requires HOME to be set right which root's HOME isn't)
- [x] **15.3** Test: `\timing` is on (verified via heredoc)
- [x] **15.4** Test: NULL displayed as `∅` (verified)
- [x] **15.5** README: comprehensive final pass with TOC and all required sections
- [x] **15.6** Commit: `feat(s15): psqlrc and ux polish`

### S15 Notes
- **PSQLRC env var** is the right hook, not `~/.psqlrc`. With no USER directive in Dockerfile, `docker exec` runs as root (HOME=/root) — `~/.psqlrc` lookup fails. Putting the file at `/etc/psqlrc` and pointing `PSQLRC` at it sidesteps the HOME issue.
- `psql -c "..."` deliberately skips `.psqlrc`; tests use heredoc.
- All 15 required README sections delivered.

### Required README Sections (final state)
- [x] Title + one-paragraph description
- [x] Table of contents
- [x] Prerequisites
- [x] Quick start
- [x] Default users + passwords table
- [x] Connection examples (helper scripts + raw psql + in-container)
- [x] Volume layout
- [x] Resetting the environment
- [x] Updating config without rebuild
- [x] Architecture support note (multi-arch + bind-mount UID alignment)
- [x] Sample `docker-compose.override.yml` (two patterns: extends vs include)
- [x] Permissions matrix
- [x] Reference to `.psqlrc` (path, contents, macros)
- [x] Extension list with usage example each (14 extensions)
- [x] CLI tools list with example invocation
- [x] pgbench prerequisites
- [x] pg_cron access doc (developer can schedule, has DML on cron.job)
- [x] Logging guide (text + JSON, scripts/logs.sh, pgbadger)
- [x] Troubleshooting (5 common issues)

---

## Slice 16 — Final Integration Test

- [x] **16.1** Full reset (`scripts/reset.sh`) + cold up to healthy
- [x] **16.2** Fresh DB inherits 13 extensions from template1 (pg_cron is `postgres`-only by design); template1 itself + postgres has 14 each
- [x] **16.3** admin/developer/app all connect with default `.env` passwords
- [x] **16.4** RLS enforced: admin sees 5 rows (BYPASSRLS), developer sees 1 (own row), app sees 1 (own row)
- [x] **16.5** Both `postgresql-YYYY-MM-DD.log` (text) and `.json` files written; jq-decodable
- [x] **16.6** `cron.schedule_in_database()` from developer schedules a cross-DB job
- [x] **16.7** pgaudit captured 2 AUDIT entries for each of admin/developer/app
- [x] **16.8** ~~pg_anonymizer~~ — SKIPPED (excluded per user decision)
- [x] **16.9** Data persists across `down/up` — rows including persist_marker confirmed
- [x] **16.10** `work_mem` changed from 4MB to 8MB via config edit + `docker compose restart` (no rebuild)
- [x] **16.11** pgbadger generated 1.06 MB HTML report with proper `<title>` from JSON+text logs
- [x] **16.12** hadolint clean on the final Dockerfile
- [x] **16.13** Final commit: `chore(s16): final integration test pass`

### Final summary
- **17 commits** (S0 through S16)
- **PostgreSQL 17.9** on `oraclelinux:9-slim`, multi-arch (verified arm64; amd64 architecturally supported)
- **Image size:** 1.13 GB
- **Extensions (14):** pg_stat_statements, pg_cron, pgaudit, pg_partman, pldbgapi, pg_buffercache, pg_prewarm, pg_squeeze, hypopg, pg_hint_plan, plpython3u, tablefunc, pgtap, plus auto_explain (preload-only) and wal2json (output plugin) — `pg_anonymizer` excluded per user
- **CLI tools (5):** pgcli 4.1.0, pg_activity 3.6.1, pgbadger 13.2, pspg 5.8.16, sqitch 1.6.1 (+ pgbench from server package) — `pgloader` excluded per user
- **Users:** admin (SUPERUSER), developer (RLS-enforced, pg_monitor), app (RLS-enforced, conn limit 50)
- **Schemas:** `app` (admin-owned), `public` (extensions only, CREATE revoked from PUBLIC)
- **Logging:** dual format (text + JSON), daily rotation, `log_min_duration_statement=0`
- **All init scripts run on first boot only**; reset workflow documented and tested

---

## Slice 17 — Barman 3.18 continuous backups + PITR

**Goal:** add continuous WAL-based backups with point-in-time recovery to the
existing setup, in the SAME container, without breaking anything.

### Spec corrections (approved by user)
- **B1**: streaming-only — no SSH, no `archive_command`. Barman pulls WAL via the streaming replication slot. Simpler, lower latency, fewer failure modes.
- **B2**: drop the spec's "every minute receive-wal" cron line (broken — receive-wal is a long-running daemon, not a per-minute job). Use `barman cron` every minute instead — that's the command that manages receive-wal as a child daemon and restarts it on failure.
- **B3**: keep `wal_level = logical` (NOT downgraded to `replica`). Logical is a strict superset; Barman works fine with it. Downgrading would break `wal2json` and the CDC playbook chapters.
- **T1**: storage cap raised from 1 GB to 5 GB. 1 GB is too tight for 30-day PITR with normal dev activity.
- **T2**: simple `cron -f &` background + foreground postgres (no supervisord).
- **T3**: container `mem_limit` raised from 512 MB to 768 MB.

### Tasks
- [x] Dockerfile Step 6f: install `barman 3.18.0`, `barman-cli 3.18.0`, `cronie 1.5.7`, `sudo`. Create `/var/lib/barman` (700, barman:barman) and `/var/log/barman`. Sudoers entry for postgres → barman. COPY barman.conf, barman.d/, cron file, helper scripts.
- [x] `compose.yml`: add `./backups:/var/lib/barman` bind mount; bump `mem_limit` to 768m, `mem_reservation` to 384m.
- [x] `.env.example` + local `.env`: add `BARMAN_USER` and `BARMAN_PASSWORD`.
- [x] `config/postgresql.conf`: `wal_keep_size = 512MB`, explicit `max_wal_senders = 10`, `max_replication_slots = 10`. **NOT** changing `wal_level` (stays `logical`).
- [x] `config/pg_hba.conf`: add replication entries for `barman_repl` over 127.0.0.1 + ::1, scram-sha-256.
- [x] `config/barman.conf`: global config (barman_user, barman_home, log_file, configuration_files_directory).
- [x] `config/barman.d/postgres-dev.conf`: server config — backup_method=postgres, streaming_archiver=on, slot_name=barman_slot, retention_policy=RECOVERY WINDOW OF 30 DAYS, minimum_redundancy=2.
- [x] `config/barman.crontab` (installed at `/etc/cron.d/barman`): every-minute `barman cron`, weekly + monthly `barman backup`, daily `barman check`, every-15-min cleanup script.
- [x] `initdb/05_barman_replication.sh`: create the BARMAN_USER role and physical replication slot.
- [x] `entrypoint.sh`: align barman UID/GID to bind-mount owner; generate `/var/lib/barman/.pgpass` from env; start crond in background.
- [x] `scripts/barman-{backup,list,check,restore-latest,restore-pitr,cleanup}.sh` helpers.

### Tests
- [x] hadolint clean on updated Dockerfile
- [x] Build succeeds on arm64 (image: 1.13 GB → 1.24 GB)
- [x] Fresh reset + cold up to healthy: all 6 init scripts run (00, 02, 03, 04, **05** new, 06)
- [x] Regression suite (S16-style):
  - 14 extensions still installed in fresh DB
  - admin/developer/app users connect with default passwords
  - RLS enforced (admin sees 5, developer 1, app 1)
  - `wal_level` is `logical` (NOT downgraded to replica)
  - `wal_keep_size = 512MB` applied
- [x] Barman infrastructure:
  - `barman 3.18.0` installed; `barman --version` reports 3.18.0
  - `crond -n -m off` running in background as PID alongside postgres
  - `barman_repl` role created with REPLICATION + 3 role memberships + 4 EXECUTE function grants
  - Physical replication slot `barman_slot` created (visible in `pg_replication_slots`)
  - `/var/lib/barman/.pgpass` generated at entrypoint with 0600 perms
- [x] `barman cron` succeeds; receive-wal streaming established
- [x] `barman switch-wal --force --archive` works (requires `pg_checkpoint` role + `pg_switch_wal` EXECUTE — both granted)
- [x] `barman backup postgres-dev` produces a 27.5 MiB basebackup in ~20 sec
- [x] After 2 backups, `barman check` reports OK across all 22 health checks
- [x] `barman recover` to sandbox dir produces valid PGDATA; restored cluster boots on alternate port
- [x] **PITR verified end-to-end**: inserted pre-marker + post-marker into a table, took backup before, ran PITR with `--target-time` between the two inserts, recovered cluster shows pre-marker only (post-marker correctly absent)
- [x] Helper scripts on PATH: barman-backup, barman-list, barman-check, barman-restore-latest, barman-restore-pitr, barman-cleanup
- [x] /etc/cron.d/barman has expected entries (every-min cron, weekly/monthly backups, daily check, cleanup)
- [x] Backup storage on host (./backups/) at 99 MB after 3 basebackups + WAL streams

### S17 Implementation Notes
- **Inline comments break Barman's INI parser** — `key = value # comment` is parsed with the comment as part of the value. All barman config files keep comments on their own lines.
- **Barman `path_prefix = /usr/pgsql-17/bin`** is required because barman runs as the `barman` user with default PATH (`/sbin:/bin:/usr/sbin:/usr/bin`) which doesn't include the postgres bin dir.
- **`barman_repl` needs more than REPLICATION**: requires `pg_read_all_settings`, `pg_read_all_stats`, `pg_checkpoint` role memberships AND `EXECUTE` grants on `pg_switch_wal()`, `pg_create_restore_point()`, `pg_backup_start()`, `pg_backup_stop()`. Without these, `barman check` fails with "missing required privileges".
- **`barman switch-wal --force` requires `pg_checkpoint`** role membership (PG14+).
- **PITR `--target-time` must be AFTER the chosen backup's end time** — pick a backup whose end time precedes your target with `barman list-backup`. Use `--target-action pause` to keep the recovered cluster queryable read-only after reaching the target.
- **`./backups/` UID alignment** — same Docker Desktop Mac quirk as PGDATA. Entrypoint detects bind-mount UID/GID and aligns the in-container barman user to match (`usermod -o`). Both postgres and barman end up with the same UID (host UID) on Mac; Linux native runs see them as separate UIDs.
- **No SSH** — `archive_command` is unset in postgres; Barman uses the streaming replication slot (`pg_receivewal`-style) for continuous WAL pull. Lower latency than archive_command, fewer failure modes.

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
