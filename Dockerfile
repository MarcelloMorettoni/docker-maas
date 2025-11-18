FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive \
    MAAS_VERSION=3.3

# Base dependencies + MAAS
RUN apt update && apt install -y \
    software-properties-common \
    python3 \
    python3-pip \
    python3-psycopg2 \
    python3-yaml \
    python3-dbus \
    postgresql-client \
    nginx \
    supervisor \
    curl \
    gnupg && \
    add-apt-repository -y ppa:maas/${MAAS_VERSION} && \
    apt update && apt install -y \
      maas-region-controller \
      maas-rack-controller && \
    apt clean && rm -rf /var/lib/apt/lists/*

# Make sure log dir exists
RUN mkdir -p /var/log/maas && chown -R root:maas /var/log/maas

# Copy supervisord config and entrypoint
COPY supervisord.conf /etc/supervisor/conf.d/maas.conf
COPY entrypoint.sh /entrypoint.sh

RUN chmod +x /entrypoint.sh

EXPOSE 5240

CMD ["/entrypoint.sh"]

