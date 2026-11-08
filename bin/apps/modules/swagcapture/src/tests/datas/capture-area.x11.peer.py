"""Drag a real XTEST pointer across the isolated Capture area overlay."""
import ctypes as c
import os
import time

assert os.environ.get('SWAG_TEST_ISOLATED_X11') == '1'
x11 = c.CDLL('libX11.so.6')
xtst = c.CDLL('libXtst.so.6')
pointer, unsigned = c.c_void_p, c.c_ulong
x11.XOpenDisplay.argtypes = [c.c_char_p]
x11.XOpenDisplay.restype = pointer
x11.XDefaultRootWindow.argtypes = [pointer]
x11.XDefaultRootWindow.restype = unsigned
x11.XDisplayWidth.argtypes = [pointer, c.c_int]
x11.XDisplayHeight.argtypes = [pointer, c.c_int]
x11.XQueryTree.argtypes = [pointer, unsigned, c.POINTER(unsigned), c.POINTER(unsigned),
                           c.POINTER(c.POINTER(unsigned)), c.POINTER(c.c_uint)]
x11.XGetGeometry.argtypes = [pointer, unsigned, c.POINTER(unsigned), c.POINTER(c.c_int),
                             c.POINTER(c.c_int), c.POINTER(c.c_uint), c.POINTER(c.c_uint),
                             c.POINTER(c.c_uint), c.POINTER(c.c_uint)]
x11.XFree.argtypes = [pointer]
x11.XSync.argtypes = [pointer, c.c_int]
x11.XCloseDisplay.argtypes = [pointer]
xtst.XTestFakeMotionEvent.argtypes = [pointer, c.c_int, c.c_int, c.c_int, unsigned]
xtst.XTestFakeButtonEvent.argtypes = [pointer, c.c_uint, c.c_int, unsigned]

display = x11.XOpenDisplay(None)
assert display
try:
    root = x11.XDefaultRootWindow(display)
    screen_width = x11.XDisplayWidth(display, 0)
    screen_height = x11.XDisplayHeight(display, 0)
    deadline = time.monotonic() + 5
    overlay_found = False
    while time.monotonic() < deadline and not overlay_found:
        queried_root, parent = unsigned(), unsigned()
        children, count = c.POINTER(unsigned)(), c.c_uint()
        assert x11.XQueryTree(display, root, c.byref(queried_root), c.byref(parent),
                              c.byref(children), c.byref(count))
        try:
            for index in range(count.value):
                geometry_root, x, y = unsigned(), c.c_int(), c.c_int()
                width, height, border, depth = c.c_uint(), c.c_uint(), c.c_uint(), c.c_uint()
                if x11.XGetGeometry(display, children[index], c.byref(geometry_root),
                                    c.byref(x), c.byref(y), c.byref(width), c.byref(height),
                                    c.byref(border), c.byref(depth)):
                    if width.value == screen_width and height.value == screen_height:
                        overlay_found = True
                        break
        finally:
            x11.XFree(children)
        if not overlay_found:
            time.sleep(0.01)
    assert overlay_found, 'Capture area overlay did not appear'
    time.sleep(0.1)
    assert xtst.XTestFakeMotionEvent(display, -1, 18, 27, 0)
    assert xtst.XTestFakeButtonEvent(display, 1, 1, 0)
    x11.XSync(display, 0)
    time.sleep(0.05)
    assert xtst.XTestFakeMotionEvent(display, -1, 50, 54, 0)
    x11.XSync(display, 0)
    time.sleep(0.05)
    assert xtst.XTestFakeButtonEvent(display, 1, 0, 0)
    x11.XSync(display, 0)
finally:
    x11.XCloseDisplay(display)
