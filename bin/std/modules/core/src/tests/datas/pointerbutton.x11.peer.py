"""Hold a real pointer button on an isolated X11 display until the test has polled it."""
import ctypes as c
import os
import sys
import signal
import time
from pathlib import Path

assert os.environ.get('SWAG_TEST_ISOLATED_X11') == '1'
x11, xtst = c.CDLL('libX11.so.6'), c.CDLL('libXtst.so.6')
P = c.c_void_p
x11.XOpenDisplay.argtypes = [c.c_char_p]
x11.XOpenDisplay.restype = P
x11.XCloseDisplay.argtypes = [P]
x11.XSync.argtypes = [P, c.c_int]
xtst.XTestFakeButtonEvent.argtypes = [P, c.c_uint, c.c_int, c.c_ulong]
display = x11.XOpenDisplay(None)
assert display
button, directory = int(sys.argv[1]), Path(sys.argv[2])
signal.signal(signal.SIGTERM, lambda *_: sys.exit(1))
try:
    assert xtst.XTestFakeButtonEvent(display, button, 1, 0)
    x11.XSync(display, 0)
    (directory / 'ready').write_text('ready')
    deadline = time.monotonic() + 4
    while not (directory / 'done').exists():
        if time.monotonic() >= deadline:
            raise TimeoutError('polling fixture did not finish')
        time.sleep(0.005)
finally:
    xtst.XTestFakeButtonEvent(display, button, 0, 0)
    x11.XSync(display, 0)
    x11.XCloseDisplay(display)
