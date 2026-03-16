#!/usr/bin/env python3
"""Patch QGIS Python files to make GUI imports optional for headless/server builds.

When QGIS is built with WITH_GUI=OFF, the qgis.gui module doesn't exist.
This patch wraps the unconditional GUI imports in try/except so the
processing plugin can still load in headless mode (qgis_process, server).

Usage: fix_headless_imports.py <qgis_python_root>
  e.g. fix_headless_imports.py /usr/local/share/qgis/python
"""
import sys
import os

root = sys.argv[1]

# Map of (relative path -> list of (old, new) replacements)
patches = {
    "qgis/utils.py": [
        (
            'from qgis.PyQt.QtGui import QDesktopServices',
            'try:\n    from qgis.PyQt.QtGui import QDesktopServices\nexcept ImportError:\n    QDesktopServices = None'
        ),
        (
            'from qgis.PyQt.QtWidgets import QPushButton, QApplication',
            'try:\n    from qgis.PyQt.QtWidgets import QPushButton, QApplication\nexcept ImportError:\n    QPushButton = None\n    QApplication = None'
        ),
        (
            'from qgis.gui import QgsMessageBar',
            'try:\n    from qgis.gui import QgsMessageBar\nexcept ImportError:\n    QgsMessageBar = None'
        ),
    ],
    "plugins/processing/tools/dataobjects.py": [
        (
            'from qgis.gui import QgsSublayersDialog',
            'try:\n    from qgis.gui import QgsSublayersDialog\nexcept ImportError:\n    QgsSublayersDialog = None'
        ),
    ],
}

patched = 0
for relpath, replacements in patches.items():
    filepath = os.path.join(root, relpath)
    if not os.path.exists(filepath):
        print(f"  SKIP {relpath} (not found)")
        continue

    with open(filepath, 'r') as f:
        content = f.read()

    changed = False
    for old, new in replacements:
        if old in content:
            content = content.replace(old, new)
            changed = True

    if changed:
        with open(filepath, 'w') as f:
            f.write(content)
        patched += 1
        print(f"  Patched {relpath}")
    else:
        print(f"  SKIP {relpath} (already patched or pattern not found)")

print(f"Patched {patched} file(s) for headless operation")
