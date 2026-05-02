#!/usr/bin/env bash
# Take a manual backup of postgres-dev.
# Useful for ad-hoc snapshots outside the weekly/monthly cron schedule.
# Usage:  docker exec postgres-dev barman-backup
#         (or, from host) docker exec postgres-dev barman-backup --immediate-checkpoint
set -euo pipefail
exec sudo -u barman /usr/bin/barman backup postgres-dev "$@"
