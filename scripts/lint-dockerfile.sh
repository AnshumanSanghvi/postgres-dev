#!/usr/bin/env bash
# Lint the Dockerfile with hadolint.
# Uses the hadolint Docker image so contributors don't need a local install.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

if [[ ! -f Dockerfile ]]; then
  echo "No Dockerfile found in $REPO_ROOT" >&2
  exit 1
fi

if command -v hadolint >/dev/null 2>&1; then
  exec hadolint --config .hadolint.yaml Dockerfile
fi

# Fallback: run hadolint via Docker
exec docker run --rm -i \
  -v "$REPO_ROOT/.hadolint.yaml:/.config/hadolint.yaml:ro" \
  hadolint/hadolint hadolint --config /.config/hadolint.yaml - < Dockerfile
