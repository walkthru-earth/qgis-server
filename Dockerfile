# syntax=docker/dockerfile:1.7
# QGIS Server Docker Image - Using Official Packages
# Maintainer: Walkthru Earth
# Repository: ghcr.io/walkthru-earth/qgis-server

# =============================================================================
# Build Arguments
# =============================================================================
ARG GDAL_VERSION=3.12.1
ARG UBUNTU_VERSION=noble

# =============================================================================
# Stage 1: Base Image with GDAL (Multi-arch: amd64 + arm64)
# =============================================================================
FROM ghcr.io/osgeo/gdal:ubuntu-small-${GDAL_VERSION} AS base

LABEL org.opencontainers.image.authors="Walkthru Earth <info@walkthru.earth>"
LABEL org.opencontainers.image.source="https://github.com/walkthru-earth/qgis-server"
LABEL org.opencontainers.image.description="QGIS Server with official packages - Multi-architecture"

SHELL ["/bin/bash", "-o", "pipefail", "-cux"]

# Install base utilities
RUN --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    --mount=type=cache,target=/var/cache/apt,sharing=locked \
    rm -f /etc/apt/apt.conf.d/docker-clean && \
    apt-get update && \
    apt-get upgrade -y && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        gnupg \
        wget \
        software-properties-common \
        adduser

# =============================================================================
# Stage 2: Runtime - Add QGIS Repository and Install
# =============================================================================
FROM base AS runtime

ARG TARGETARCH

# Add QGIS official repository with apt preference to prioritize it
RUN mkdir -m755 -p /etc/apt/keyrings && \
    wget -O /etc/apt/keyrings/qgis-archive-keyring.gpg \
        https://download.qgis.org/downloads/qgis-archive-keyring.gpg && \
    echo "Types: deb deb-src" > /etc/apt/sources.list.d/qgis.sources && \
    echo "URIs: https://qgis.org/ubuntu-ltr" >> /etc/apt/sources.list.d/qgis.sources && \
    echo "Suites: noble" >> /etc/apt/sources.list.d/qgis.sources && \
    echo "Architectures: amd64" >> /etc/apt/sources.list.d/qgis.sources && \
    echo "Components: main" >> /etc/apt/sources.list.d/qgis.sources && \
    echo "Signed-By: /etc/apt/keyrings/qgis-archive-keyring.gpg" >> /etc/apt/sources.list.d/qgis.sources && \
    echo 'Package: *' > /etc/apt/preferences.d/qgis && \
    echo 'Pin: origin qgis.org' >> /etc/apt/preferences.d/qgis && \
    echo 'Pin-Priority: 1001' >> /etc/apt/preferences.d/qgis

# Install QGIS Server and dependencies
# Note: python3-qgis excluded due to version conflicts between repos
RUN --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    --mount=type=cache,target=/var/cache/apt,sharing=locked \
    apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        # Web servers
        apache2 \
        libapache2-mod-fcgid \
        lighttpd \
        spawn-fcgi \
        # QGIS Server (from official repo)
        qgis-server \
        # Fonts
        xfonts-100dpi \
        xfonts-75dpi \
        xfonts-base \
        xfonts-scalable \
        fontconfig \
        fonts-dejavu-core \
        # Utilities
        xvfb \
        xauth

# =============================================================================
# Stage 3: Server - Production QGIS Server
# =============================================================================
FROM runtime AS server

# Copy runtime configuration
COPY runtime/ /

# Allow non-root font installation
RUN chmod u+s /usr/bin/fc-cache && \
    chmod o+w /usr/local/share/fonts 2>/dev/null || true

# Apache configuration
ENV APACHE_CONFDIR=/etc/apache2 \
    APACHE_ENVVARS=/etc/apache2/envvars \
    APACHE_RUN_USER=www-data \
    APACHE_RUN_GROUP=www-data \
    APACHE_RUN_DIR=/tmp/apache2 \
    APACHE_PID_FILE=/tmp/apache2/apache2.pid \
    APACHE_LOCK_DIR=/var/lock/apache2 \
    APACHE_LOG_DIR=/var/log/apache2

# Server mode configuration
ENV SERVER=apache \
    LIGHTTPD_CONF=/etc/lighttpd/lighttpd.conf \
    LIGHTTPD_PORT=8080 \
    LIGHTTPD_FASTCGI_HOST=spawn-fcgi \
    LIGHTTPD_FASTCGI_PORT=3000 \
    LIGHTTPD_FASTCGI_SOCKET=

# FCGI tuning
ENV FCGID_MAX_REQUESTS_PER_PROCESS=1000 \
    FCGID_MIN_PROCESSES=1 \
    FCGID_MAX_PROCESSES=5 \
    FCGID_BUSY_TIMEOUT=300 \
    FCGID_IDLE_TIMEOUT=300 \
    FCGID_IO_TIMEOUT=40

# QGIS Server configuration
ENV QGIS_SERVER_LOG_STDERR=1 \
    QGIS_CUSTOM_CONFIG_PATH=/tmp \
    QGIS_PLUGINPATH=/var/www/plugins \
    PYTHONPATH=/usr/share/qgis/python/:/var/www/plugins/

# Configure Apache
RUN a2enmod fcgid headers status && \
    a2dismod -f auth_basic authn_file authn_core authz_user autoindex dir && \
    rm -f /etc/apache2/mods-enabled/alias.conf && \
    mkdir -p ${APACHE_RUN_DIR} ${APACHE_LOCK_DIR} ${APACHE_LOG_DIR} && \
    sed -ri 's!^(\s*CustomLog)\s+\S+!\1 /proc/self/fd/1!g; s!^(\s*ErrorLog)\s+\S+!\1 /proc/self/fd/2!g;' \
        /etc/apache2/sites-enabled/000-default.conf /etc/apache2/apache2.conf && \
    sed -ri 's!LogFormat "(.*)" combined!LogFormat "%{us}T %{X-Request-Id}i \1" combined!g' /etc/apache2/apache2.conf && \
    echo 'ErrorLogFormat "%{X-Request-Id}i [%l] [pid %P] %M"' >> /etc/apache2/apache2.conf && \
    sed -i -e 's/<VirtualHost \*:80>/<VirtualHost *:8080>/' /etc/apache2/sites-available/000-default.conf && \
    sed -i -e 's/Listen 80$/Listen 8080/' /etc/apache2/ports.conf && \
    rm -rf /etc/apache2/conf-enabled/other-vhosts-access-log.conf && \
    mkdir -p /var/www/.qgis3 /var/www/plugins && \
    chown www-data:root /var/www/.qgis3 && \
    ln -s /etc/qgisserver /project

# Setup permissions for non-root
RUN adduser www-data root && \
    chmod -R g+rw ${APACHE_CONFDIR} ${APACHE_RUN_DIR} ${APACHE_LOCK_DIR} ${APACHE_LOG_DIR} \
        /var/lib/apache2/fcgid /var/log /var/www/.qgis3 && \
    chgrp -R root ${APACHE_LOG_DIR} /var/lib/apache2/fcgid

# Update library cache
RUN ldconfig

VOLUME /tmp
WORKDIR /etc/qgisserver
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8080/ows?SERVICE=WMS&REQUEST=GetCapabilities || exit 1

CMD ["/usr/local/bin/start-server"]

# =============================================================================
# Stage 4: Server Debug - With debugging tools
# =============================================================================
FROM server AS server-debug

RUN --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    --mount=type=cache,target=/var/cache/apt,sharing=locked \
    apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        gdb \
        strace \
        valgrind
