#!/bin/bash
set -e

echo "🔧 Writing /etc/maas/regiond.conf from env..."
cat >/etc/maas/regiond.conf <<EOF
database_host: "${MAAS_DB_HOST}"
database_name: "${MAAS_DB_NAME}"
database_user: "${MAAS_DB_USER}"
database_pass: "${MAAS_DB_PASSWORD}"
database_port: ${MAAS_DB_PORT}
maas_url: "${MAAS_URL}"
EOF

chown root:maas /etc/maas/regiond.conf
chmod 640 /etc/maas/regiond.conf

echo "Waiting for PostgreSQL at ${MAAS_DB_HOST}:${MAAS_DB_PORT} (db=${MAAS_DB_NAME})..."
export PGPASSWORD="${MAAS_DB_PASSWORD}"

until psql "host=${MAAS_DB_HOST} port=${MAAS_DB_PORT} dbname=${MAAS_DB_NAME} user=${MAAS_DB_USER}" -c "SELECT 1;" >/dev/null 2>&1; do
  echo "  … still waiting for DB …"
  sleep 2
done
echo "PostgreSQL is ready"

echo "⚙ Running MAAS DB migrations (maas-region dbupgrade)…"
maas-region dbupgrade || {
  echo "maas-region dbupgrade failed"
  exit 1
}

# Ensure nginx config exists (MAAS writes /var/lib/maas/http/nginx.conf)
if [ ! -f /var/lib/maas/http/nginx.conf ]; then
  echo "⚠ /var/lib/maas/http/nginx.conf missing – MAAS http config not generated"
fi

echo "Ensuring admin user exists…"
# createadmin is safe to rerun – will error if user exists; we ignore that
maas createadmin \
  --username "${MAAS_ADMIN_USERNAME}" \
  --password "${MAAS_ADMIN_PASSWORD}" \
  --email "${MAAS_ADMIN_EMAIL}" || true

echo "Starting supervisord (nginx + regiond + rackd)…"
/usr/bin/supervisord -n

