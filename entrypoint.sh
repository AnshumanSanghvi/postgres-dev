#!/usr/bin/env bash
# ============================================================================
# Postgres Dev Environment — container entrypoint
#
#   Phase 1 (root):  Bind-mounted volumes from the host arrive owned by the
#                    host UID/GID. On Linux we can chown them; on Docker
#                    Desktop for Mac (virtiofs), chown across the boundary
#                    is restricted. Instead we align the in-container
#                    postgres user to the host's UID/GID — no chown needed.
#                    Then re-exec as that user.
#   Phase 2 (postgres): on first boot, run initdb with explicit locale and
#                    scram-sha-256 auth (password from $POSTGRES_PASSWORD).
#                    On every boot, exec the CMD in the foreground.
# ============================================================================
set -Eeuo pipefail

if [[ "$(id -u)" == "0" ]]; then
  mkdir -p "${PGDATA}" /var/log/postgresql

  data_uid="$(stat -c '%u' /var/lib/pgsql/data)"
  data_gid="$(stat -c '%g' /var/lib/pgsql/data)"
  pg_uid="$(id -u postgres)"
  pg_gid="$(id -g postgres)"

  if [[ "${data_uid}" != "${pg_uid}" || "${data_gid}" != "${pg_gid}" ]]; then
    echo "[entrypoint] aligning postgres user to host uid:${data_uid} gid:${data_gid}"
    # -o = allow non-unique IDs (the host UID may already exist in /etc/passwd)
    groupmod -o -g "${data_gid}" postgres
    usermod  -o -u "${data_uid}" -g "${data_gid}" postgres
  fi

  # chown is best-effort: succeeds on Linux, may be a no-op on macOS Docker
  # Desktop bind mounts. UID alignment above makes the chown unnecessary for
  # the bind mounts. Image-internal dirs (/run/postgresql) MUST be chowned
  # so the now-aligned postgres user can write the unix socket lock file.
  chown -R postgres:postgres /var/lib/pgsql /var/log/postgresql /run/postgresql 2>/dev/null || true
  chmod 700 "${PGDATA}"

  exec runuser -u postgres -- "$0" "$@"
fi

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
else
  echo "[entrypoint] existing cluster at ${PGDATA} — skipping initdb"
fi

exec "$@"
