# syntax=docker/dockerfile:1.7
# QGIS Server Docker Image - Compiled from Source
# Maintainer: Walkthru Earth
# Repository: ghcr.io/walkthru-earth/qgis-server
# Supports: linux/amd64, linux/arm64

# =============================================================================
# Build Arguments
# =============================================================================
ARG GDAL_VERSION=3.12.2
ARG QGIS_VERSION=final-3_44_7

# =============================================================================
# Stage 1: Base Image with GDAL
# =============================================================================
FROM ghcr.io/osgeo/gdal:ubuntu-small-${GDAL_VERSION} AS base

LABEL org.opencontainers.image.authors="Walkthru Earth <hi@walkthru.earth>"
LABEL org.opencontainers.image.source="https://github.com/walkthru-earth/qgis-server"
LABEL org.opencontainers.image.description="QGIS Server - Compiled from source"

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
# Stage 2: Builder - Compile QGIS from source
# =============================================================================
FROM base AS builder

ARG QGIS_VERSION
ARG TARGETARCH

# Install build dependencies
RUN --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    --mount=type=cache,target=/var/cache/apt,sharing=locked \
    apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        # Build tools
        bison \
        build-essential \
        ccache \
        cmake \
        flex \
        git \
        ninja-build \
        pkg-config \
        # Qt6 development libraries
        qt6-base-dev \
        qt6-base-private-dev \
        qt6-tools-dev \
        qt6-tools-dev-tools \
        qt6-positioning-dev \
        qt6-svg-dev \
        qt6-serialport-dev \
        qt6-5compat-dev \
        libqt6opengl6-dev \
        libqt6sql6-sqlite \
        libqscintilla2-qt6-dev \
        qtkeychain-qt6-dev \
        # QGIS dependencies
        libdraco-dev \
        libexiv2-dev \
        libexpat1-dev \
        libfcgi-dev \
        libgeos-dev \
        libgsl-dev \
        libpq-dev \
        libprotobuf-dev \
        libqca-qt6-dev \
        libqca-qt6-plugins \
        libspatialindex-dev \
        libspatialite-dev \
        libsqlite3-dev \
        libsqlite3-mod-spatialite \
        libzip-dev \
        libzstd-dev \
        protobuf-compiler \
        # Python bindings (for qgis_process + PyQGIS)
        python3-dev \
        python3-sip-dev \
        sip-tools \
        python3-pyqtbuild \
        pyqt6-dev \
        pyqt6-dev-tools \
        python3-pyqt6 \
        python3-pyqt6.sip

# Remove broken PROJ cmake files from GDAL base image
RUN rm -rf /usr/local/lib/cmake/proj

# Clone QGIS repository
WORKDIR /src
RUN git clone --depth=1 --branch=${QGIS_VERSION} https://github.com/qgis/QGIS.git .

# Apply Ubuntu Noble compatibility patches (Qt 6.4, SIP 6.8)
COPY patches/ /tmp/patches/
RUN /tmp/patches/apply.sh /src && rm -rf /tmp/patches

# Configure ccache
ENV PATH="/usr/lib/ccache:${PATH}"
ENV CCACHE_DIR=/ccache
ENV CCACHE_MAXSIZE=2G

# Build QGIS Server
WORKDIR /src/build
RUN --mount=type=cache,target=/ccache,id=ccache-${TARGETARCH} \
    cmake .. \
        -GNinja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=/usr/local \
        -DCMAKE_C_FLAGS="-O2" \
        -DCMAKE_CXX_FLAGS="-O2" \
        -DBUILD_WITH_QT6=ON \
        -DWITH_QTWEBKIT=OFF \
        -DWITH_SERVER=ON \
        -DWITH_SERVER_LANDINGPAGE_WEBAPP=OFF \
        -DWITH_DESKTOP=OFF \
        -DWITH_GUI=OFF \
        -DWITH_3D=OFF \
        -DWITH_PDAL=OFF \
        -DWITH_BINDINGS=ON \
        -DBUILD_TESTING=OFF \
        -DENABLE_TESTS=OFF && \
    ninja -j$(nproc) && \
    ninja install && \
    rm -rf /usr/local/share/qgis/i18n/

# =============================================================================
# Stage 2b: Build GeoParquet plugin for GDAL (standalone, ~150MB added)
# =============================================================================
FROM base AS parquet-builder

ARG GDAL_VERSION
ARG TARGETARCH

RUN --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    --mount=type=cache,target=/var/cache/apt,sharing=locked \
    apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        build-essential \
        cmake \
        git && \
    # Add Apache Arrow apt repository
    curl -LO -fsS https://apache.jfrog.io/artifactory/arrow/ubuntu/apache-arrow-apt-source-latest-noble.deb && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y -V ./apache-arrow-apt-source-latest-noble.deb && \
    rm -f apache-arrow-apt-source-latest-noble.deb && \
    apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y -V --no-install-recommends \
        libarrow-dev=23.0.1-1 \
        libparquet-dev=23.0.1-1 \
        libarrow-acero-dev=23.0.1-1 \
        libarrow-dataset-dev=23.0.1-1 \
        libarrow-compute-dev=23.0.1-1

