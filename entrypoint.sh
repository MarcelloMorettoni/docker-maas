#!/bin/bash
set -euo pipefail

DB_URI="postgres://${MAAS_DB_USER}:${MAAS_DB_PASSWORD}@${MAAS_DB_HOST}:${MAAS_DB_PORT}/${MAAS_DB_NAME}"
INIT_FLAG="/var/lib/maas/.maas-init-done"

echo "Waiting for PostgreSQL at ${MAAS_DB_HOST}:${MAAS_DB_PORT}..."
export PGPASSWORD="${MAAS_DB_PASSWORD}"

until psql "host=${MAAS_DB_HOST} port=${MAAS_DB_PORT} dbname=${MAAS_DB_NAME} user=${MAAS_DB_USER}" -c "SELECT 1;" >/dev/null 2>&1; do
  echo "  ... still waiting for DB ..."
  sleep 2
done
echo "PostgreSQL is ready"

if [ ! -f "${INIT_FLAG}" ]; then
  echo "Running 'maas init' to mirror the LogicWeb guide..."

  INIT_ARGS=(--maas-url "${MAAS_URL}" --database-uri "${DB_URI}")

  echo "Attempting 'maas init' with --mode syntax..."
  if INIT_OUTPUT=$(maas init --mode region+rack "${INIT_ARGS[@]}" 2>&1); then
    printf '%s\n' "$INIT_OUTPUT"
  else
    printf '%s\n' "$INIT_OUTPUT"
    if grep -qiE 'unrecognized argument|unrecognized arguments|unknown option|unknown arguments' <<<"$INIT_OUTPUT"; then
      echo "Detected MAAS release without --mode support; retrying legacy syntax."
      if ! maas init region+rack "${INIT_ARGS[@]}"; then
        echo "maas init failed"
        exit 1
      fi
    else
      echo "maas init failed"
      exit 1
    fi
  fi
  touch "${INIT_FLAG}"
else
  echo "MAAS already initialised; skipping 'maas init'"
fi

echo "Running MAAS DB migrations..."
maas-region dbupgrade || {
  echo "maas-region dbupgrade failed"
  exit 1
}

echo "Generating MAAS Nginx Configuration..."
# Create the directory where Nginx expects config and static files
mkdir -p /var/lib/maas/http
mkdir -p /usr/share/maas/web/static

# Generate a standalone Nginx config
cat >/var/lib/maas/http/nginx.conf <<EOF
user root;
worker_processes auto;
error_log /var/log/maas/nginx_error.log;
pid /run/nginx.pid;

events {
    worker_connections 1024;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    access_log /var/log/maas/nginx_access.log;
    sendfile on;
    keepalive_timeout 65;

    # Upstream: The MAAS Region Controller (running on 5240)
    upstream maas_region {
        # Use localhost to support both IPv4 and IPv6 bindings
        server localhost:5240;
    }

    server {
        listen 80;
        server_name localhost;

        # 1. Serve Static Files directly (bypassing Python)
        location /MAAS/static/ {
            alias /usr/share/maas/web/static/;
            autoindex off;
        }

        # 2. Proxy API and other requests to MAAS Regiond
        location / {
            proxy_pass http://maas_region;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
            
            # Websocket support (Crucial for MAAS UI updates)
            proxy_http_version 1.1;
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection "upgrade";
        }
    }
}
EOF

echo "Installing static files (manual fallback)..."
# We manually copy static files because 'collectstatic' fails in Docker without full config
TARGET_DIR="/usr/share/maas/web/static"

# Copy MAAS Server static files
if [ -d "/usr/lib/python3/dist-packages/maasserver/static" ]; then
    # -u: update only (don't recopy identical files)
    cp -ru /usr/lib/python3/dist-packages/maasserver/static/* "$TARGET_DIR/"
else
    echo "Warning: Could not find maasserver static files."
fi

# Copy Django Admin static files (fixes broken admin UI)
if [ -d "/usr/lib/python3/dist-packages/django/contrib/admin/static" ]; then
    cp -ru /usr/lib/python3/dist-packages/django/contrib/admin/static/* "$TARGET_DIR/"
fi
echo "Static files installed to $TARGET_DIR"

echo "Ensuring admin user exists..."
maas createadmin \
  --username "${MAAS_ADMIN_USERNAME}" \
  --password "${MAAS_ADMIN_PASSWORD}" \
  --email "${MAAS_ADMIN_EMAIL}" || true

echo "Starting supervisord..."
exec /usr/bin/supervisord -n