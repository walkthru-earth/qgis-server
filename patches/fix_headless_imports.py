#!/usr/bin/env python3
"""Patch qgis/utils.py to make GUI imports optional for headless/server builds.

When QGIS is built with WITH_GUI=OFF, the qgis.gui module doesn't exist.
This patch wraps the unconditional GUI imports in try/except so the
processing plugin can still load in headless mode (qgis_process, server).
"""
import re
import sys

filepath = sys.argv[1]

with open(filepath, 'r') as f:
    content = f.read()

replacements = [
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
]

for old, new in replacements:
    content = content.replace(old, new)

with open(filepath, 'w') as f:
    f.write(content)
