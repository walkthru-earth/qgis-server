#!/bin/bash
# =============================================================================
# QGIS Server Docker Image — Smoke Test Suite
# =============================================================================
# Runs inside the container to validate all capabilities.
# Usage:
#   docker run --rm -e QT_QPA_PLATFORM=offscreen \
#     -v ./tests:/tests:ro \
#     walkthruearth/qgis-server:latest /tests/smoke-test.sh
#
# Exit codes: 0 = all critical tests pass, 1 = critical failure
# =============================================================================

set -o pipefail

# --- Helpers -----------------------------------------------------------------
PASS=0; FAIL=0; WARN=0; TOTAL=0
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

# Markdown report file (for GitHub Actions job summary)
MD_REPORT="${SMOKE_TEST_REPORT:-/tmp/smoke-test-summary.md}"
: > "$MD_REPORT"

md() { echo "$@" >> "$MD_REPORT"; }

pass()     { ((PASS++)); ((TOTAL++)); echo -e "  ${GREEN}✓${NC} $1"; md "| ✅ | $1 |"; }
fail()     { ((FAIL++)); ((TOTAL++)); echo -e "  ${RED}✗${NC} $1"; md "| ❌ | $1 |"; }
warn()     { ((WARN++)); ((TOTAL++)); echo -e "  ${YELLOW}⚠${NC} $1"; md "| ⚠️ | $1 |"; }
info()     { echo -e "  ${CYAN}·${NC} $1"; }
section()  { echo -e "\n${BOLD}[$1]${NC}"; md ""; md "### $1"; md ""; md "| Status | Check |"; md "|--------|-------|"; }

# Critical test — failure means exit 1
critical() {
    local desc="$1"; shift
    if "$@" >/dev/null 2>&1; then pass "$desc"; else fail "$desc (CRITICAL)"; CRITICAL_FAIL=1; fi
}

# Non-critical test — failure is a warning
check() {
    local desc="$1"; shift
    if "$@" >/dev/null 2>&1; then pass "$desc"; else warn "$desc"; fi
}

CRITICAL_FAIL=0
TEST_DATA="${TEST_DATA:-/tests/data}"
export QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-offscreen}"

echo -e "${BOLD}QGIS Server Docker Image — Smoke Test${NC}"
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "==========================================="

md "## 🔍 Smoke Test Report"
md "_$(date -u +%Y-%m-%dT%H:%M:%SZ)_"

# =============================================================================
# 1. VERSIONS
# =============================================================================
echo -e "\n${BOLD}[Versions]${NC}"

GDAL_VER=$(gdalinfo --version 2>/dev/null | head -1)
info "GDAL: $GDAL_VER"

QGIS_VER=$(qgis_mapserv.fcgi 2>&1 | grep -oP 'QGIS \K[0-9.]+' || echo "unknown")
info "QGIS Server: $QGIS_VER"

PYTHON_VER=$(python3 --version 2>&1)
info "Python: $PYTHON_VER"

PROJ_VER=$(projinfo 2>&1 | head -1 || echo "unknown")
info "PROJ: $PROJ_VER"

md ""
md "### Versions"
md ""
md "| Component | Version |"
md "|-----------|---------|"
md "| GDAL | ${GDAL_VER} |"
md "| QGIS Server | ${QGIS_VER} |"
md "| Python | ${PYTHON_VER} |"
md "| PROJ | ${PROJ_VER} |"

# =============================================================================
# 2. GDAL DRIVERS
# =============================================================================
section "GDAL Raster Drivers"

RASTER_DRIVERS=$(gdalinfo --formats 2>/dev/null | tail -n +2)
RASTER_COUNT=$(echo "$RASTER_DRIVERS" | wc -l)
info "Total raster drivers: $RASTER_COUNT"

# All raster drivers present — list them in the markdown report
RASTER_NAMES=$(echo "$RASTER_DRIVERS" | sed 's/^ *//' | cut -d' ' -f1 | sort | tr '\n' ', ' | sed 's/,$//')
md "| ℹ️ | **$RASTER_COUNT raster drivers** |"

