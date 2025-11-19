#!/bin/bash
set -euo pipefail

TEMPORAL_HOST=${TEMPORAL_HOST:-127.0.0.1}
TEMPORAL_PORT=${TEMPORAL_PORT:-7233}
TEMPORAL_WAIT_SECS=${TEMPORAL_WAIT_SECS:-60}

log() {
  printf '[regiond-wrapper] %s\n' "$*"
}

check_temporal() {
  python3 - "$TEMPORAL_HOST" "$TEMPORAL_PORT" <<'PY'
import socket
import sys
host = sys.argv[1]
port = int(sys.argv[2])
try:
    with socket.create_connection((host, port), timeout=1.0):
        pass
except OSError:
    sys.exit(1)
else:
    sys.exit(0)
PY
}

elapsed=0
until check_temporal; do
  if (( elapsed >= TEMPORAL_WAIT_SECS )); then
    log "Temporal server is still unavailable at ${TEMPORAL_HOST}:${TEMPORAL_PORT} after ${TEMPORAL_WAIT_SECS}s"
    exit 1
  fi
  log "Waiting for Temporal at ${TEMPORAL_HOST}:${TEMPORAL_PORT}..."
  sleep 2
  elapsed=$((elapsed + 2))
done

log "Temporal is reachable; launching regiond"
exec /usr/sbin/regiond
