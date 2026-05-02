# Postgres Dev Playbook — Scenario-Based Recipes

A working guide to the extensions and tools shipped with this dev environment.
Each chapter starts with a real situation a developer hits, then walks through
the extensions/tools that solve it, with executable steps and a short rationale.

Every recipe assumes the container is running and you have `.env`-set passwords;
adapt user (`admin`/`developer`/`app`) and database (`postgres`/your db) as needed.

---

## Table of contents

1. [Performance investigation](#1-performance-investigation)
   1.1 [An endpoint got slower after the last deploy](#11--an-endpoint-got-slower-after-the-last-deploy)
   1.2 [Some queries are fast in dev, slow in staging](#12--some-queries-are-fast-in-dev-slow-in-staging)
   1.3 [We're CPU-bound but I don't know which query](#13--were-cpu-bound-but-i-dont-know-which-query)
   1.4 [Buffer cache hit ratio dropped](#14--buffer-cache-hit-ratio-dropped)
2. [Index design](#2-index-design)
   2.1 [Should I add this index?](#21--should-i-add-this-index)
   2.2 [Comparing two candidate indexes for the same query](#22--comparing-two-candidate-indexes-for-the-same-query)
   2.3 [The planner ignores my new index](#23--the-planner-ignores-my-new-index)
   2.4 [How much will this index cost to maintain?](#24--how-much-will-this-index-cost-to-maintain)
3. [Schema & migration workflow](#3-schema--migration-workflow)
   3.1 [I need a SQL-native migration tool](#31--i-need-a-sql-native-migration-tool)
   3.2 [Verifying my migrations don't break RLS](#32--verifying-my-migrations-dont-break-rls)
   3.3 [Rolling forward and back safely](#33--rolling-forward-and-back-safely)
   3.4 [Migrating data with a Python transform](#34--migrating-data-with-a-python-transform)
4. [Maintenance automation](#4-maintenance-automation)
   4.1 [Delete soft-deleted rows after 30 days](#41--delete-soft-deleted-rows-after-30-days)
   4.2 [Refresh a materialized view every 10 minutes](#42--refresh-a-materialized-view-every-10-minutes)
   4.3 [Run VACUUM on a hot table every night](#43--run-vacuum-on-a-hot-table-every-night)
   4.4 [Cross-database job](#44--cross-database-job)
5. [Partitioning at scale](#5-partitioning-at-scale)
   5.1 [Convert a 500M-row table to time-partitioned](#51--convert-a-500m-row-table-to-time-partitioned)
   5.2 [Auto-create future partitions](#52--auto-create-future-partitions)
   5.3 [Drop expired partitions automatically](#53--drop-expired-partitions-automatically)
   5.4 [Reclaim bloat from the hot partition](#54--reclaim-bloat-from-the-hot-partition)
6. [Change data capture & event streaming](#6-change-data-capture--event-streaming)
   6.1 [Stream INSERT/UPDATE/DELETE to a downstream consumer](#61--stream-insertupdatedelete-to-a-downstream-consumer)
   6.2 [Replay a window of changes after a bug](#62--replay-a-window-of-changes-after-a-bug)
   6.3 [Lightweight CDC without Debezium](#63--lightweight-cdc-without-debezium)
   6.4 [Filter which tables to publish](#64--filter-which-tables-to-publish)
7. [Auditing, compliance & forensics](#7-auditing-compliance--forensics)
   7.1 [Who accessed customer table this week?](#71--who-accessed-customer-table-this-week)
   7.2 [Reconstruct a session's activity](#72--reconstruct-a-sessions-activity)
   7.3 [Catch unexpected DDL](#73--catch-unexpected-ddl)
   7.4 [Verify least-privilege boundaries](#74--verify-least-privilege-boundaries)
8. [PL/pgSQL development & debugging](#8-plpgsql-development--debugging)
   8.1 [Step-debug a PL/pgSQL function](#81--step-debug-a-plpgsql-function)
   8.2 [Unit-test a procedure](#82--unit-test-a-procedure)
   8.3 [Call Python from a function](#83--call-python-from-a-function)
   8.4 [Capture performance of stored procedures](#84--capture-performance-of-stored-procedures)
9. [Reporting & analytics](#9-reporting--analytics)
   9.1 [Pivot daily counts into a weekly view](#91--pivot-daily-counts-into-a-weekly-view)
   9.2 [Walk a tree of comments or categories](#92--walk-a-tree-of-comments-or-categories)
   9.3 [Find largest tables by total size](#93--find-largest-tables-by-total-size)
   9.4 [Per-table cache hit ratio](#94--per-table-cache-hit-ratio)
10. [Capacity planning & load testing](#10-capacity-planning--load-testing)
    10.1 [How many concurrent connections can this handle?](#101--how-many-concurrent-connections-can-this-handle)
    10.2 [Cost of an index on a write-heavy table](#102--cost-of-an-index-on-a-write-heavy-table)
    10.3 [Will it stay healthy under 10× traffic?](#103--will-it-stay-healthy-under-10-traffic)
11. [RLS & security validation](#11-rls--security-validation)
    11.1 [Catch an over-permissive grant](#111--catch-an-over-permissive-grant)
    11.2 [Verify RLS policies before deploy](#112--verify-rls-policies-before-deploy)
    11.3 [Audit what role X can actually do](#113--audit-what-role-x-can-actually-do)
12. [Daily DX shortcuts](#12-daily-dx-shortcuts)
    12.1 [Make psql sing for me](#121--make-psql-sing-for-me)
    12.2 [Stop typing the same diagnostics queries](#122--stop-typing-the-same-diagnostics-queries)
    12.3 [Read the JSON log live](#123--read-the-json-log-live)
13. [Backup, restore, and PITR with Barman](#13-backup-restore-and-pitr-with-barman)
    13.1 [Take an out-of-band backup](#131--take-an-out-of-band-backup)
    13.2 [Restore the latest backup to a sandbox cluster](#132--restore-the-latest-backup-to-a-sandbox-cluster)
    13.3 ["I dropped the wrong table" — point-in-time recovery](#133--i-dropped-the-wrong-table--point-in-time-recovery)
    13.4 [Verify a backup is good before you need it](#134--verify-a-backup-is-good-before-you-need-it)
    13.5 [Recover when storage hits the cap](#135--recover-when-storage-hits-the-cap)

---

## 1. Performance investigation

### 1.1 — "An endpoint got slower after the last deploy"

**Symptom:** `/orders/recent` p99 latency jumped from 80 ms to 600 ms after Monday's
release. You don't know which query is the culprit.

**Tooling:** `pg_stat_statements`, `auto_explain`, `pgbadger`, `:slow` macro.

#### Step 1 — find candidates with `pg_stat_statements`
```sql
-- snapshot a clean baseline
SELECT pg_stat_statements_reset();
```
After exercising the slow endpoint a few times:
```sql
:slow                                          -- shortcut from .psqlrc
-- or directly:
SELECT calls, mean_exec_time::int AS mean_ms,
       total_exec_time::int       AS total_ms,
       rows, substr(query, 1, 100) AS query
FROM   pg_stat_statements
WHERE  query NOT LIKE '%pg_stat_statements%'
ORDER  BY total_exec_time DESC LIMIT 10;
```
The `total_ms` column (calls × mean_ms) reveals which query is paying for the
regression — not just the slowest in isolation.

#### Step 2 — get the plan from `auto_explain`
```bash
jq -r 'select(.message | startswith("duration:")) | .message' \
   volumes/logs/postgresql-$(date -u +%Y-%m-%d).json \
   | grep -A 40 'orders_recent'
```
Look for: `Seq Scan` on a large table, missing index, wrong join type, or
`Rows Removed by Filter` orders of magnitude larger than `Rows`.

#### Step 3 — generate a shareable HTML report with `pgbadger`
```bash
docker exec postgres-dev pgbadger -q \
  /var/log/postgresql/postgresql-$(date -u +%Y-%m-%d).log \
  -o /tmp/perf-$(date -u +%Y-%m-%d).html
docker cp postgres-dev:/tmp/perf-$(date -u +%Y-%m-%d).html ./
```

#### Step 4 — confirm the diagnosis
- Compare today's plan against a previous pgbadger report.
- `SELECT last_analyze, last_autoanalyze FROM pg_stat_user_tables WHERE relname='orders';`
- Check whether the query's parameter shape changed (e.g., a date filter that used to match 1 % of rows now matches 10 %).

#### Step 5 — fix path
- Plan needs an index → §2.1
- Stale stats → `ANALYZE orders;`
- Planner picks the wrong plan even with the right index → §2.3
- Regression is unavoidable → benchmark with `pgbench` (§10.3) and budget the cost

**Why this works:** `pg_stat_statements` aggregates blame across every call. `auto_explain`
captures the plan for free at the moment of slowness — no reproduction needed.
`pgbadger` packages both into something a non-DBA can read.

---

### 1.2 — "Some queries are fast in dev, slow in staging"

**Symptom:** `EXPLAIN ANALYZE` of the same query gives wildly different plans in each environment.

**Tooling:** `auto_explain` JSON plans + plain text diff.

#### Step 1 — capture both plans in JSON
On each environment, run the query then pull its `auto_explain` entry from
`volumes/logs/postgresql-*.json`:
```bash
jq 'select(.message | startswith("duration:") and contains("orders_recent"))' \
   volumes/logs/postgresql-$(date -u +%Y-%m-%d).json > dev-plan.json
# repeat in staging → staging-plan.json
```

#### Step 2 — diff the plan structure
```bash
diff <(jq '.message' dev-plan.json | jq .) \
     <(jq '.message' staging-plan.json | jq .)
```

#### Step 3 — typical causes
- Different `random_page_cost` / `seq_page_cost` (check `:settings`).
- Different table sizes → `pg_stat_user_tables.n_live_tup`.
- Stale statistics (`last_analyze` differ).
- Different `work_mem` causing a hash join in dev but a merge join in staging.

**Why this works:** JSON plans are diff-able. Diffing them surfaces the planner's
decisions (loops, joins, costs) explicitly, instead of trying to read prose
`EXPLAIN` output side-by-side.

---

### 1.3 — "We're CPU-bound but I don't know which query"

**Symptom:** container hits its CPU ceiling, app responses pile up.

**Tooling:** `pg_activity` (live), `pg_stat_statements` (history), `:activity` macro.

#### Step 1 — live view
```bash
docker exec -it -e PGPASSWORD=admin postgres-dev pg_activity -U admin -p 5499
```
Sort by CPU, then by IO read/write. Watch for one query dominating the list.

#### Step 2 — historical view
```sql
:slow
-- combine with shared_blks for IO-heavy queries:
SELECT calls, mean_exec_time::int AS mean_ms,
       shared_blks_read, shared_blks_hit,
       substr(query, 1, 80) AS query
FROM pg_stat_statements
ORDER BY shared_blks_read DESC LIMIT 10;
```

#### Step 3 — drill into a specific session
```sql
:activity
-- specific pid:
SELECT * FROM pg_stat_activity WHERE pid = 12345;
```

**Why this works:** `pg_activity` gives you instant insight; `pg_stat_statements`
tells you whether what you're seeing is a one-off or chronic.

---

### 1.4 — "Buffer cache hit ratio dropped"

**Symptom:** queries that used to be fast become consistently slow, especially
right after a deploy or restart.

**Tooling:** `pg_buffercache`, `pg_prewarm`.

#### Step 1 — measure current hit ratio
```sql
SELECT sum(heap_blks_hit)::float / nullif(sum(heap_blks_hit)+sum(heap_blks_read),0)
  AS hit_ratio
FROM pg_statio_user_tables;
```
Healthy: > 0.99. < 0.95 means the working set isn't fitting.

#### Step 2 — see what's currently in cache
```sql
SELECT c.relname,
       count(*) AS buffers,
       pg_size_pretty(count(*) * 8192) AS size
FROM   pg_buffercache b
JOIN   pg_class c ON b.relfilenode = pg_relation_filenode(c.oid)
GROUP  BY c.relname
ORDER  BY count(*) DESC LIMIT 20;
```

#### Step 3 — prewarm hot tables after a restart
```sql
SELECT pg_prewarm('app.orders');
SELECT pg_prewarm('app.orders_pkey');
```
Or schedule it via `pg_cron` to run a few seconds after startup.

**Why this works:** `pg_buffercache` shows reality; `pg_prewarm` lets you make
restarts behave like steady-state instead of cold-start.

---

## 2. Index design

### 2.1 — "Should I add this index?"

**Symptom:** a slow query has a `Seq Scan`; you suspect an index would help, but
the table is large and `CREATE INDEX` would take an hour.

**Tooling:** `hypopg`.

#### Step 1 — baseline plan
```sql
EXPLAIN SELECT * FROM app.orders WHERE customer_id = 42;
```

#### Step 2 — create a hypothetical index (no actual build)
```sql
SELECT * FROM hypopg_create_index('CREATE INDEX ON app.orders(customer_id)');
```

#### Step 3 — re-run EXPLAIN
```sql
EXPLAIN SELECT * FROM app.orders WHERE customer_id = 42;
-- Look for "Bitmap Index Scan on <13592>btree_app_orders_customer_id"
```
If the plan changes and cost drops meaningfully, the real index will help.

#### Step 4 — clean up
```sql
SELECT hypopg_reset();         -- discard all hypotheticals
```

**Why this works:** the planner uses hypothetical indexes for cost estimation
without touching the table. You can iterate through five candidate indexes
faster than `CREATE INDEX` runs once.

---

### 2.2 — "Comparing two candidate indexes for the same query"

**Symptom:** you can't decide between `(a, b)` vs `(b, a)` vs `(a) WHERE b IS NOT NULL`.

**Tooling:** `hypopg` × multiple, then `EXPLAIN` each.

```sql
SELECT hypopg_reset();
SELECT hypopg_create_index('CREATE INDEX ON app.t(a, b)');
EXPLAIN SELECT * FROM app.t WHERE a = 1 AND b = 2;
SELECT hypopg_reset();

SELECT hypopg_create_index('CREATE INDEX ON app.t(b, a)');
EXPLAIN SELECT * FROM app.t WHERE a = 1 AND b = 2;
SELECT hypopg_reset();

SELECT hypopg_create_index('CREATE INDEX ON app.t(a) WHERE b IS NOT NULL');
EXPLAIN SELECT * FROM app.t WHERE a = 1 AND b IS NOT NULL;
```
Compare the costs (`cost=0.00..XX.XX`); pick the lowest for your most common query shape.

**Why this works:** lets you A/B/C indexes without paying build time three times.

---

### 2.3 — "The planner ignores my new index"

**Symptom:** you built the index, but `EXPLAIN` still shows `Seq Scan`.

**Tooling:** `pg_hint_plan` (auto-loaded per session).

#### Step 1 — force the plan
```sql
/*+ IndexScan(orders orders_customer_id_idx) */
EXPLAIN ANALYZE
SELECT * FROM app.orders WHERE customer_id = 42;
```

#### Step 2 — compare costs
- If forced plan is *faster* → planner is mis-costing. Check `random_page_cost`,
  table stats (`ANALYZE`), and column correlation (`pg_stats.correlation`).
- If forced plan is *slower* → the planner was right; the index doesn't help here.

#### Step 3 — common fixes
- `ANALYZE app.orders;` — stats are stale.
- Lower `random_page_cost` (default 4.0; for SSD, 1.1 is standard).
- Add multi-column statistics if columns are correlated:
  `CREATE STATISTICS s_corr (dependencies) ON a, b FROM app.t; ANALYZE app.t;`

**Why this works:** `pg_hint_plan` makes the "what if the planner did the right
thing?" question testable in seconds.

---

### 2.4 — "How much will this index cost to maintain?"

**Symptom:** the index speeds reads but the table is write-heavy. You want to
quantify the trade-off before shipping.

**Tooling:** `pgbench` + `auto_explain`.

#### Step 1 — capture write throughput baseline
```bash
docker exec -e PGPASSWORD=admin postgres-dev pgbench -i -U admin -p 5499 -d postgres
docker exec -e PGPASSWORD=admin postgres-dev pgbench \
  -c 4 -j 2 -T 30 -U admin -p 5499 postgres > /tmp/baseline.txt
```

#### Step 2 — add the index, repeat
```sql
CREATE INDEX CONCURRENTLY ON pgbench_accounts (bid);
```
```bash
docker exec -e PGPASSWORD=admin postgres-dev pgbench \
  -c 4 -j 2 -T 30 -U admin -p 5499 postgres > /tmp/with-index.txt
```

#### Step 3 — diff TPS
The "tps =" line at the bottom of each report is what you compare. A 5–15 % drop
is typical for one extra btree on a hot write path.

**Why this works:** turns "indexes are expensive on writes" from folklore into a
measured number specific to your data and config.

---

## 3. Schema & migration workflow

### 3.1 — "I need a SQL-native migration tool"

**Symptom:** existing tools are Java-heavy or ORM-coupled; you want to manage
schema with plain SQL files.

**Tooling:** `sqitch` (already in the image).

#### Step 1 — initialize a project
```bash
docker exec -it postgres-dev bash
cd /workspace                                                     # bind mount your repo here
sqitch init my_project --engine pg --target db:pg://admin@/postgres
```

#### Step 2 — add a change
```bash
sqitch add create_orders -n 'create orders table'
# this creates deploy/, revert/, verify/ SQL stubs
```
Edit `deploy/create_orders.sql`, `revert/create_orders.sql`, and
`verify/create_orders.sql`.

#### Step 3 — deploy / verify / revert
```bash
sqitch deploy db:pg://admin:admin@localhost:5499/postgres
sqitch verify db:pg://admin:admin@localhost:5499/postgres
sqitch revert  db:pg://admin:admin@localhost:5499/postgres -y
```

**Why this works:** sqitch tracks dependencies between changes (not linear
versions) and never assumes your migrations are append-only — making revert a
first-class operation.

---

### 3.2 — "Verifying my migrations don't break RLS"

**Symptom:** you added a new policy or table; you want CI to catch unintended
loosening of access.

**Tooling:** `pgtap`, executed inside a `BEGIN ... ROLLBACK` block.

```sql
BEGIN;
SELECT plan(5);

-- schema assertions
SELECT has_table('app', 'orders', 'orders table exists');
SELECT col_not_null('app', 'orders', 'id', 'id is NOT NULL');
SELECT has_pk('app', 'orders', 'orders has a primary key');

-- RLS policy assertions
SELECT is(
  (SELECT relrowsecurity FROM pg_class WHERE oid = 'app.orders'::regclass),
  true,
  'RLS is enabled on orders'
);
SELECT isnt_empty(
  $$ SELECT polname FROM pg_policy WHERE polrelid = 'app.orders'::regclass $$,
  'orders has at least one policy'
);

SELECT * FROM finish();
ROLLBACK;
```

#### Run from CI
```bash
docker exec -i -e PGPASSWORD=admin postgres-dev \
  psql -U admin -p 5499 -d postgres < tests/orders.sql
```
Exit non-zero on any failed assertion.

**Why this works:** `BEGIN ... ROLLBACK` keeps tests zero-impact; `pgtap` returns
TAP-format output that any test runner understands.

---

### 3.3 — "Rolling forward and back safely"

**Symptom:** a migration broke staging; you need a rehearsed rollback.

**Tooling:** `sqitch revert`, `pgtap` as a gate.

#### Step 1 — write a verify script for every change
`verify/create_orders.sql`:
```sql
SELECT 1/COUNT(*) FROM information_schema.tables
  WHERE table_schema='app' AND table_name='orders';
```
A failed verify aborts the migration.

#### Step 2 — script the round-trip in CI
```bash
sqitch deploy && sqitch verify && sqitch revert -y && sqitch verify
```
The last verify *should* fail (the table no longer exists). Confirms revert truly removed it.

#### Step 3 — add pgtap test for invariants
`tests/orders.test.sql` (chapter 3.2) runs after every deploy in your pipeline.

**Why this works:** sqitch revert is only as good as your revert script; pgtap is
the safety net that says "actually verified".

---

### 3.4 — "Migrating data with a Python transform"

**Symptom:** you need to backfill a column with a value derived from a complex
Python function (parsing, hashing, calling a regex library).

**Tooling:** `plpython3u`.

```sql
CREATE OR REPLACE FUNCTION app.normalize_email(raw text) RETURNS text
LANGUAGE plpython3u AS $$
import re
return re.sub(r'\s+', '', raw.strip().lower())
$$;

UPDATE app.users
   SET email_normalized = app.normalize_email(email)
 WHERE email_normalized IS NULL;

DROP FUNCTION app.normalize_email(text);  -- remove after backfill if one-shot
```

**Why this works:** plpython3u gives you the full Python standard library inside
a single SQL statement, so you avoid pulling rows into the app, transforming,
and writing back.

---

## 4. Maintenance automation

### 4.1 — "Delete soft-deleted rows after 30 days"

**Tooling:** `pg_cron`.
```sql
SELECT cron.schedule(
  'expire-soft-deleted',
  '0 3 * * *',
  $$ DELETE FROM app.users
       WHERE deleted_at IS NOT NULL
         AND deleted_at < now() - interval '30 days' $$
);

-- inspect:
SELECT * FROM cron.job;
SELECT * FROM cron.job_run_details ORDER BY start_time DESC LIMIT 10;
```

**Why this works:** scheduling lives in the database with the data — no extra
service, no env-specific cron config drift.

---

### 4.2 — "Refresh a materialized view every 10 minutes"

```sql
SELECT cron.schedule(
  'refresh-summary',
  '*/10 * * * *',
  $$ REFRESH MATERIALIZED VIEW CONCURRENTLY app.daily_summary $$
);
```
The `CONCURRENTLY` keyword requires a unique index on the MV — without it, the
refresh holds an `ACCESS EXCLUSIVE` lock and blocks readers.

---

### 4.3 — "Run VACUUM on a hot table every night"

```sql
SELECT cron.schedule(
  'vacuum-orders',
  '0 2 * * *',
  $$ VACUUM (ANALYZE) app.orders $$
);
```
Run at low-traffic hours; combine with `pg_squeeze` (§5.4) for tables that
accumulate bloat faster than autovacuum can clean.

---

### 4.4 — "Cross-database job"

**Symptom:** metadata lives in `postgres`, but a maintenance job needs to run in
`analytics_db`.

```sql
-- from the postgres database (where cron lives):
SELECT cron.schedule_in_database(
  'analytics-refresh',
  '*/15 * * * *',
  $$ REFRESH MATERIALIZED VIEW CONCURRENTLY public.report $$,
  'analytics_db'
);
```
**Note:** developer has DML on `cron.job`, so this works without superuser.

---

## 5. Partitioning at scale

### 5.1 — "Convert a 500M-row table to time-partitioned"

**Symptom:** an `events` table grew unbounded; queries that filter by `created_at`
are slow because no index can help past a certain size.

**Tooling:** `pg_partman` (uses native PG declarative partitioning).

#### Step 1 — create a partitioned parent
```sql
CREATE TABLE app.events_p (
  id bigserial,
  ts timestamptz NOT NULL,
  payload jsonb
) PARTITION BY RANGE (ts);

-- pg_partman manages children:
SELECT partman.create_parent(
  p_parent_table => 'app.events_p',
  p_control      => 'ts',
  p_type         => 'native',
  p_interval     => 'daily',
  p_premake      => 7              -- create 7 future partitions ahead
);
```

#### Step 2 — migrate data
For a one-shot copy:
```sql
INSERT INTO app.events_p SELECT * FROM app.events;
ANALYZE app.events_p;
```
For zero-downtime, use a logical replication subscription or `pg_partman`'s
`partition_data_proc()` to chunk it.

#### Step 3 — swap names
```sql
BEGIN;
ALTER TABLE app.events RENAME TO events_old;
ALTER TABLE app.events_p RENAME TO events;
COMMIT;
```

---

### 5.2 — "Auto-create future partitions"

The `pg_partman_bgw` background worker (already loaded in `shared_preload_libraries`)
runs `partman.run_maintenance_proc()` every hour as `admin`. It pre-creates
future partitions per the `premake` setting.

Verify:
```sql
SELECT * FROM partman.part_config WHERE parent_table = 'app.events';
SELECT * FROM partman.part_config_sub;            -- per-partition config
```

---

### 5.3 — "Drop expired partitions automatically"

```sql
UPDATE partman.part_config
   SET retention = '90 days',
       retention_keep_table = false               -- actually drop, don't just detach
 WHERE parent_table = 'app.events';
```
The hourly bgw picks this up; partitions older than 90 days are dropped.

---

### 5.4 — "Reclaim bloat from the hot partition"

`VACUUM` reclaims dead-tuple space but not the file's physical size. After a big
backfill or churn:
```sql
SELECT squeeze.squeeze_table('app', 'events_2026_04_29', NULL, NULL, NULL);
```
This rewrites the partition online — no `ACCESS EXCLUSIVE` lock — and gives the
disk space back.

Combine with `pg_cron`:
```sql
SELECT cron.schedule(
  'squeeze-hot-events',
  '0 4 * * 0',                      -- Sunday 4am
  $$ SELECT squeeze.squeeze_table('app', 'events_today', NULL, NULL, NULL) $$
);
```

---

## 6. Change data capture & event streaming

### 6.1 — "Stream INSERT/UPDATE/DELETE to a downstream consumer"

**Tooling:** `wal2json` + a logical replication slot.

#### Step 1 — create a slot using wal2json
```sql
SELECT pg_create_logical_replication_slot('cdc_slot', 'wal2json');
```

#### Step 2 — make changes in another session
```sql
INSERT INTO app.orders (id, total) VALUES (1, 99.50);
UPDATE app.orders SET total = 100 WHERE id = 1;
DELETE FROM app.orders WHERE id = 1;
```

#### Step 3 — read changes as JSON
```sql
SELECT data
FROM   pg_logical_slot_get_changes('cdc_slot', NULL, NULL,
         'pretty-print', '1',
         'include-types', 'true');
```
You'll get a JSON document per transaction with one entry per change row,
including the schema, table, columns, old values (for updates/deletes), and
new values.

#### Step 4 — clean up
```sql
SELECT pg_drop_replication_slot('cdc_slot');
```

**Note:** `wal_level=logical` is already on; no config change needed.

---

### 6.2 — "Replay a window of changes after a bug"

If you keep the slot open (don't drop it after each consume), `pg_logical_slot_peek_changes`
reads without advancing — useful for re-reading the same window:
```sql
SELECT data FROM pg_logical_slot_peek_changes('cdc_slot', NULL, NULL);
-- inspect, then advance only when sure:
SELECT data FROM pg_logical_slot_get_changes('cdc_slot', NULL, NULL);
```

**Caveat:** an open replication slot pins WAL — disk usage grows until you
consume or drop it.

---

### 6.3 — "Lightweight CDC without Debezium"

Combine wal2json with plpython3u to POST changes to a webhook:
```sql
CREATE OR REPLACE FUNCTION app.publish_changes() RETURNS void
LANGUAGE plpython3u AS $$
import json, urllib.request

rows = plpy.execute("""
  SELECT data FROM pg_logical_slot_get_changes('cdc_slot', NULL, NULL)
""")
for r in rows:
    req = urllib.request.Request(
        'http://my-consumer.internal/cdc',
        data=r['data'].encode(),
        headers={'Content-Type': 'application/json'}
    )
    urllib.request.urlopen(req, timeout=5)
$$;

-- run every 30s via pg_cron:
SELECT cron.schedule('publish-cdc', '*/30 * * * * *', $$ SELECT app.publish_changes() $$);
```

**Why this works:** under load this won't scale like Kafka, but for low-volume
streams it removes a whole tier from your stack.

---

### 6.4 — "Filter which tables to publish"

`wal2json` accepts options at slot read time:
```sql
SELECT data
FROM   pg_logical_slot_get_changes('cdc_slot', NULL, NULL,
         'add-tables',    'app.orders,app.payments',
         'filter-tables', 'app.audit_log',
         'format-version', '2');
```
Combine with PG's native publication filtering for a fully-typed pipeline.

---

## 7. Auditing, compliance & forensics

### 7.1 — "Who accessed customer table this week?"

**Tooling:** `pgaudit` (already capturing every statement) + `jq`.

```bash
jq -r 'select(.message | startswith("AUDIT:") and contains("app.customers"))
       | "\(.timestamp) \(.user_name): \(.message)"' \
   volumes/logs/postgresql-2026-04-2*.json
```
You get one line per audited access, with timestamp, user, and full SQL text.

---

### 7.2 — "Reconstruct a session's activity"

`log_line_prefix = '%m [%p] %q%u@%d '` puts the PID in every log line. Pick a
PID from any audit entry, then pull every log line for that PID from the same
day:
```bash
PID=12345
jq -r --arg p "[$PID]" 'select(.message | contains($p))
                       | "\(.timestamp) \(.error_severity): \(.message)"' \
   volumes/logs/postgresql-$(date -u +%Y-%m-%d).json
```
Caveat: PIDs are reused across reconnects; combine with `application_name` or
`session_id` (in pgaudit) for confidence.

---

### 7.3 — "Catch unexpected DDL"

`pgaudit.log = 'all'` includes the `DDL` class. Filter for it:
```bash
jq -r 'select(.message | startswith("AUDIT:") and contains(",DDL,"))
       | "\(.timestamp) \(.user_name): \(.message)"' \
   volumes/logs/postgresql-$(date -u +%Y-%m-%d).json
```
Pipe to your alerting system; any DDL outside maintenance windows is a flag.

---

### 7.4 — "Verify least-privilege boundaries"

Use `pgtap` to assert that `app` cannot do things it shouldn't:
```sql
BEGIN;
SELECT plan(3);

SET ROLE app;
SELECT throws_ok(
  $$ CREATE TABLE app.smuggled (id int) $$,
  '42501', NULL,                               -- 42501 = insufficient_privilege
  'app cannot create tables'
);
SELECT throws_ok(
  $$ TRUNCATE app.orders $$,
  '42501', NULL,
  'app cannot truncate'
);
SELECT throws_ok(
  $$ SELECT * FROM public.pg_stat_statements $$,
  '42501', NULL,
  'app cannot read pg_stat_statements'
);
RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
```
Run in CI on every schema change. If a developer adds a grant that erodes the
boundary, this fails before merge.

---

## 8. PL/pgSQL development & debugging

### 8.1 — "Step-debug a PL/pgSQL function"

**Tooling:** `pldebugger` (extension name `pldbgapi`) + a client like pgAdmin or
DBeaver.

#### Step 1 — set a breakpoint
In pgAdmin: right-click the function → "Debug" → "Set Breakpoint".

In code (alternative):
```sql
SELECT pldbg_set_breakpoint(
  pldbg_create_listener(),
  'app.calculate_invoice'::regprocedure,
  10                    -- line number
);
```

#### Step 2 — call the function in another session
The debugger session catches at the breakpoint and lets you step / inspect
variables / continue.

#### Step 3 — common uses
- Trace why a `RAISE EXCEPTION` fires intermittently.
- Inspect intermediate values inside a complex CTE-heavy function.
- Validate loop bounds without `RAISE NOTICE` everywhere.

---

### 8.2 — "Unit-test a procedure"

```sql
BEGIN;
SELECT plan(3);

-- setup
INSERT INTO app.orders (id, total) VALUES (1, 100), (2, 200);

-- exercise
SELECT app.apply_discount(0.1);              -- procedure under test

-- assert
SELECT is(total, 90.0::numeric, 'order 1 has 10% off')
FROM app.orders WHERE id = 1;
SELECT is(total, 180.0::numeric, 'order 2 has 10% off')
FROM app.orders WHERE id = 2;
SELECT cmp_ok(
  (SELECT count(*) FROM app.orders WHERE total < 0), '=', 0,
  'no negative totals'
);

SELECT * FROM finish();
ROLLBACK;
```
The `ROLLBACK` undoes the setup; tests are zero-impact.

---

### 8.3 — "Call Python from a function"

```sql
CREATE OR REPLACE FUNCTION app.geocode(addr text) RETURNS text
LANGUAGE plpython3u AS $$
import json, urllib.request, urllib.parse
q = urllib.parse.quote(addr)
with urllib.request.urlopen(f'https://nominatim.openstreetmap.org/search?q={q}&format=json',
                            timeout=5) as r:
    data = json.load(r)
    if data:
        return f"{data[0]['lat']},{data[0]['lon']}"
return None
$$;

UPDATE app.users SET coords = app.geocode(address)
WHERE coords IS NULL;
```
**Caveats:** `plpython3u` is *untrusted* — only superuser can create these
functions, and they have full Python access (file system, network). Use sparingly
and review every function carefully.

---

### 8.4 — "Capture performance of stored procedures"

`pg_stat_statements.track = 'all'` (set in `postgresql.conf`) means statements
*inside* functions are tracked too:
```sql
SELECT calls, mean_exec_time::int, query
FROM   pg_stat_statements
WHERE  query LIKE '%FROM app.orders%'        -- internal query of a function
ORDER  BY mean_exec_time DESC LIMIT 5;
```
The function call appears alongside its internal SQL — you see both the surface
and the substance.

---

## 9. Reporting & analytics

### 9.1 — "Pivot daily counts into a weekly view"

**Tooling:** `tablefunc.crosstab()`.
```sql
SELECT *
FROM crosstab(
  $$ SELECT product_id::text,
            to_char(day, 'Dy')           AS dow,
            sum(amount)::int             AS total
     FROM   app.daily_sales
     GROUP  BY product_id, day
     ORDER  BY 1, 2 $$,
  $$ VALUES ('Mon'),('Tue'),('Wed'),('Thu'),('Fri'),('Sat'),('Sun') $$
) AS ct(product_id text, mon int, tue int, wed int, thu int, fri int, sat int, sun int);
```

---

### 9.2 — "Walk a tree of comments or categories"

```sql
SELECT *
FROM connectby(
  'app.comments',                 -- table
  'id',                           -- key
  'parent_id',                    -- parent reference
  '42',                           -- starting row
  0,                              -- depth (0 = unlimited)
  '/'                             -- path delimiter
) AS t(id int, parent_id int, level int, path text);
```
Result includes a depth column and a `/`-delimited path — useful for indenting
in a UI.

---

### 9.3 — "Find largest tables by total size"

Use the `:sizes` macro from `.psqlrc`:
```sql
:sizes
```
which expands to:
```sql
SELECT schemaname, relname,
       pg_size_pretty(pg_total_relation_size(schemaname||'.'||relname)) AS total
FROM   pg_stat_user_tables
ORDER  BY pg_total_relation_size(schemaname||'.'||relname) DESC;
```

---

### 9.4 — "Per-table cache hit ratio"

```sql
SELECT relname,
       heap_blks_hit,
       heap_blks_read,
       round(heap_blks_hit::numeric /
             nullif(heap_blks_hit + heap_blks_read, 0), 4) AS hit_ratio
FROM   pg_statio_user_tables
ORDER  BY heap_blks_read DESC LIMIT 20;
```
Tables at the top with low `hit_ratio` are candidates for `pg_prewarm` or
schema/index changes that reduce reads.

---

## 10. Capacity planning & load testing

### 10.1 — "How many concurrent connections can this handle?"

```bash
docker exec -e PGPASSWORD=admin postgres-dev pgbench -i -U admin -p 5499 -d postgres
for c in 5 10 20 30 40 45; do
  echo "--- $c clients ---"
  docker exec -e PGPASSWORD=admin postgres-dev \
    pgbench -c $c -j 4 -T 10 -U admin -p 5499 postgres \
    | tail -3
done
```
Watch where TPS plateaus or starts dropping — that's your effective concurrency
ceiling for this config.

---

### 10.2 — "Cost of an index on a write-heavy table"

```bash
# baseline:
docker exec -e PGPASSWORD=admin postgres-dev pgbench \
  -c 8 -j 2 -T 30 -U admin -p 5499 postgres > /tmp/before.txt

# add the index in another shell:
PGPASSWORD=admin psql -h localhost -p 5499 -U admin -d postgres \
  -c 'CREATE INDEX CONCURRENTLY ON pgbench_accounts(bid)'

# repeat:
docker exec -e PGPASSWORD=admin postgres-dev pgbench \
  -c 8 -j 2 -T 30 -U admin -p 5499 postgres > /tmp/after.txt

grep '^tps' /tmp/before.txt /tmp/after.txt
```

---

### 10.3 — "Will it stay healthy under 10× traffic?"

Write a custom pgbench script that mirrors your real query mix:
```sql
-- /tmp/mixed.sql
\set aid random(1, 1000000)
\set bid random(1, 100)

SELECT * FROM pgbench_accounts WHERE aid = :aid;
UPDATE pgbench_accounts SET abalance = abalance + 1 WHERE aid = :aid;
INSERT INTO pgbench_history (tid, bid, aid, delta) VALUES (1, :bid, :aid, 1);
```
Then:
```bash
docker cp /tmp/mixed.sql postgres-dev:/tmp/mixed.sql
docker exec -e PGPASSWORD=admin postgres-dev pgbench \
  -f /tmp/mixed.sql -c 40 -j 8 -T 60 -U admin -p 5499 postgres
```
Watch `pg_activity` simultaneously to see lock waits / IO bottlenecks under load.

---

## 11. RLS & security validation

### 11.1 — "Catch an over-permissive grant"

```sql
BEGIN;
SELECT plan(2);

SELECT ok(
  NOT has_table_privilege('app', 'app.audit_log', 'SELECT'),
  'app cannot read audit_log'
);
SELECT ok(
  NOT has_table_privilege('developer', 'app.audit_log', 'TRUNCATE'),
  'developer cannot truncate audit_log'
);

SELECT * FROM finish();
ROLLBACK;
```

---

### 11.2 — "Verify RLS policies before deploy"

```sql
BEGIN;
SELECT plan(3);

-- setup
INSERT INTO app.docs (id, owner, body) VALUES
  (1, 'alice', 'a'), (2, 'bob', 'b'), (3, 'developer', 'd');

-- developer (NOBYPASSRLS) sees only their own row:
SET ROLE developer;
SELECT is( (SELECT count(*) FROM app.docs)::int, 1, 'developer sees 1 row');
SELECT is( (SELECT owner   FROM app.docs)::text, 'developer', 'developer sees only their row');
RESET ROLE;

-- admin (BYPASSRLS) sees all:
SELECT is( (SELECT count(*) FROM app.docs)::int, 3, 'admin sees all 3 rows');

SELECT * FROM finish();
ROLLBACK;
```

---

### 11.3 — "Audit what role X can actually do"

```sql
SELECT pg_has_role('developer', 'role_developer', 'MEMBER') AS in_role_developer,
       has_table_privilege('developer', 'app.orders', 'SELECT,INSERT,UPDATE,DELETE') AS dml_app,
       has_schema_privilege('developer', 'public', 'CREATE') AS create_public;

-- across all tables, grouped:
SELECT table_schema, table_name,
       string_agg(privilege_type, ',' ORDER BY privilege_type) AS perms
FROM information_schema.table_privileges
WHERE grantee = 'role_developer'
GROUP BY 1,2 ORDER BY 1,2;
```

---

## 12. Daily DX shortcuts

### 12.1 — "Make psql sing for me"

```bash
scripts/psql-admin.sh
# → connects with timing on, NULL as ∅, unicode tables, pspg pager,
#   verbose errors, ON_ERROR_STOP, per-database history
```
Inside, try:
```
:slow            -- top 20 slow queries
:activity        -- live pg_stat_activity
:locks           -- granted/blocked locks
:settings        -- non-default config
:sizes           -- largest tables
```

For autocomplete + syntax highlighting:
```bash
docker exec -it -e PGPASSWORD=admin postgres-dev pgcli -U admin -p 5499 -d postgres
```

---

### 12.2 — "Stop typing the same diagnostics queries"

Add your own to `config/psqlrc` (it's a regular file, edit and rebuild):
```
\set explain 'EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)'
\set bloat 'SELECT schemaname, relname, n_dead_tup, n_live_tup, ...'
\set idle 'SELECT pid, query, age(now(), state_change) AS idle FROM pg_stat_activity WHERE state = ''idle in transaction'';'
```
Then in any session:
```sql
:idle
```

---

### 12.3 — "Read the JSON log live"

```bash
scripts/logs.sh                 # follow today's JSON log, pretty-printed
scripts/logs.sh 50              # last 50 lines instead of follow
```

Custom filters:
```bash
# only ERRORs:
tail -F volumes/logs/postgresql-$(date -u +%Y-%m-%d).json \
  | jq -r 'select(.error_severity == "ERROR")
           | "\(.timestamp) [\(.user_name)@\(.database_name)] \(.message)"'

# only AUDIT entries from a specific user:
tail -F volumes/logs/postgresql-$(date -u +%Y-%m-%d).json \
  | jq -r 'select(.message | startswith("AUDIT:")) | select(.user_name == "app")
           | "\(.timestamp) \(.message)"'

# slow queries logged by auto_explain:
tail -F volumes/logs/postgresql-$(date -u +%Y-%m-%d).json \
  | jq -r 'select(.message | startswith("duration:")) | .message'
```

---

## 13. Backup, restore, and PITR with Barman

### 13.1 — "Take an out-of-band backup"

**Symptom:** about to ship a risky migration; want a verified snapshot beyond
the next scheduled weekly backup.

**Tooling:** `barman-backup` (helper that wraps `barman backup postgres-dev`).

```bash
docker exec postgres-dev barman-backup
# → Backup completed (start time: ..., elapsed time: ~20 seconds)
# → Backup size: ~28 MiB for an empty cluster

docker exec postgres-dev barman-list
# → postgres-dev 20260430T120000 - F - ... - Size: 28 MiB - WAL Size: 0 B
```

The backup ID is the timestamp (`20260430T120000`). Note it for §13.3 below
in case you need to restore exactly to "right before that migration".

**Why this works:** `pg_basebackup` over the streaming replication slot
copies all data files atomically without locking. WAL is preserved
continuously by `barman cron`, so PITR works against this backup point.

---

### 13.2 — "Restore the latest backup to a sandbox cluster"

**Symptom:** want to verify the backup actually restores cleanly, or you need
a copy of yesterday's state to compare against today's.

**Tooling:** `barman-restore-latest` + `pg_ctl` on a different port.

```bash
# Restore into a fresh directory inside the container:
docker exec postgres-dev barman-restore-latest /tmp/recover

# Boot it on port 5599 with a private socket dir:
docker exec -u barman postgres-dev /usr/pgsql-17/bin/pg_ctl \
  -D /tmp/recover \
  -o "-p 5599 -c listen_addresses=localhost -c unix_socket_directories=/tmp" \
  -l /tmp/recover/recovery.log start

# Query — the recovered cluster is read-write and independent of the live one:
docker exec -u barman -e PGPASSWORD=admin postgres-dev /usr/pgsql-17/bin/psql \
  -h /tmp -p 5599 -U admin -d postgres -c "SELECT count(*) FROM app.orders;"

# When done, stop it:
docker exec -u barman postgres-dev /usr/pgsql-17/bin/pg_ctl -D /tmp/recover stop -m fast
```

**Why this works:** `barman recover` produces a complete PGDATA. Booting it on
a non-default port avoids any clash with the live cluster on 5499.

---

### 13.3 — "I dropped the wrong table" — point-in-time recovery

**Symptom:** at 14:17:22 someone ran `DROP TABLE orders` in the live cluster.
You need to recover the data as it existed at 14:17:21.

**Tooling:** `barman-restore-pitr`.

#### Step 1 — find a basebackup that ENDED before the disaster
```bash
docker exec postgres-dev barman-list
# 20260430T120000 ended at  Sat Apr 30 12:00:18 2026  ← this one is fine
# 20260430T140000 ended at  Sat Apr 30 14:18:32 2026  ← TOO LATE — finished AFTER drop
```
Pick a backup whose end time is before your PITR target.

#### Step 2 — restore to a sandbox dir, replay WAL up to disaster - 1 second
```bash
docker exec postgres-dev rm -rf /tmp/oops && \
  docker exec postgres-dev mkdir -p /tmp/oops && \
  docker exec postgres-dev chown barman:barman /tmp/oops

# Use --target-action pause so you can query the recovered state:
docker exec postgres-dev sudo -u barman /usr/bin/barman recover postgres-dev \
  20260430T120000 /tmp/oops \
  --target-time '2026-04-30 14:17:21+00' \
  --target-action pause
```

#### Step 3 — boot the recovered cluster, dump the lost table
```bash
docker exec -u barman postgres-dev /usr/pgsql-17/bin/pg_ctl \
  -D /tmp/oops \
  -o "-p 5599 -c listen_addresses=localhost -c unix_socket_directories=/tmp" \
  -l /tmp/oops/recovery.log start

# Verify the table exists at the recovered point:
docker exec -u barman -e PGPASSWORD=admin postgres-dev /usr/pgsql-17/bin/psql \
  -h /tmp -p 5599 -U admin -d postgres -c "SELECT count(*) FROM app.orders;"

# Dump just that table (recovered cluster is read-only with --target-action pause):
docker exec -u barman -e PGPASSWORD=admin postgres-dev /usr/pgsql-17/bin/pg_dump \
  -h /tmp -p 5599 -U admin -d postgres -t app.orders -f /tmp/orders.sql

# Stop the sandbox:
docker exec -u barman postgres-dev /usr/pgsql-17/bin/pg_ctl -D /tmp/oops stop -m immediate
```

#### Step 4 — restore the dump into the live cluster
```bash
docker cp postgres-dev:/tmp/orders.sql ./orders.sql
PGPASSWORD=admin psql -h localhost -p 5499 -U admin -d postgres -f orders.sql
```

**Why this works:** `--target-action pause` halts WAL replay at the target
time and leaves the cluster up read-only. You can `pg_dump` any subset and
re-import without overwriting parts of the live cluster you didn't want
rolled back.

**Caveat:** if the target time is BEFORE the basebackup's end time, Barman
will refuse — pick an earlier backup. The `barman list-backup` "Status" or
"End Time" column tells you which.

---

### 13.4 — "Verify a backup is good before you need it"

**Symptom:** you don't want the first time you restore to be during an
incident.

**Tooling:** `barman-check` (daily cron) + a periodic restore drill.

```bash
# Quick health check — verifies WAL streaming, replication slot,
# pg_basebackup compatibility, retention policy, etc.
docker exec postgres-dev barman-check
# Expected: every line ends with "OK"

# Full drill: restore latest into a sandbox and boot it (see §13.2).
# If this passes, your backups are real.
```

The cron job at 06:00 UTC daily runs the same `barman check` and writes to
`/var/log/barman/daily-check.log` inside the container. Anything other than
"OK" is a flag.

---

### 13.5 — "Recover when storage hits the cap"

**Symptom:** `./backups/` is at 5 GB and growing; the cleanup script just
deleted your oldest weekly backup.

**Tooling:** `barman-cleanup` script + `BACKUP_LIMIT_BYTES` override.

#### Step 1 — see what's using space
```bash
du -sh ./backups
docker exec postgres-dev sudo -u barman du -sh /var/lib/barman/postgres-dev/*
# typical breakdown:
#   base/   ← basebackups (recent + older retention)
#   wals/   ← WAL stream archive
#   streaming/ ← in-flight WAL from receive-wal
```

#### Step 2 — raise the cap if you really need more retention
```bash
# Inside the container (/etc/barman-cleanup.conf is read by the cleanup script):
docker exec postgres-dev sh -c \
  'echo "BACKUP_LIMIT_BYTES=$((10 * 1024 * 1024 * 1024))" > /etc/barman-cleanup.conf'
# (10 GB now)
```
Persists for the life of the container; bake into the image if you want it
permanent (edit `scripts/barman-cleanup.sh` default and rebuild).

#### Step 3 — or shrink retention to fit
Edit `config/barman.d/postgres-dev.conf`:
```
retention_policy = RECOVERY WINDOW OF 7 DAYS
```
Then `docker compose restart postgres` (no rebuild needed since `./config/`
is bind-mounted). Next `barman cron` enforces the new policy.

**Why this works:** the cleanup script and the retention policy are
independent — cleanup is a hard cap on disk usage; retention_policy is
Barman's normal "keep enough basebackups to support the recovery window".
Tighten either to fit your storage budget.

---

## See also
- [README.md](../README.md) — environment overview and feature list
- [pg_optimization_decision_tree.html](pg_optimization_decision_tree.html) — interactive decision tree for general PG perf tuning
- [PLAN.md](PLAN.md) — architectural decisions
- [TASKS.md](TASKS.md) — implementation slice tracker
- [../config/psqlrc](../config/psqlrc) — interactive psql defaults (commented)