# Critical raster drivers (must have)
for drv in GTiff COG VRT PNG JPEG Zarr GPKG WMS WMTS; do
    if echo "$RASTER_DRIVERS" | grep -qiw "$drv"; then
        pass "Raster: $drv"
    else
        fail "Raster: $drv (CRITICAL)"
        CRITICAL_FAIL=1
    fi
done

# Nice-to-have raster drivers
for drv in WEBP MBTiles JP2OpenJPEG GRIB PDF PostGISRaster STACIT STACTA WCS; do
    if echo "$RASTER_DRIVERS" | grep -qiw "$drv"; then
        pass "Raster: $drv"
    else
        warn "Raster: $drv (not available)"
    fi
done

# Expected missing (ubuntu-small)
for drv in netCDF HDF5; do
    if echo "$RASTER_DRIVERS" | grep -qiw "$drv"; then
        pass "Raster: $drv"
    else
        info "Raster: $drv (not in ubuntu-small)"
    fi
done

# Full driver list in collapsible markdown
md ""
md "<details><summary>All $RASTER_COUNT raster drivers</summary>"
md ""
md "\`\`\`"
md "$RASTER_NAMES"
md "\`\`\`"
md "</details>"

section "GDAL Vector Drivers"

VECTOR_DRIVERS=$(ogrinfo --formats 2>/dev/null | tail -n +2)
VECTOR_COUNT=$(echo "$VECTOR_DRIVERS" | wc -l)
info "Total vector drivers: $VECTOR_COUNT"

VECTOR_NAMES=$(echo "$VECTOR_DRIVERS" | sed 's/^ *//' | cut -d' ' -f1 | sort | tr '\n' ', ' | sed 's/,$//')
md "| ℹ️ | **$VECTOR_COUNT vector drivers** |"

# Critical vector drivers (must have)
for drv in GPKG "ESRI Shapefile" GeoJSON FlatGeobuf Parquet CSV PostgreSQL WFS GML; do
    if echo "$VECTOR_DRIVERS" | grep -qi "$drv"; then
        pass "Vector: $drv"
    else
        fail "Vector: $drv (CRITICAL)"
        CRITICAL_FAIL=1
    fi
done

# Nice-to-have vector drivers
for drv in ADBC MVT PMTiles ODS XLSX KML JSONFG GeoJSONSeq GPX OSM SQLite DXF OAPIF MBTiles OpenFileGDB PDF; do
    if echo "$VECTOR_DRIVERS" | grep -qi "$drv"; then
        pass "Vector: $drv"
    else
        warn "Vector: $drv (not available)"
    fi
done

# Full driver list in collapsible markdown
md ""
md "<details><summary>All $VECTOR_COUNT vector drivers</summary>"
md ""
md "\`\`\`"
md "$VECTOR_NAMES"
md "\`\`\`"
md "</details>"

# =============================================================================
# 3. GDAL CLI TOOLS
# =============================================================================
section "GDAL CLI Tools"

for tool in gdalinfo gdal_translate gdalwarp ogr2ogr ogrinfo gdal_create gdal; do
    if command -v "$tool" >/dev/null 2>&1; then
        pass "$tool"
    else
        warn "$tool (not found)"
    fi
done

# New gdal unified CLI subcommands
if command -v gdal >/dev/null 2>&1; then
    for sub in "vector convert" "vector info" "raster convert" "raster info" "raster pipeline"; do
        if gdal $sub --help >/dev/null 2>&1; then
            pass "gdal $sub"
        else
            warn "gdal $sub (not available)"
        fi
    done
fi

# =============================================================================
# 4. ZARR COMPRESSORS
# =============================================================================
section "Zarr Compressors"

ZARR_COMPRESSORS=$(gdalinfo --format Zarr 2>/dev/null | grep -oP 'COMPRESSORS=\K[^ ]+' | head -1)
info "Available: $ZARR_COMPRESSORS"

