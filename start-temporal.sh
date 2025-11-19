#!/bin/bash
set -euo pipefail

TEMPORAL_PORT=${TEMPORAL_PORT:-7233}
TEMPORAL_UI_PORT=${TEMPORAL_UI_PORT:-8233}
TEMPORAL_NAMESPACE=${TEMPORAL_NAMESPACE:-maas-internal}
TEMPORAL_DB_FILE=${TEMPORAL_DB_FILE:-/var/lib/maas/temporal/temporal.sqlite}

mkdir -p "$(dirname "$TEMPORAL_DB_FILE")"

exec temporal server start-dev \
  --ip 0.0.0.0 \
  --port "${TEMPORAL_PORT}" \
  --db-filename "${TEMPORAL_DB_FILE}" \
  --ui-port "${TEMPORAL_UI_PORT}" \
  --namespace "${TEMPORAL_NAMESPACE}"
