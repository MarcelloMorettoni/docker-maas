FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive \
    MAAS_VERSION=3.3

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
RUN chmod +x /entrypoint.sh

EXPOSE 5240 80
CMD ["/entrypoint.sh"]