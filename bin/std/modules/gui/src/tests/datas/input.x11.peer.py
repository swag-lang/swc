"""Independent real XTEST input peer for the isolated native GUI fixture."""
import ctypes as c
import sys

x11, xtst = c.CDLL('libX11.so.6'), c.CDLL('libXtst.so.6')
P, U = c.c_void_p, c.c_ulong
x11.XOpenDisplay.argtypes = [c.c_char_p]
x11.XOpenDisplay.restype = P
x11.XDefaultRootWindow.argtypes = [P]
x11.XDefaultRootWindow.restype = U
x11.XTranslateCoordinates.argtypes = [P, U, U, c.c_int, c.c_int, c.POINTER(c.c_int), c.POINTER(c.c_int), c.POINTER(U)]
x11.XKeysymToKeycode.argtypes = [P, U]
x11.XKeysymToKeycode.restype = c.c_uint8
x11.XSetInputFocus.argtypes = [P, U, c.c_int, U]
x11.XSync.argtypes = [P, c.c_int]
x11.XCloseDisplay.argtypes = [P]
xtst.XTestFakeMotionEvent.argtypes = [P, c.c_int, c.c_int, c.c_int, U]
xtst.XTestFakeButtonEvent.argtypes = [P, c.c_uint, c.c_int, U]
xtst.XTestFakeKeyEvent.argtypes = [P, c.c_uint, c.c_int, U]
display = x11.XOpenDisplay(None)
assert display
try:
    window = int(sys.argv[1])
    root = x11.XDefaultRootWindow(display)
    x, y, child = c.c_int(), c.c_int(), U()
    assert x11.XTranslateCoordinates(display, window, root, 120, 120, c.byref(x), c.byref(y), c.byref(child))
    x11.XSetInputFocus(display, window, 2, 0)
    assert xtst.XTestFakeMotionEvent(display, -1, x.value, y.value, 0)
    # Both edges are queued before the next GUI frame; polling alone loses this click.
    for button in (1, 8, 4):
        assert xtst.XTestFakeButtonEvent(display, button, 1, 0)
        assert xtst.XTestFakeButtonEvent(display, button, 0, 0)
    def key(symbol, pressed):
        code = x11.XKeysymToKeycode(display, symbol)
        assert code and xtst.XTestFakeKeyEvent(display, code, pressed, 0)
    key(0xffe1, 1)
    key(ord('a'), 1)
    key(ord('a'), 0)
    key(0xffe1, 0)
    key(0xffe3, 1)
    key(ord('a'), 1)
    key(ord('a'), 0)
    key(0xffe3, 0)
    x11.XSync(display, 0)
    print('ok', flush=True)
finally:
    x11.XCloseDisplay(display)
