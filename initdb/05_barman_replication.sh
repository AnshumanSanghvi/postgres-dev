#!/usr/bin/env bash
# =============================================================================
# 05_barman_replication.sh — create the Barman replication user + slot (S17)
#
# Runs once on first boot, after roles (03) and before pg_cron (06).
# Reads BARMAN_USER and BARMAN_PASSWORD from the environment (sourced from
# .env via compose). Creates a LOGIN+REPLICATION role with the privileges
# Barman 3.18 needs to run `check`, `backup`, and `switch-wal`, plus a
# physical replication slot named `barman_slot`.
# =============================================================================
set -Eeuo pipefail

: "${BARMAN_USER:?BARMAN_USER must be set}"
: "${BARMAN_PASSWORD:?BARMAN_PASSWORD must be set}"

echo "[05_barman_replication] creating ${BARMAN_USER} and barman_slot"

psql -v ON_ERROR_STOP=1 \
     -v barman_user="${BARMAN_USER}" \
     -v barman_pw="${BARMAN_PASSWORD}" \
     -U postgres -h /tmp -p 5499 -d postgres <<-'EOSQL'

-- Replication user. NOSUPERUSER, NOCREATEDB, NOCREATEROLE — just enough
-- privilege to stream WAL, run pg_basebackup, and let `barman check` and
-- `barman switch-wal` succeed.
CREATE ROLE :"barman_user" LOGIN REPLICATION
       NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS
       PASSWORD :'barman_pw';

-- Built-in roles that Barman 3.18 requires for `barman check` and friends.
-- pg_read_all_settings : read pg_settings completely
-- pg_read_all_stats    : read pg_stat_* (replication state, archiver state)
-- pg_checkpoint        : run CHECKPOINT (used by `barman switch-wal --force`)
GRANT pg_read_all_settings, pg_read_all_stats, pg_checkpoint
   TO :"barman_user";

-- Function-level EXECUTE grants. Barman 3.18 calls these directly during
-- `barman switch-wal` and `barman backup`. Default is superuser-only;
-- granting EXECUTE is the standard "barman pre-requisites" recipe for
-- PG14+ when the barman user is non-superuser.
GRANT EXECUTE ON FUNCTION pg_switch_wal()                       TO :"barman_user";
GRANT EXECUTE ON FUNCTION pg_create_restore_point(text)         TO :"barman_user";
GRANT EXECUTE ON FUNCTION pg_backup_start(text, boolean)        TO :"barman_user";
GRANT EXECUTE ON FUNCTION pg_backup_stop(boolean)               TO :"barman_user";

-- Physical replication slot used by Barman for streaming WAL. Persisting it
-- here (vs. letting Barman create it on first connect) means the slot
-- survives a Barman restart without losing WAL position.
SELECT pg_create_physical_replication_slot('barman_slot');

EOSQL

echo "[05_barman_replication] done"
