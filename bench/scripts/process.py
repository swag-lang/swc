"""Select the host process backend without importing foreign OS APIs."""
import os
if os.name == 'nt':
    import winproc as _backend
else:
    import linuxproc as _backend

run = _backend.run


def __getattr__(name):
    # Machine accounting also consumes private Windows counter helpers.
    return getattr(_backend, name)
