#!/usr/bin/env bash
# Tail today's JSON log file with jq pretty-printing.
# Usage: scripts/logs.sh [N]    where N is the number of trailing lines (default: follow)
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

today_log="volumes/logs/postgresql-$(date -u +%Y-%m-%d).json"

if [[ ! -f "$today_log" ]]; then
  echo "[logs] no log file at $today_log yet (postgres may not have flushed)" >&2
  echo "[logs] available files:" >&2
  ls -1 volumes/logs/*.json 2>/dev/null || echo "  (none)"
  exit 1
fi

if [[ $# -gt 0 ]]; then
  tail -n "$1" "$today_log" | jq -r '"\(.timestamp) [\(.error_severity)] \(.user_name // "-")@\(.database_name // "-") \(.message)"'
else
  tail -F "$today_log" | jq -r '"\(.timestamp) [\(.error_severity)] \(.user_name // "-")@\(.database_name // "-") \(.message)"'
fi
