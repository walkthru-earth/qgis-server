# QGIS Server Docker - Architecture Documentation

This document describes the architecture, build process, and deployment options for the QGIS Server Docker image.

## Table of Contents

- [Overview](#overview)
- [Technology Stack](#technology-stack)
- [Docker Build Architecture](#docker-build-architecture)
- [Multi-Architecture Support](#multi-architecture-support)
- [Server Modes](#server-modes)
- [CI/CD Pipeline](#cicd-pipeline)
- [Configuration Reference](#configuration-reference)

---

## Overview

This project provides a modern, multi-architecture Docker image for QGIS Server built with Qt6.

### Design Principles

1. **Multi-Architecture First**: Native support for AMD64 and ARM64
2. **Qt6 Native**: Built for QGIS 4.x with Qt6 (no Qt5 legacy)
3. **Minimal Runtime**: Small production image with only runtime dependencies
4. **Flexible Deployment**: Multiple server modes for different use cases
5. **Cloud Native**: Healthchecks, non-root user, read-only filesystem support

### Published Images

| Registry | Image |
|----------|-------|
| GitHub Container Registry | `ghcr.io/walkthru-earth/qgis-server` |
| Docker Hub | `docker.io/walkthruearth/qgis-server` |

---

## Technology Stack

```mermaid
graph TB
    subgraph "Versions"
        QGIS["QGIS 4.x<br/>(Qt6)"]
        QT["Qt 6.6+"]
        PYTHON["Python 3.12"]
        GDAL["GDAL 3.12.1"]
        UBUNTU["Ubuntu 24.04+"]
    end

    subgraph "Architectures"
        AMD["linux/amd64<br/>(x86_64)"]
        ARM["linux/arm64<br/>(aarch64)"]
    end

    QGIS --> QT
    QGIS --> PYTHON
    GDAL --> UBUNTU
    UBUNTU --> AMD
    UBUNTU --> ARM
```

| Component | Version | Notes |
|-----------|---------|-------|
| QGIS | 4.x (master) | Built from source with Qt6 |
| Qt | 6.4+ | Required for QGIS 4.x |
| Python | 3.12 | With PyQt6 bindings |
| GDAL | 3.12.1 | Multi-arch base image |
| Ubuntu | 24.04 (Noble) | From GDAL base |

---

## Docker Build Architecture

### Multi-Stage Build

The Dockerfile uses a 6-stage build optimized for caching and minimal image size.

```mermaid
flowchart TB
    subgraph "Stage 1: Base"
        BASE["base<br/>ghcr.io/osgeo/gdal:ubuntu-small-3.12.1<br/>+ Python 3, curl, ca-certificates"]
    end

    subgraph "Stage 2-3: Compilation"
        BUILDER["builder<br/>+ Qt6 dev packages<br/>+ Build tools (cmake, ninja, clang)<br/>+ QGIS source<br/>CMake: BUILD_WITH_QT6=ON"]

        BUILDER_DEBUG["builder-debug<br/>CMAKE_BUILD_TYPE=Debug<br/>+ Debug symbols"]
    end

    subgraph "Stage 4: Runtime"
        RUNTIME["runtime<br/>+ Qt6 runtime libs<br/>+ PyQt6<br/>+ Apache, Lighttpd, spawn-fcgi<br/>+ Fonts"]
    end

    subgraph "Stage 5-6: Final Images"
        SERVER["server<br/>Production image<br/>~800MB"]
        DEBUG["server-debug<br/>+ GDB, strace, valgrind<br/>~900MB"]
    end

    BASE --> BUILDER
    BUILDER --> BUILDER_DEBUG
    BASE --> RUNTIME
    RUNTIME --> SERVER
    SERVER --> DEBUG

    BUILDER -.->|"COPY binaries"| SERVER
    BUILDER_DEBUG -.->|"COPY debug binaries"| DEBUG
```

### Build Stages

| Stage | Purpose | Size Impact |
|-------|---------|-------------|
| `base` | GDAL + Python base | ~500MB |
| `builder` | Compile QGIS with Qt6 | ~4GB (not in final) |
| `builder-debug` | Compile with debug symbols | ~5GB (not in final) |
| `runtime` | Runtime dependencies only | ~700MB |
| `server` | Final production image | ~800MB |
| `server-debug` | With debugging tools | ~900MB |

### CMake Configuration

```cmake
cmake .. \
    -GNinja \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_WITH_QT6=ON \          # Enable Qt6
    -DWITH_QTWEBKIT=OFF \           # Not available in Qt6
    -DWITH_SERVER=ON \
    -DWITH_SERVER_LANDINGPAGE_WEBAPP=ON \
    -DWITH_DESKTOP=OFF \            # Server only
    -DWITH_3D=OFF \
    -DWITH_PDAL=OFF \
    -DWITH_BINDINGS=ON \            # Python bindings
    -DBUILD_TESTING=OFF
```

---

## Multi-Architecture Support

### How It Works

```mermaid
flowchart LR
    subgraph "Build Process"
        BUILDX["docker buildx"]
        QEMU["QEMU<br/>(ARM64 emulation)"]
    end

    subgraph "Parallel Builds"
        AMD["AMD64 Build<br/>(native)"]
        ARM["ARM64 Build<br/>(emulated or native)"]
    end

    subgraph "Output"
        MANIFEST["Multi-arch Manifest<br/>walkthruearth/qgis-server:latest"]
    end

    subgraph "Registries"
        GHCR["ghcr.io"]
        DOCKER["docker.io"]
    end

    BUILDX --> QEMU
    QEMU --> ARM
    BUILDX --> AMD
    AMD --> MANIFEST
    ARM --> MANIFEST
    MANIFEST --> GHCR
    MANIFEST --> DOCKER
```

### Architecture Detection

The Dockerfile uses `TARGETARCH` to handle architecture-specific configurations:

```dockerfile
ARG TARGETARCH
# TARGETARCH = "amd64" or "arm64"

# Architecture-aware library paths
RUN ARCH_DIR=$(dpkg --print-architecture) && \
    ldconfig /usr/lib/${ARCH_DIR}-linux-gnu/
```

### Base Image Verification

The GDAL base image provides verified multi-arch support:

```bash
$ docker manifest inspect ghcr.io/osgeo/gdal:ubuntu-small-3.12.1
# Returns: linux/amd64, linux/arm64
```

---

## Server Modes

The container supports three server modes, selected via the `SERVER` environment variable.

```mermaid
flowchart TB
    START["Container Start<br/>/usr/local/bin/start-server"]

    CHECK{"SERVER=?"}

    subgraph "Apache Mode (Default)"
        A1["Configure FCGI environment"]
        A2["Setup PassEnv for Apache"]
        A3["apache2 -DFOREGROUND"]
        A4["mod_fcgid manages<br/>QGIS FCGI processes"]
    end

    subgraph "spawn-fcgi Mode"
        S1["Export environment"]
        S2["spawn-fcgi -n"]
        S3["qgis_mapserv.fcgi"]
    end

    subgraph "lighttpd Mode"
        L1["Validate config"]
        L2["lighttpd -D"]
        L3["Proxy to FCGI backend"]
    end

    START --> CHECK
    CHECK -->|"apache"| A1 --> A2 --> A3 --> A4
    CHECK -->|"spawn-fcgi"| S1 --> S2 --> S3
    CHECK -->|"lighttpd"| L1 --> L2 --> L3
```

### Mode Comparison

| Feature | Apache | spawn-fcgi | lighttpd |
|---------|--------|------------|----------|
| **Use Case** | Standard deployment | Kubernetes sidecar | Lightweight proxy |
| **Process Management** | mod_fcgid | Single process | External backend |
| **Memory** | Higher | Lowest | Low |
| **Complexity** | All-in-one | Requires pairing | Requires backend |
| **Port** | 8080 | 3000 | 8080 |

### Deployment Patterns

#### Pattern 1: Standalone (Apache)

```yaml
services:
  qgis:
    image: ghcr.io/walkthru-earth/qgis-server:latest
    ports:
      - "8080:8080"
    environment:
      QGIS_PROJECT_FILE: /data/project.qgs
    volumes:
      - ./data:/data:ro
```

#### Pattern 2: Kubernetes-Ready (spawn-fcgi + lighttpd)

```yaml
services:
  # FCGI backend (scalable)
  fcgi:
    image: ghcr.io/walkthru-earth/qgis-server:latest
    environment:
      SERVER: spawn-fcgi
    user: "1000:1000"
    read_only: true

  # Web frontend
  web:
    image: ghcr.io/walkthru-earth/qgis-server:latest
    environment:
      SERVER: lighttpd
      LIGHTTPD_FASTCGI_HOST: fcgi
    ports:
      - "8080:8080"
```

---

## CI/CD Pipeline

### Workflow Overview

```mermaid
flowchart TB
    subgraph "Triggers"
        PUSH["Push to main"]
        TAG["Tag (v*)"]
        PR["Pull Request"]
        SCHEDULE["Weekly rebuild"]
        MANUAL["Manual dispatch"]
    end

    subgraph "Setup"
        QEMU["Setup QEMU<br/>(ARM64 emulation)"]
        BUILDX["Setup Docker Buildx"]
        LOGIN["Login to registries<br/>GHCR + Docker Hub"]
    end

    subgraph "Build Matrix"
        SERVER["Build: server<br/>platforms: amd64, arm64"]
        DEBUG["Build: server-debug<br/>platforms: amd64, arm64"]
    end

    subgraph "Cache"
        GHA["GitHub Actions Cache<br/>type=gha"]
    end

    subgraph "Output"
        GHCR["ghcr.io/walkthru-earth/qgis-server"]
        DOCKER["docker.io/walkthruearth/qgis-server"]
    end

    subgraph "Test"
        TEST["Test Images<br/>WMS/WFS capabilities<br/>Python imports"]
    end

    PUSH & TAG & PR & SCHEDULE & MANUAL --> QEMU
    QEMU --> BUILDX --> LOGIN
    LOGIN --> SERVER & DEBUG
    GHA <--> SERVER & DEBUG
    SERVER & DEBUG --> GHCR & DOCKER
    GHCR & DOCKER --> TEST
```

### Tag Strategy

| Trigger | Tags Generated |
|---------|----------------|
| Push to `main` | `latest`, `latest-debug` |
| Tag `v1.2.3` | `1.2.3`, `1.2`, `1.2.3-debug`, `1.2-debug` |
| PR #42 | `pr-42`, `pr-42-debug` (not pushed) |

### Caching

The pipeline uses GitHub Actions cache for Docker layers:

```yaml
cache-from: type=gha,scope=server
cache-to: type=gha,mode=max,scope=server
```

Separate cache scopes per target prevent cache pollution.

---

## Configuration Reference

### Environment Variables

#### Server Configuration

```mermaid
graph LR
    subgraph "Server Mode"
        SERVER["SERVER<br/>apache|spawn-fcgi|lighttpd"]
    end

    subgraph "Apache/FCGI"
        FCGI_MAX["FCGID_MAX_PROCESSES=5"]
        FCGI_MIN["FCGID_MIN_PROCESSES=1"]
        FCGI_TIMEOUT["FCGID_*_TIMEOUT"]
    end

    subgraph "Lighttpd"
        LH_PORT["LIGHTTPD_PORT=8080"]
        LH_HOST["LIGHTTPD_FASTCGI_HOST"]
        LH_FPORT["LIGHTTPD_FASTCGI_PORT=3000"]
    end

    SERVER --> FCGI_MAX & FCGI_MIN & FCGI_TIMEOUT
    SERVER --> LH_PORT & LH_HOST & LH_FPORT
```

#### QGIS Server

| Variable | Description |
|----------|-------------|
| `QGIS_PROJECT_FILE` | Path to .qgs/.qgz project |
| `QGIS_SERVER_LOG_LEVEL` | 0=debug, 1=info, 2=warning, 3=critical |
| `QGIS_SERVER_LOG_STDERR` | Log to stderr (default: 1) |
| `QGIS_PLUGINPATH` | Plugin directory |
| `QGIS_AUTH_DB_DIR_PATH` | Auth database location |
| `PGSERVICEFILE` | PostgreSQL service file |

### Volumes

```mermaid
graph TB
    subgraph "Container"
        ETC["/etc/qgisserver<br/>Project files, configs"]
        PLUGINS["/var/www/plugins<br/>QGIS plugins"]
        CACHE["/var/cache/qgisserver<br/>Cache directory"]
        TMP["/tmp<br/>Temporary files"]
    end

    subgraph "Host/Persistent"
        H_DATA["Project data<br/>(read-only)"]
        H_PLUGINS["Custom plugins"]
        V_CACHE["Cache volume"]
        V_TMP["tmpfs"]
    end

    H_DATA -->|"bind mount"| ETC
    H_PLUGINS -->|"bind mount"| PLUGINS
    V_CACHE -->|"volume"| CACHE
    V_TMP -->|"tmpfs"| TMP
```

### Ports

| Port | Service | Mode |
|------|---------|------|
| 8080 | HTTP | Apache, Lighttpd |
| 3000 | FCGI | spawn-fcgi |

---

## File Structure

```
qgis-server/
├── .github/
│   └── workflows/
│       └── build.yaml           # CI/CD pipeline
├── runtime/
│   ├── etc/
│   │   ├── apache2/conf-enabled/
│   │   │   └── qgis.conf        # Apache FCGI config
│   │   └── lighttpd/
│   │       └── lighttpd.conf    # Lighttpd config
│   └── usr/local/bin/
│       ├── start-server         # Entry point
│       └── qgis-mapserv-wrapper # FCGI wrapper
├── tests/
│   └── data/                    # Test project files
├── Dockerfile                   # Multi-stage build
├── Makefile                     # Build commands
├── docker-compose.yaml          # Development
├── docker-compose.test.yaml     # Testing
└── README.md
```

---

## Performance Considerations

### Build Time

| Architecture | Build Method | Approximate Time |
|--------------|--------------|------------------|
| AMD64 | Native | ~45 min |
| ARM64 | Native | ~45 min |
| ARM64 | QEMU emulation | ~3-4 hours |

### Optimization Tips

1. **Use ccache**: Mounted as BuildKit cache for incremental builds
2. **Parallel ninja**: Uses all available cores (`ninja -j$(nproc)`)
3. **GHA Cache**: Preserves layers between CI runs
4. **Separate targets**: Debug builds don't slow down production

### Resource Requirements

| Stage | RAM | Disk |
|-------|-----|------|
| Build (peak) | 8GB+ | 20GB |
| Runtime | 512MB+ | 1GB |

---

## Security

### Non-Root Execution

```yaml
services:
  qgis:
    image: ghcr.io/walkthru-earth/qgis-server:latest
    user: "1000:1000"  # Non-root
    read_only: true     # Immutable filesystem
    volumes:
      - data:/data:ro   # Read-only data
      - /tmp            # Writable tmpfs
```

### Healthcheck

Built-in health check for orchestration:

```dockerfile
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8080/ows?SERVICE=WMS&REQUEST=GetCapabilities || exit 1
```
