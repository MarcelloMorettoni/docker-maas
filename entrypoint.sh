#!/bin/bash
set -euo pipefail

DB_URI="postgres://${MAAS_DB_USER}:${MAAS_DB_PASSWORD}@${MAAS_DB_HOST}:${MAAS_DB_PORT}/${MAAS_DB_NAME}"
INIT_FLAG="/var/lib/maas/.maas-init-done"

echo "Preparing runtime directories..."
mkdir -p /run /run/lock
chown root:maas /run/lock
chmod 775 /run/lock
mkdir -p /run/maas
chown maas:maas /run/maas
chmod 775 /run/maas

echo "Waiting for PostgreSQL at ${MAAS_DB_HOST}:${MAAS_DB_PORT}..."
export PGPASSWORD="${MAAS_DB_PASSWORD}"

until psql "host=${MAAS_DB_HOST} port=${MAAS_DB_PORT} dbname=${MAAS_DB_NAME} user=${MAAS_DB_USER}" -c "SELECT 1;" >/dev/null 2>&1; do
  echo "  ... still waiting for DB ..."
  sleep 2
done
echo "PostgreSQL is ready"

provision_regiond_conf_from_env() {
  echo "Provisioning /etc/maas/regiond.conf directly from environment..."
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
}

if [ ! -f "${INIT_FLAG}" ]; then
  echo "Running 'maas init' to mirror the LogicWeb guide..."
  maas_init_completed=0
  maas_init_requires_manual_config=0

  INIT_ARGS=(--maas-url "${MAAS_URL}" --database-uri "${DB_URI}")
  DB_SPLIT_ARGS=(
    --maas-url "${MAAS_URL}"
    --database-host "${MAAS_DB_HOST}"
    --database-port "${MAAS_DB_PORT}"
    --database-name "${MAAS_DB_NAME}"
    --database-user "${MAAS_DB_USER}"
    --database-pass "${MAAS_DB_PASSWORD}"
  )

  attempt_maas_init() {
    local description="$1"
    shift
    local -a cmd=("$@")

    echo "Attempting 'maas init' (${description})..."
    if INIT_OUTPUT=$("${cmd[@]}" 2>&1); then
      printf '%s\n' "$INIT_OUTPUT"
      return 0
    fi

    local status=$?
    printf '%s\n' "$INIT_OUTPUT"
    if grep -qiE 'unrecognized argument|unrecognized arguments|unknown option|unknown arguments|the following arguments (are|were) required|the following arguments are missing|argument .+ is required' <<<"$INIT_OUTPUT"; then
      echo "\"${description}\" syntax not supported; trying next variant."
      return 1
    fi

    echo "'maas init' failed while using ${description} syntax (exit ${status})."
    exit 1
  }

  run_legacy_maas_init_matrix() {
    if attempt_maas_init "--mode region+rack" maas init --mode region+rack "${INIT_ARGS[@]}"; then
      return 0
    elif attempt_maas_init "legacy positional region+rack" maas init region+rack "${INIT_ARGS[@]}"; then
      return 0
    elif attempt_maas_init "no positional (region+rack auto-detect)" maas init "${INIT_ARGS[@]}"; then
      return 0
    elif attempt_maas_init "split DB parameters + region+rack" maas init region+rack "${DB_SPLIT_ARGS[@]}"; then
      return 0
    elif attempt_maas_init "split DB parameters (auto mode)" maas init "${DB_SPLIT_ARGS[@]}"; then
      return 0
    fi
    return 1
  }

  run_mode_permutations() {
    local description="$1"
    shift
    local -a args=("$@")
    local attempted=0

    if [[ -n "${DETECTED_MODE_FLAG:-}" ]]; then
      attempted=1
      if attempt_maas_init "${description} + ${DETECTED_MODE_FLAG}" maas init "${DETECTED_MODE_FLAG}" region+rack "${args[@]}"; then
        return 0
      fi
    fi

    if (( DETECTED_SUPPORTS_POSITIONAL_MODE )); then
      attempted=1
      if attempt_maas_init "${description} + positional region+rack" maas init region+rack "${args[@]}"; then
        return 0
      fi
    fi

    attempted=1
    if attempt_maas_init "${description} + auto mode" maas init "${args[@]}"; then
      return 0
    fi

    if (( ! attempted )); then
      echo "No supported mode hints detected for ${description}; skipping."
    fi
    return 1
  }

  run_dynamic_maas_init() {
    local help_text="$1"
    local -n success_ref="$2"
    local help_text_lc
    help_text_lc=$(printf '%s' "$help_text" | tr '[:upper:]' '[:lower:]')

    local find_flag
    find_flag() {
      local __result="$1"
      shift
      local candidate
      for candidate in "$@"; do
        local candidate_lc="${candidate,,}"
        if grep -q -- "$candidate_lc" <<<"$help_text_lc"; then
          printf -v "$__result" '%s' "$candidate"
          return 0
        fi
      done
      printf -v "$__result" ''
      return 1
    }

    find_flag DETECTED_MODE_FLAG --mode --role --controllers --components
    find_flag DETECTED_MAAS_URL_FLAG --maas-url --region-url --url --api-url --controller-url
    find_flag DETECTED_DB_URI_FLAG --database-uri --db-uri --postgres-uri --pg-uri --region-db-uri --regiondb-uri --pg-conn-uri
    find_flag DETECTED_DB_HOST_FLAG --database-host --db-host --postgres-host --pg-host --region-db-host --regiondb-host --dbhost
    find_flag DETECTED_DB_PORT_FLAG --database-port --db-port --postgres-port --pg-port --region-db-port --regiondb-port --dbport
    find_flag DETECTED_DB_NAME_FLAG --database-name --db-name --database --dbname --region-db-name --regiondb-name
    find_flag DETECTED_DB_USER_FLAG --database-user --db-user --database-username --region-db-user --regiondb-user
    find_flag DETECTED_DB_PASS_FLAG --database-pass --database-password --db-pass --db-password --region-db-pass --region-db-password --regiondb-pass --regiondb-password

    DETECTED_SUPPORTS_POSITIONAL_MODE=0
    if grep -qE 'region[[:space:]]*\+?[[:space:]]*rack' <<<"$help_text_lc"; then
      DETECTED_SUPPORTS_POSITIONAL_MODE=1
    fi

    local -a common_args=()
    if [[ -n "$DETECTED_MAAS_URL_FLAG" ]]; then
      common_args=("$DETECTED_MAAS_URL_FLAG" "${MAAS_URL}")
    else
      echo "'maas init --help' did not advertise a MAAS URL flag; continuing without explicitly setting it."
    fi

    local -a arg_sets_desc=()
    local -a arg_sets=()

    if [[ -n "$DETECTED_DB_URI_FLAG" ]]; then
      local serialized
      printf -v serialized '%q ' "${common_args[@]}" "$DETECTED_DB_URI_FLAG" "$DB_URI"
      serialized=${serialized% }
      arg_sets_desc+=("detected ${DETECTED_DB_URI_FLAG}")
      arg_sets+=("$serialized")
    fi

    if [[ -n "$DETECTED_DB_HOST_FLAG" && -n "$DETECTED_DB_PORT_FLAG" && -n "$DETECTED_DB_NAME_FLAG" && -n "$DETECTED_DB_USER_FLAG" && -n "$DETECTED_DB_PASS_FLAG" ]]; then
      local serialized
      printf -v serialized '%q ' \
        "${common_args[@]}" \
        "$DETECTED_DB_HOST_FLAG" "$MAAS_DB_HOST" \
        "$DETECTED_DB_PORT_FLAG" "$MAAS_DB_PORT" \
        "$DETECTED_DB_NAME_FLAG" "$MAAS_DB_NAME" \
        "$DETECTED_DB_USER_FLAG" "$MAAS_DB_USER" \
        "$DETECTED_DB_PASS_FLAG" "$MAAS_DB_PASSWORD"
      serialized=${serialized% }
      arg_sets_desc+=("detected split DB flags")
      arg_sets+=("$serialized")
    fi

    if [[ ${#arg_sets_desc[@]} -eq 0 ]]; then
      echo "Unable to map any supported database flags from 'maas init --help'."
      maas_init_requires_manual_config=1
      return 1
    fi

    local i
    for ((i = 0; i < ${#arg_sets_desc[@]}; i++)); do
      local -a current_args=()
      eval "current_args=(${arg_sets[$i]})"
      if run_mode_permutations "${arg_sets_desc[$i]}" "${current_args[@]}"; then
        success_ref=1
        return 0
      fi
    done
    return 1
  }

  DETECTED_MODE_FLAG=""
  DETECTED_MAAS_URL_FLAG=""
  DETECTED_DB_URI_FLAG=""
  DETECTED_DB_HOST_FLAG=""
  DETECTED_DB_PORT_FLAG=""
  DETECTED_DB_NAME_FLAG=""
  DETECTED_DB_USER_FLAG=""
  DETECTED_DB_PASS_FLAG=""
  DETECTED_SUPPORTS_POSITIONAL_MODE=0

  dynamic_maas_init_success=0
  if MAAS_INIT_HELP=$(maas init --help 2>&1); then
    if [[ -n "$MAAS_INIT_HELP" ]]; then
      echo "Inspecting 'maas init --help' output to discover supported flags..."
      if run_dynamic_maas_init "$MAAS_INIT_HELP" dynamic_maas_init_success; then
        :
      fi
    else
      echo "'maas init --help' returned no output; falling back to legacy probes."
    fi
  else
    echo "Warning: unable to execute 'maas init --help'; falling back to legacy probes."
  fi

  if (( dynamic_maas_init_success )); then
    maas_init_completed=1
  fi

  if (( maas_init_requires_manual_config )); then
    echo "'maas init' CLI does not expose database flags; using legacy config file provisioning."
    provision_regiond_conf_from_env
    maas_init_completed=1
  elif (( ! dynamic_maas_init_success )); then
    echo "Falling back to legacy 'maas init' invocation matrix..."
    if run_legacy_maas_init_matrix; then
      maas_init_completed=1
    else
      echo "maas init failed for all known syntaxes"
      echo "Falling back to direct /etc/maas/regiond.conf provisioning as a last resort..."
      provision_regiond_conf_from_env
      maas_init_completed=1
    fi
  fi

  if (( maas_init_completed )); then
    touch "${INIT_FLAG}"
  else
    echo "Unable to complete MAAS initialisation."
    exit 1
  fi
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