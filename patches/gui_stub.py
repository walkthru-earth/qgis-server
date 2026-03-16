"""Stub qgis.gui module for headless builds (WITH_GUI=OFF).

When QGIS is built without GUI support, the qgis.gui C extension doesn't
exist. This stub module is installed as qgis/gui.py so that all
`from qgis.gui import X` statements succeed by returning a no-op stub class.

This allows the processing plugin and other code that conditionally uses
GUI classes to load without modification in headless mode (qgis_process,
QGIS Server).
"""


class _StubMeta(type):
    """Metaclass that makes class-level attribute access return _Stub."""

    def __getattr__(cls, name):
        return cls

    def __bool__(cls):
        return False


class _Stub(metaclass=_StubMeta):
    """No-op stub that absorbs any call, instantiation, or attribute access.

    Works both as a class (e.g. _Stub.WidgetType.Standard) and as an
    instance (e.g. _Stub().someMethod()), returning itself in all cases.
    """

    def __init__(self, *args, **kwargs):
        pass

    def __call__(self, *args, **kwargs):
        return _Stub()

    def __getattr__(self, name):
        return _Stub

    def __bool__(self):
        return False

    def __iter__(self):
        return iter([])

    def __len__(self):
        return 0


def __getattr__(name):
    """Module-level __getattr__: any attribute access returns _Stub class."""
    return _Stub
