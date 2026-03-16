#!/bin/bash
# Apply all patches for building QGIS on Ubuntu Noble (Qt 6.4, SIP 6.8)
# These patches will be unnecessary once the base image moves to Ubuntu 25.04+
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
QGIS_SRC="${1:-.}"

echo "Applying patches to QGIS source at: ${QGIS_SRC}"

# 1. Qt 6.4: boundValueNames() requires Qt 6.6+
#    Replace with empty QStringList (used for debug logging only)
sed -i 's/query->boundValueNames()/QStringList()/g' \
    "${QGIS_SRC}/src/core/auth/qgsauthconfigurationstoragedb.cpp"
echo "  [1/3] Patched boundValueNames() for Qt 6.4"

# 2. Qt 6.4: MOC enforces sizeof(T) on forward-declared pointer types
#    Qt 6.6+ relaxed this. Patch the system header to match.
find /usr/include -name 'qmetatype.h' -path '*/qt6/*' -exec \
    sed -i 's/static_assert(sizeof(T), "Type argument of Q_PROPERTY or Q_DECLARE_METATYPE(T\*) must be fully defined");/\/\/ static_assert removed for Qt 6.4 compat (relaxed in Qt 6.6+)/g' {} \;
echo "  [2/3] Patched qmetatype.h static_assert for Qt 6.4"

# 3. SIP 6.8: Missing QList<qint64> mapped type (needs Qt 6.5+ PyQt6)
#    Append the mapped type to conversions.sip
cat "${SCRIPT_DIR}/qlist_qint64.sip" >> "${QGIS_SRC}/python/PyQt6/core/conversions.sip"
echo "  [3/3] Added QList<qint64> SIP mapped type"

echo "All build patches applied successfully"
