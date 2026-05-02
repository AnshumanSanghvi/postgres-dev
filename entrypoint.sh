#!/usr/bin/env bash
# ============================================================================
# Postgres Dev Environment — container entrypoint
#
#   Phase 1 (root):       align in-container postgres UID/GID to the
#                         bind-mounted PGDATA owner (so chown is unnecessary
#                         on Docker Desktop Mac), then re-exec as postgres.
#   Phase 2 (postgres):   on first boot, initdb + run /docker-entrypoint-initdb.d
#                         scripts in alphabetical order. On every boot, exec the
#                         CMD (postgres) in the foreground.
# ============================================================================
set -Eeuo pipefail

INIT_DIR=/docker-entrypoint-initdb.d

# ---------------------------------------------------------------------------
# Phase 1: root — align UID/GID
# ---------------------------------------------------------------------------
if [[ "$(id -u)" == "0" ]]; then
  mkdir -p "${PGDATA}" /var/log/postgresql /var/log/barman /var/lib/barman

  data_uid="$(stat -c '%u' /var/lib/pgsql/data)"
  data_gid="$(stat -c '%g' /var/lib/pgsql/data)"
  pg_uid="$(id -u postgres)"
  pg_gid="$(id -g postgres)"

  if [[ "${data_uid}" != "${pg_uid}" || "${data_gid}" != "${pg_gid}" ]]; then
    echo "[entrypoint] aligning postgres user to host uid:${data_uid} gid:${data_gid}"
    groupmod -o -g "${data_gid}" postgres
    usermod  -o -u "${data_uid}" -g "${data_gid}" postgres
  fi

  # S17: align barman to the bind-mounted /var/lib/barman owner UID/GID
  # (Docker Desktop Mac restricts chown across virtiofs).
  barman_data_uid="$(stat -c '%u' /var/lib/barman)"
  barman_data_gid="$(stat -c '%g' /var/lib/barman)"
  if [[ "${barman_data_uid}" != "$(id -u barman)" || "${barman_data_gid}" != "$(id -g barman)" ]]; then
    echo "[entrypoint] aligning barman user to host uid:${barman_data_uid} gid:${barman_data_gid}"
    groupmod -o -g "${barman_data_gid}" barman
    usermod  -o -u "${barman_data_uid}" -g "${barman_data_gid}" barman
  fi

  chown -R postgres:postgres /var/lib/pgsql /var/log/postgresql /run/postgresql 2>/dev/null || true
  chown -R barman:barman   /var/lib/barman /var/log/barman              2>/dev/null || true
  chmod 700 "${PGDATA}"
  chmod 700 /var/lib/barman

  # S17: generate ~barman/.pgpass so barman can authenticate as $BARMAN_USER
  # without the password appearing in process args or env. .pgpass requires
  # 0600 perms — postgres rejects it otherwise.
  if [[ -n "${BARMAN_USER:-}" && -n "${BARMAN_PASSWORD:-}" ]]; then
    {
      echo "127.0.0.1:5499:*:${BARMAN_USER}:${BARMAN_PASSWORD}"
      echo "localhost:5499:*:${BARMAN_USER}:${BARMAN_PASSWORD}"
    } > /var/lib/barman/.pgpass
    chown barman:barman /var/lib/barman/.pgpass
    chmod 600           /var/lib/barman/.pgpass
  fi

  # S17: start cron in the background as root. Cron entries in /etc/cron.d/barman
  # specify barman/root user as needed. `crond -n` runs in foreground; we send
  # it to background here so the entrypoint can continue to `exec postgres`.
  # If cron dies, container stays alive (postgres is the supervisor). The first
  # few cron iterations will fail until postgres is accepting connections —
  # that's fine, errors are logged to /var/log/barman/cron.log.
  if [[ -x /usr/sbin/crond ]]; then
    echo "[entrypoint] starting crond in background"
    /usr/sbin/crond -n -m off &
  fi

  exec runuser -u postgres -- "$0" "$@"
fi

# ---------------------------------------------------------------------------
# Phase 2: postgres user
# ---------------------------------------------------------------------------
need_init_scripts=0

if [[ ! -s "${PGDATA}/PG_VERSION" ]]; then
  : "${POSTGRES_PASSWORD:?POSTGRES_PASSWORD must be set on first boot}"

  echo "[entrypoint] initializing new cluster at ${PGDATA}"
  initdb \
    --username=postgres \
    --pwfile=<(printf '%s' "${POSTGRES_PASSWORD}") \
    --auth-host=scram-sha-256 \
    --auth-local=scram-sha-256 \
    --encoding=UTF8 \
    --locale=C.UTF-8 \
    --pgdata="${PGDATA}"
  echo "[entrypoint] initdb complete"
  need_init_scripts=1
fi

# Run /docker-entrypoint-initdb.d scripts on first boot only.
# Postgres is started temporarily on a local-only socket so the scripts can
# connect; then stopped before we exec the real CMD.
if [[ "${need_init_scripts}" == "1" ]] && compgen -G "${INIT_DIR}/*" >/dev/null; then
  echo "[entrypoint] running init scripts from ${INIT_DIR}"

  pg_ctl -D "${PGDATA}" \
    -o "-c listen_addresses='' \
        -c config_file=/etc/postgresql/postgresql.conf \
        -c hba_file=/etc/postgresql/pg_hba.conf" \
    -w -t 30 start

  export PGPASSWORD="${POSTGRES_PASSWORD}"
  for f in "${INIT_DIR}"/*; do
    case "$f" in
      *.sh)     echo "[entrypoint]   . $f" ; bash "$f" ;;
      *.sql)    echo "[entrypoint]   * $f" ; psql -U postgres -d postgres -p 5499 -h /tmp -v ON_ERROR_STOP=1 -f "$f" ;;
      *.sql.gz) echo "[entrypoint]   * $f" ; gunzip -c "$f" | psql -U postgres -d postgres -p 5499 -h /tmp -v ON_ERROR_STOP=1 ;;
      *)        echo "[entrypoint]   ? $f (ignored)" ;;
    esac
  done
  unset PGPASSWORD

  pg_ctl -D "${PGDATA}" -m fast -w stop
  echo "[entrypoint] init scripts complete"
fi

exec "$@"
