FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive \
    MAAS_VERSION=3.3 \
    TEMPORAL_CLI_VERSION=1.25.1

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# 1. Install Dependencies
RUN apt-get update && apt-get install -y \
    software-properties-common \
    python3 python3-pip python3-psycopg2 python3-yaml python3-dbus \
    postgresql-client nginx supervisor curl gnupg sudo \
    bind9 bind9-dnsutils bind9-host iproute2 \
    && add-apt-repository -y ppa:maas/${MAAS_VERSION} \
    && apt-get update \
    && apt-get install -y maas-region-controller maas-rack-controller \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# 1.1 Install Temporal CLI so we can run an embedded Temporal server for MAAS
RUN set -euo pipefail; \
    for asset in \
        "temporal_${TEMPORAL_CLI_VERSION}_linux_amd64.tar.gz" \
        "temporal_${TEMPORAL_CLI_VERSION}_Linux_x86_64.tar.gz" \
        "temporal_Linux_x86_64.tar.gz"; do \
      url="https://github.com/temporalio/cli/releases/download/v${TEMPORAL_CLI_VERSION}/${asset}"; \
      if curl -fsSL "$url" -o /tmp/temporal.tgz; then \
        break; \
      fi; \
    done; \
    test -f /tmp/temporal.tgz; \
    tar -xzf /tmp/temporal.tgz -C /usr/local/bin temporal; \
    rm -f /tmp/temporal.tgz; \
    chmod +x /usr/local/bin/temporal

# 2. Install the Mock Systemctl
COPY mock_systemctl /usr/bin/systemctl
RUN chmod 755 /usr/bin/systemctl

# 3. ALLOW MAAS USER TO SUDO (Critical for systemctl calls)
RUN echo "maas ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

# 4. Setup Logs
RUN mkdir -p /var/log/maas && \
    chown -R maas:maas /var/log/maas && \
    chmod 775 /var/log/maas

# 5. Setup Nginx
RUN rm -f /etc/nginx/sites-enabled/default

# 6. Configs
COPY supervisord.conf /etc/supervisor/conf.d/maas.conf
COPY entrypoint.sh /entrypoint.sh
COPY start-regiond.sh /usr/local/bin/start-regiond.sh
COPY start-temporal.sh /usr/local/bin/start-temporal.sh
RUN chmod +x /entrypoint.sh /usr/local/bin/start-regiond.sh /usr/local/bin/start-temporal.sh

EXPOSE 5240 80
CMD ["/entrypoint.sh"]