for comp in zlib gzip lzma zstd blosc lz4; do
    if echo "$ZARR_COMPRESSORS" | grep -qi "$comp"; then
        pass "Compressor: $comp"
    else
        warn "Compressor: $comp (not compiled in)"
    fi
done

# =============================================================================
# 5. GEOPARQUET
# =============================================================================
section "GeoParquet"

critical "Parquet driver loaded" bash -c 'ogrinfo --formats | grep -q Parquet'

if [ -f "$TEST_DATA/testlayer.shp" ]; then
    # Write with optimized options
    if gdal vector convert "$TEST_DATA/testlayer.shp" /tmp/test_smoke.parquet \
        --lco COMPRESSION=ZSTD \
        --lco SORT_BY_BBOX=YES \
        --lco WRITE_COVERING_BBOX=YES \
        --lco USE_PARQUET_GEO_TYPES=YES >/dev/null 2>&1; then
        pass "GeoParquet write (ZSTD + native types + bbox)"
    else
        fail "GeoParquet write (CRITICAL)"
        CRITICAL_FAIL=1
    fi

    # Read back
    if gdal vector info /tmp/test_smoke.parquet 2>/dev/null | grep -q "Feature Count"; then
        FEAT_COUNT=$(gdal vector info /tmp/test_smoke.parquet 2>/dev/null | grep -oP 'Feature Count: \K[0-9]+')
        pass "GeoParquet read (${FEAT_COUNT} features)"
    else
        fail "GeoParquet read (CRITICAL)"
        CRITICAL_FAIL=1
    fi
    rm -f /tmp/test_smoke.parquet
else
    warn "GeoParquet read/write (no test data at $TEST_DATA/testlayer.shp)"
fi

# =============================================================================
# 6. QGIS PROCESSING (qgis_process)
# =============================================================================
section "qgis_process Algorithms"

# Get algorithm list once (timeout guards against shutdown hang)
ALGO_LIST=$(timeout 60 qgis_process list 2>&1 || true)

NATIVE_COUNT=$(echo "$ALGO_LIST" | grep -c "native:" || true)
GDAL_COUNT=$(echo "$ALGO_LIST" | grep -c "gdal:" || true)
TOTAL_ALGO=$((NATIVE_COUNT + GDAL_COUNT))

info "native: $NATIVE_COUNT, gdal: $GDAL_COUNT, total: $TOTAL_ALGO"
md "| ℹ️ | native: **$NATIVE_COUNT**, gdal: **$GDAL_COUNT**, total: **$TOTAL_ALGO** |"

if [ "$NATIVE_COUNT" -gt 200 ]; then
    pass "Native algorithms ($NATIVE_COUNT > 200)"
else
    fail "Native algorithms ($NATIVE_COUNT <= 200) (CRITICAL)"
    CRITICAL_FAIL=1
fi

if [ "$GDAL_COUNT" -gt 30 ]; then
    pass "GDAL algorithms ($GDAL_COUNT > 30) — processing plugin loaded"
else
    warn "GDAL algorithms ($GDAL_COUNT <= 30) — processing plugin may not be loaded"
fi

# Check for processing plugin errors
if echo "$ALGO_LIST" | grep -q "error loading plugin: processing"; then
    warn "Processing plugin had load errors"
fi

# =============================================================================
# 7. QGIS_PROCESS EXECUTION
# =============================================================================
section "qgis_process Execution"

if [ -f "$TEST_DATA/testlayer.shp" ]; then
    # Buffer test (timeout guards against qgis_process hanging on shutdown crash)
    timeout 60 qgis_process run native:buffer -- \
        INPUT="$TEST_DATA/testlayer.shp" DISTANCE=1 OUTPUT=/tmp/buffered.gpkg >/dev/null 2>&1 || true
    if [ -f /tmp/buffered.gpkg ]; then
        BUF_COUNT=$(ogrinfo -so /tmp/buffered.gpkg -al 2>/dev/null | grep -oP 'Feature Count: \K[0-9]+' || echo 0)
        pass "native:buffer ($BUF_COUNT features buffered)"
        rm -f /tmp/buffered.gpkg
    else
        fail "native:buffer — output not created (CRITICAL)"
        CRITICAL_FAIL=1
    fi