# Clone matching GDAL source (must exactly match base image version)
WORKDIR /gdal-src
RUN git clone --depth=1 --branch=v${GDAL_VERSION} https://github.com/OSGeo/gdal.git .

# Build only the Parquet driver as a standalone plugin
WORKDIR /gdal-src/build-parquet
RUN cmake ../ogr/ogrsf_frmts/parquet \
        -DCMAKE_PREFIX_PATH=/usr \
        -DCMAKE_BUILD_TYPE=Release && \
    cmake --build . -j$(nproc)

# =============================================================================
# Stage 3: Runtime
# =============================================================================
FROM base AS runtime

# Install runtime dependencies
RUN --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    --mount=type=cache,target=/var/cache/apt,sharing=locked \
    apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        # Web servers
        apache2 \
        libapache2-mod-fcgid \
        lighttpd \
        spawn-fcgi \
        # Qt6 runtime
        libqt6concurrent6t64 \
        libqt6core6t64 \
        libqt6gui6t64 \
        libqt6widgets6t64 \
        libqt6network6t64 \
        libqt6serialport6 \
        libqt6sql6t64 \
        libqt6sql6-sqlite \
        libqt6xml6t64 \
        libqt6svg6 \
        libqt6opengl6t64 \
        libqt6positioning6 \
        libqt6core5compat6 \
        libqscintilla2-qt6-15 \
        libqt6keychain1 \
        # QGIS runtime dependencies
        libqca-qt6-2 \
        libqca-qt6-plugins \
        libfcgi0ldbl \
        libgslcblas0 \
        libspatialindex6 \
        libspatialite8 \
        libsqlite3-0 \
        libsqlite3-mod-spatialite \
        libzip4 \
        libzstd1 \
        libdraco8 \
        libexiv2-27 \
        libprotobuf32t64 \
        libprotobuf-lite32t64 \
        libgsl27 \
        # Fonts
        xfonts-100dpi \
        xfonts-75dpi \
        xfonts-base \
        xfonts-scalable \
        fontconfig \
        fonts-dejavu-core \
        # Python bindings runtime (for qgis_process + PyQGIS)
        python3-pyqt6 \
        python3-pyqt6.sip \
        python3-pyqt6.qtsvg \
        python3-pyqt6.qtpositioning \
        python3-pyqt6.qtserialport \
        python3-sip \
        # Utilities
        xvfb \
        xauth && \
    # Add Apache Arrow runtime libs for GeoParquet plugin (~150MB)
    curl -LO -fsS https://apache.jfrog.io/artifactory/arrow/ubuntu/apache-arrow-apt-source-latest-noble.deb && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y -V ./apache-arrow-apt-source-latest-noble.deb && \
    rm -f apache-arrow-apt-source-latest-noble.deb && \
    apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y -V --no-install-recommends \
        libarrow2300 \
        libparquet2300 \
        libarrow-dataset2300 \
        libarrow-compute2300

# =============================================================================
# Stage 4: Server - Production QGIS Server
# =============================================================================
FROM runtime AS server

# Copy compiled QGIS from builder (includes Python bindings + processing plugin)
COPY --from=builder /usr/local/bin /usr/local/bin/
COPY --from=builder /usr/local/lib /usr/local/lib/
COPY --from=builder /usr/local/share/qgis /usr/local/share/qgis/

# Copy GeoParquet GDAL plugin into the existing plugins directory
COPY --from=parquet-builder /gdal-src/build-parquet/ogr_Parquet.so /tmp/ogr_Parquet.so
RUN GDAL_PLUGDIR=$(find /usr/lib -type d -name gdalplugins | head -1) && \
    mv /tmp/ogr_Parquet.so ${GDAL_PLUGDIR}/ogr_Parquet.so && \
    echo "Installed GeoParquet plugin to ${GDAL_PLUGDIR}"

# Copy runtime configuration
COPY runtime/ /

# Update Apache config: use the wrapper script (restores env vars for FCGI processes)
RUN sed -i 's|/usr/lib/cgi-bin/qgis_mapserv.fcgi|/usr/local/bin/qgis-mapserv-wrapper|g' \
        /etc/apache2/conf-enabled/qgis.conf && \
    sed -i 's|/usr/lib/cgi-bin/|/usr/local/bin/|g' \
        /etc/apache2/conf-enabled/qgis.conf

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
    QGIS_PREFIX_PATH=/usr/local \
    PYTHONPATH=/usr/local/lib/python3/dist-packages:/usr/local/share/qgis/python/:/var/www/plugins/

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
# Stage 5: Server Debug
# =============================================================================
FROM server AS server-debug

RUN --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    --mount=type=cache,target=/var/cache/apt,sharing=locked \
    apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        gdb \
        strace \
        valgrind
