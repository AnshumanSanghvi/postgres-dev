#!/usr/bin/env bash
# =============================================================================
# Storage guardrail (S17). Runs every 15 min via cron as root.
#
# If /var/lib/barman exceeds the BACKUP_LIMIT_BYTES threshold, deletes the
# oldest basebackup repeatedly until under threshold. Then always runs
# `barman cron` to enforce normal retention policy.
#
# Default threshold: 5 GB (overridable via /etc/barman-cleanup.conf).
# =============================================================================
set -euo pipefail

DEFAULT_LIMIT_BYTES=$((5 * 1024 * 1024 * 1024))
BACKUP_LIMIT_BYTES="${BACKUP_LIMIT_BYTES:-$DEFAULT_LIMIT_BYTES}"
[[ -f /etc/barman-cleanup.conf ]] && . /etc/barman-cleanup.conf

current() {
  du -sb /var/lib/barman 2>/dev/null | awk '{print $1}'
}

human() {
  numfmt --to=iec --suffix=B "$1"
}

now=$(current)
limit=$BACKUP_LIMIT_BYTES

if [[ "$now" -gt "$limit" ]]; then
  echo "[$(date -Iseconds)] /var/lib/barman at $(human "$now") > limit $(human "$limit") — pruning"

  # Loop: delete the oldest backup until we're under threshold.
  # `barman list-backup --minimal postgres-dev` outputs IDs newest-first, so
  # `tail -1` is the oldest.
  while :; do
    now=$(current)
    [[ "$now" -le "$limit" ]] && break

    oldest=$(sudo -u barman /usr/bin/barman list-backup --minimal postgres-dev 2>/dev/null | tail -1 || true)
    if [[ -z "$oldest" ]]; then
      echo "[$(date -Iseconds)] no more backups to delete; storage at $(human "$now")"
      break
    fi

    echo "[$(date -Iseconds)] deleting backup ${oldest}"
    sudo -u barman /usr/bin/barman delete postgres-dev "${oldest}" || {
      echo "[$(date -Iseconds)] delete failed for ${oldest}; aborting cleanup"
      exit 1
    }
  done

  echo "[$(date -Iseconds)] storage now $(human "$(current)")"
fi

# Always run barman cron to apply normal retention policy and start/restart
# receive-wal as needed.
sudo -u barman /usr/bin/barman cron >/dev/null 2>&1 || true