else
    warn "qgis_process execution (no test data)"
fi

# =============================================================================
# 8. PYTHON BINDINGS
# =============================================================================
section "Python Bindings"

# GDAL Python
if python3 -c "from osgeo import gdal; print(gdal.__version__)" >/dev/null 2>&1; then
    GDAL_PY_VER=$(python3 -c "from osgeo import gdal; print(gdal.__version__)" 2>/dev/null)
    pass "osgeo.gdal ($GDAL_PY_VER)"
else
    warn "osgeo.gdal (not available)"
fi

if python3 -c "from osgeo import ogr" >/dev/null 2>&1; then
    pass "osgeo.ogr"
else
    warn "osgeo.ogr (not available)"
fi

if python3 -c "from osgeo import osr" >/dev/null 2>&1; then
    pass "osgeo.osr"
else
    warn "osgeo.osr (not available)"
fi

# QGIS Python
critical "qgis.core" python3 -c "from qgis.core import QgsApplication"

if python3 -c "from qgis.analysis import QgsNativeAlgorithms" >/dev/null 2>&1; then
    pass "qgis.analysis"
else
    warn "qgis.analysis (not available)"
fi

if python3 -c "from qgis.server import QgsServer" >/dev/null 2>&1; then
    pass "qgis.server"
else
    warn "qgis.server (not available)"
fi

# PyQt6
for mod in PyQt6.QtCore PyQt6.QtGui PyQt6.QtWidgets PyQt6.QtSvg PyQt6.QtNetwork; do
    if python3 -c "import $mod" >/dev/null 2>&1; then
        pass "$mod"
    else
        warn "$mod (not available)"
    fi
done

# Processing plugin Python imports
if python3 -c "import processing" >/dev/null 2>&1; then
    pass "processing (Python module)"
else
    warn "processing (Python module not importable)"
fi

# =============================================================================
# 9. SERVER INFRASTRUCTURE
# =============================================================================
section "Server Infrastructure"

for bin in apache2 lighttpd spawn-fcgi qgis_mapserv.fcgi; do
    if command -v "$bin" >/dev/null 2>&1; then
        pass "$bin"
    else
        warn "$bin (not found)"
    fi
done

check "Apache mod_fcgid" test -f /etc/apache2/mods-available/fcgid.conf
check "Apache qgis.conf" test -f /etc/apache2/conf-enabled/qgis.conf
check "start-server entrypoint" test -x /usr/local/bin/start-server

# =============================================================================
# 10. FONTS
# =============================================================================
section "Fonts"

FONT_COUNT=$(fc-list 2>/dev/null | wc -l)
info "Installed fonts: $FONT_COUNT"
if [ "$FONT_COUNT" -gt 50 ]; then
    pass "Font collection ($FONT_COUNT fonts)"
else
    warn "Font collection ($FONT_COUNT fonts — may be insufficient for map rendering)"
fi

# =============================================================================
# SUMMARY
# =============================================================================
echo ""
echo "==========================================="
echo -e "${BOLD}SUMMARY${NC}"
echo "==========================================="
echo -e "  ${GREEN}Passed:${NC}  $PASS"
echo -e "  ${YELLOW}Warned:${NC}  $WARN"
echo -e "  ${RED}Failed:${NC}  $FAIL"
echo -e "  Total:   $TOTAL"
echo ""

md ""
md "---"
md ""
if [ "$CRITICAL_FAIL" -eq 1 ]; then
    md "### ❌ FAILED — $PASS passed, $WARN warned, $FAIL failed (of $TOTAL)"
    echo -e "${RED}${BOLD}RESULT: FAILED${NC} — critical tests did not pass"
    exit 1
else
    md "### ✅ PASSED — $PASS passed, $WARN warned, $FAIL failed (of $TOTAL)"
    echo -e "${GREEN}${BOLD}RESULT: PASSED${NC} — all critical tests OK"
    exit 0
fi
