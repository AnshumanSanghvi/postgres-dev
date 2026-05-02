#!/usr/bin/env bash
# List backups for postgres-dev.
# Usage: docker exec postgres-dev barman-list
set -euo pipefail
echo "=== backups ==="
sudo -u barman /usr/bin/barman list-backup postgres-dev
echo ""
echo "=== server status ==="
sudo -u barman /usr/bin/barman show-server postgres-dev | head -40
