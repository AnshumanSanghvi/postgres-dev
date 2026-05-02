#!/usr/bin/env bash
# Point-in-time recovery: restore latest basebackup, then replay WAL up to the
# given target timestamp. The target must be within the recovery window
# (default: last 30 days).
#
# Usage:
#   docker exec postgres-dev barman-restore-pitr <target-dir> '<YYYY-MM-DD HH:MM:SS UTC>'
# Example:
#   docker exec postgres-dev barman-restore-pitr /tmp/pitr '2026-04-30 12:00:00 UTC'
set -euo pipefail

TARGET="${1:-}"
PITR="${2:-}"

if [[ -z "$TARGET" || -z "$PITR" ]]; then
  echo "usage: $0 <target-directory> '<YYYY-MM-DD HH:MM:SS UTC>'" >&2
  echo "" >&2
  echo "  Restores latest basebackup to <target-directory>, then replays WAL" >&2
  echo "  up to the given timestamp." >&2
  exit 2
fi

mkdir -p "$TARGET"
chown barman:barman "$TARGET" 2>/dev/null || true

echo "[barman-restore-pitr] restoring postgres-dev → $TARGET (target time: $PITR)"
exec sudo -u barman /usr/bin/barman recover postgres-dev latest "$TARGET" \
       --target-time "$PITR" \
       --target-action shutdown \
       --remote-ssh-command=""
