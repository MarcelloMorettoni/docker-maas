#!/bin/bash
set -euo pipefail

GUNICORN_BIN="${MAAS_HTTP_GUNICORN_BIN:-}"
if [[ -z "${GUNICORN_BIN}" ]]; then
  if command -v gunicorn >/dev/null 2>&1; then
    GUNICORN_BIN="$(command -v gunicorn)"
  elif command -v gunicorn3 >/dev/null 2>&1; then
    GUNICORN_BIN="$(command -v gunicorn3)"
  else
    echo "Unable to locate gunicorn binary. Install gunicorn or set MAAS_HTTP_GUNICORN_BIN." >&2
    exit 1
  fi
fi

MAAS_HTTP_BIND="${MAAS_HTTP_BIND:-0.0.0.0:5240}"
MAAS_HTTP_WORKERS="${MAAS_HTTP_WORKERS:-4}"
MAAS_HTTP_THREADS="${MAAS_HTTP_THREADS:-2}"
MAAS_HTTP_TIMEOUT="${MAAS_HTTP_TIMEOUT:-120}"
MAAS_HTTP_APP="${MAAS_HTTP_APP:-maasserver.wsgi:application}"
MAAS_HTTP_PIDFILE="${MAAS_HTTP_PIDFILE:-/run/maas/maas-http.pid}"
MAAS_HTTP_LOG_DIR="${MAAS_HTTP_LOG_DIR:-/var/log/maas}"
MAAS_HTTP_ACCESS_LOG="${MAAS_HTTP_ACCESS_LOG:-${MAAS_HTTP_LOG_DIR}/maas-http-access.log}"
MAAS_HTTP_ERROR_LOG="${MAAS_HTTP_ERROR_LOG:-${MAAS_HTTP_LOG_DIR}/maas-http-error.log}"
MAAS_HTTP_LOG_LEVEL="${MAAS_HTTP_LOG_LEVEL:-info}"

mkdir -p "${MAAS_HTTP_LOG_DIR}"
if [[ -n "${MAAS_HTTP_PIDFILE}" ]]; then
  mkdir -p "$(dirname "${MAAS_HTTP_PIDFILE}")"
fi

export DJANGO_SETTINGS_MODULE="${DJANGO_SETTINGS_MODULE:-maasserver.settings}"
export LANG="${LANG:-C.UTF-8}"
export LC_ALL="${LC_ALL:-C.UTF-8}"

exec "${GUNICORN_BIN}" \
  --bind "${MAAS_HTTP_BIND}" \
  --workers "${MAAS_HTTP_WORKERS}" \
  --threads "${MAAS_HTTP_THREADS}" \
  --timeout "${MAAS_HTTP_TIMEOUT}" \
  --graceful-timeout 30 \
  --limit-request-line 8190 \
  --pid "${MAAS_HTTP_PIDFILE}" \
  --access-logfile "${MAAS_HTTP_ACCESS_LOG}" \
  --error-logfile "${MAAS_HTTP_ERROR_LOG}" \
  --capture-output \
  --log-level "${MAAS_HTTP_LOG_LEVEL}" \
  "${MAAS_HTTP_APP}"
