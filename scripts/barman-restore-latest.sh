#!/usr/bin/env bash
# Restore the latest backup to a target directory.
# IMPORTANT: this does NOT touch the running cluster. It restores to a path
# you must specify, suitable for spinning up a recovery instance separately.
#
# Usage:
#   docker exec postgres-dev barman-restore-latest /tmp/recover-target
#   # then start a postgres process pointing at /tmp/recover-target on a
#   # different port (or stop the live cluster and rsync the recovered files
#   # into PGDATA — only do this if you really mean to overwrite live data).
set -euo pipefail

TARGET="${1:-}"
if [[ -z "$TARGET" ]]; then
  echo "usage: $0 <target-directory>" >&2
  echo "  example: $0 /tmp/recover" >&2
  exit 2
fi

mkdir -p "$TARGET"
chown barman:barman "$TARGET" 2>/dev/null || true

echo "[barman-restore-latest] restoring latest backup of postgres-dev → $TARGET"
exec sudo -u barman /usr/bin/barman recover postgres-dev latest "$TARGET" \
       --target-action shutdown \
       --remote-ssh-command="" \
       "${@:2}"
