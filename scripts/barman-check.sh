#!/usr/bin/env bash
# Run barman's health check for postgres-dev. Non-zero exit indicates a problem.
# Usage: docker exec postgres-dev barman-check
set -euo pipefail
exec sudo -u barman /usr/bin/barman check postgres-dev "$@"
