# QGIS Server Docker - Multi-Architecture

Production-ready QGIS Server Docker image with multi-architecture support.

## Features

- **Multi-Architecture**: Supports both `linux/amd64` and `linux/arm64`
- **Multiple Server Modes**: Apache, Lighttpd, or spawn-fcgi
- **Production Ready**: Healthchecks, non-root user support, read-only filesystem
- **GeoParquet Support**: Read/write GeoParquet via standalone GDAL plugin (Apache Arrow 23.0.1)
- **Processing CLI**: `qgis_process` with 280+ native algorithms, 57 GDAL algorithms, and PyQGIS scripting
- **Latest Stack**: GDAL 3.12.2, Ubuntu Noble

### Architecture Details

| Architecture | QGIS Version | Build Method |
|-------------|--------------|--------------|
| AMD64 | 3.44.7 | Compiled from source |
| ARM64 | 3.44.7 | Compiled from source |

Both architectures are built natively on Hetzner Cloud servers for fast, consistent builds.

## Quick Start

```bash
# Run QGIS Server
docker run -d -p 8080:8080 \
    -v /path/to/project:/etc/qgisserver:ro \
    -e QGIS_PROJECT_FILE=/etc/qgisserver/project.qgs \
    ghcr.io/walkthru-earth/qgis-server:latest

# Test it
curl "http://localhost:8080/ows?SERVICE=WMS&REQUEST=GetCapabilities"
```

## Images

| Image | Description |
|-------|-------------|
| `ghcr.io/walkthru-earth/qgis-server:latest` | Production server (multi-arch) |
| `docker.io/walkthruearth/qgis-server:latest` | Docker Hub mirror (multi-arch) |

### Available Tags

- `latest` - Latest build from main branch
- `vX.Y.Z` - Specific version releases

## Configuration

### Environment Variables

#### Server Mode

| Variable | Default | Description |
|----------|---------|-------------|
| `SERVER` | `apache` | Server mode: `apache`, `lighttpd`, `spawn-fcgi` |

#### Apache/FCGI Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `FCGID_MAX_REQUESTS_PER_PROCESS` | `1000` | Requests before process restart |
| `FCGID_MIN_PROCESSES` | `1` | Minimum FCGI processes |
| `FCGID_MAX_PROCESSES` | `5` | Maximum FCGI processes |
| `FCGID_BUSY_TIMEOUT` | `300` | Busy timeout (seconds) |
| `FCGID_IDLE_TIMEOUT` | `300` | Idle timeout (seconds) |
| `FCGID_IO_TIMEOUT` | `40` | I/O timeout (seconds) |

#### Lighttpd/spawn-fcgi Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `LIGHTTPD_PORT` | `8080` | Lighttpd listen port |
| `LIGHTTPD_FASTCGI_HOST` | `spawn-fcgi` | FCGI backend host |
| `LIGHTTPD_FASTCGI_PORT` | `3000` | FCGI backend port |
| `LIGHTTPD_FASTCGI_SOCKET` | - | Unix socket (alternative to port) |

#### QGIS Server Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `QGIS_PROJECT_FILE` | - | Path to QGIS project file |
| `QGIS_SERVER_LOG_LEVEL` | - | Log level (0=debug, 3=critical) |
| `QGIS_SERVER_LOG_STDERR` | `1` | Log to stderr |
| `QGIS_PLUGINPATH` | `/var/www/plugins` | Plugin directory |
| `QGIS_AUTH_DB_DIR_PATH` | - | Auth database directory |
| `PGSERVICEFILE` | - | PostgreSQL service file |
| `QT_QPA_PLATFORM` | `offscreen` | Qt platform plugin (required for headless Qt6) |

## Server Modes

### Apache (Default)

Standard Apache with mod_fcgid. Best for most deployments.

```bash
docker run -p 8080:8080 ghcr.io/walkthru-earth/qgis-server:latest
```

### Lighttpd + spawn-fcgi

Lightweight setup, ideal for Kubernetes.

```yaml
# docker-compose.yaml
services:
  fcgi:
    image: ghcr.io/walkthru-earth/qgis-server:latest
    environment:
      SERVER: spawn-fcgi
    user: "1000:1000"
    read_only: true

  web:
    image: ghcr.io/walkthru-earth/qgis-server:latest
    environment:
      SERVER: lighttpd
      LIGHTTPD_FASTCGI_HOST: fcgi
    ports:
      - "8080:8080"
    depends_on:
      - fcgi
```

## Building

### Local Build (Single Architecture)

```bash
# Build for current architecture
make build-server

# Build debug variant
make build-debug

# Run locally
make run
```

### Multi-Architecture Build

```bash
# Setup buildx
make buildx-setup

# Build and push multi-arch images
make buildx-all
```

### Build Arguments

| Argument | Default | Description |
|----------|---------|-------------|
| `QGIS_VERSION` | `final-3_44_7` | QGIS branch/tag to build |
| `GDAL_VERSION` | `3.12.2` | GDAL base image version |

```bash
# Build specific QGIS version
make build-server QGIS_VERSION=final-3_44_7
```

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Multi-Arch Manifest                       │
│         ghcr.io/walkthru-earth/qgis-server:latest           │
├─────────────────────────────┬───────────────────────────────┤
│       linux/amd64           │         linux/arm64           │
├─────────────────────────────┴───────────────────────────────┤
│                      Server Stage                            │
│  ┌─────────────────────────────────────────────────────────┐│
│  │ Apache2 / Lighttpd / spawn-fcgi                         ││
│  │ QGIS Server FCGI binary + qgis_process CLI              ││
│  │ Qt6 Runtime Libraries                                   ││
│  │ Python 3 + PyQt6 + Processing Plugin                    ││
│  │ GDAL GeoParquet Plugin (Apache Arrow)                   ││
│  └─────────────────────────────────────────────────────────┘│
├─────────────────────────────────────────────────────────────┤
│                      Base: GDAL 3.12.2                       │
│               ghcr.io/osgeo/gdal:ubuntu-small               │
└─────────────────────────────────────────────────────────────┘
```

## Volumes

| Path | Purpose |
|------|---------|
| `/etc/qgisserver` | Project files, configs |
| `/var/www/plugins` | QGIS Server plugins |
| `/var/cache/qgisserver` | Cache directory |
| `/tmp` | Temporary files |

## Health Check

The container includes a built-in health check:

```bash
curl -f http://localhost:8080/ows?SERVICE=WMS&REQUEST=GetCapabilities
```

## License

MIT License - See [LICENSE](LICENSE) for details.

## Links

- [QGIS Server Documentation](https://docs.qgis.org/latest/en/docs/server_manual/)
- [GDAL Docker Images](https://github.com/OSGeo/gdal/tree/master/docker)
- [Walkthru Earth](https://walkthru.earth)
