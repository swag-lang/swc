"""Exercise real XKB compose keys on an isolated X11 server."""
import ctypes as c
import json
import os
import sys
import time

assert os.environ.get('SWAG_TEST_ISOLATED_X11') == '1'
x11 = c.CDLL('libX11.so.6')
xtst = c.CDLL('libXtst.so.6')
P, U = c.c_void_p, c.c_ulong
x11.XOpenDisplay.argtypes = [c.c_char_p]
x11.XOpenDisplay.restype = P
x11.XCloseDisplay.argtypes = [P]
x11.XGetKeyboardMapping.argtypes = [P, c.c_ubyte, c.c_int, c.POINTER(c.c_int)]
x11.XGetKeyboardMapping.restype = c.POINTER(U)
x11.XChangeKeyboardMapping.argtypes = [P, c.c_int, c.c_int, c.POINTER(U), c.c_int]
x11.XFree.argtypes = [P]
x11.XSync.argtypes = [P, c.c_int]
x11.XSetInputFocus.argtypes = [P, U, c.c_int, U]
x11.XKeysymToKeycode.argtypes = [P, U]
x11.XKeysymToKeycode.restype = c.c_ubyte
x11.XkbSetAutoRepeatRate.argtypes = [P, c.c_uint, c.c_uint, c.c_uint]
x11.XkbSetAutoRepeatRate.restype = c.c_int
x11.XkbGetAutoRepeatRate.argtypes = [P, c.c_uint, c.POINTER(c.c_uint), c.POINTER(c.c_uint)]
x11.XkbGetAutoRepeatRate.restype = c.c_int
xtst.XTestFakeKeyEvent.argtypes = [P, c.c_uint, c.c_int, U]
display = x11.XOpenDisplay(None)
assert display
codes = [(230, 0xff20), (248, 0xfe51)]  # Multi_key and dead_acute.

def mapping(code):
    width = c.c_int()
    symbols = x11.XGetKeyboardMapping(display, code, 1, c.byref(width))
    assert symbols and width.value > 0
    result = [symbols[i] for i in range(width.value)]
    x11.XFree(symbols)
    return result

def change(code, symbols):
    values = (U * len(symbols))(*symbols)
    x11.XChangeKeyboardMapping(display, code, len(symbols), values, 1)

try:
    mode, saved = sys.argv[1:3]
    if mode == 'setup':
        previous = {str(code): mapping(code) for code, _ in codes}
        with open(saved, 'w', encoding='utf-8') as f:
            json.dump(previous, f)
        for code, symbol in codes:
            change(code, [symbol] + [0] * (len(previous[str(code)]) - 1))
        x11.XSync(display, 0)
    elif mode == 'restore':
        with open(saved, encoding='utf-8') as f:
            previous = json.load(f)
        for code, _ in codes:
            change(code, previous[str(code)])
        x11.XSync(display, 0)
    elif mode in ('send', 'remap', 'held-remap', 'repeat', 'modifiers'):
        x11.XSetInputFocus(display, int(sys.argv[3]), 2, 0)
        def tap(code):
            assert code
            assert xtst.XTestFakeKeyEvent(display, code, 1, 0)
            assert xtst.XTestFakeKeyEvent(display, code, 0, 0)
        if mode == 'modifiers':
            code = x11.XKeysymToKeycode(display, ord('a'))
            shift = x11.XKeysymToKeycode(display, 0xffe1)
            control = x11.XKeysymToKeycode(display, 0xffe3)
            assert code and shift and control
            assert xtst.XTestFakeKeyEvent(display, shift, 1, 0)
            tap(code)
            assert xtst.XTestFakeKeyEvent(display, shift, 0, 0)
            assert xtst.XTestFakeKeyEvent(display, control, 1, 0)
            tap(code)
            assert xtst.XTestFakeKeyEvent(display, control, 0, 0)
        elif mode == 'repeat':
            code = x11.XKeysymToKeycode(display, ord('a'))
            old_delay, old_interval = c.c_uint(), c.c_uint()
            assert x11.XkbGetAutoRepeatRate(display, 0x100, c.byref(old_delay), c.byref(old_interval))
            assert x11.XkbSetAutoRepeatRate(display, 0x100, 150, 40)
            try:
                assert xtst.XTestFakeKeyEvent(display, code, 1, 0)
                x11.XSync(display, 0)
                time.sleep(.7)
            finally:
                assert xtst.XTestFakeKeyEvent(display, code, 0, 0)
                assert x11.XkbSetAutoRepeatRate(display, 0x100, old_delay.value,
                                                old_interval.value)
        elif mode == 'remap':
            change(230, [ord('b')] + [0] * (len(mapping(230)) - 1))
            x11.XSync(display, 0)
            tap(230)
        elif mode == 'held-remap':
            assert xtst.XTestFakeKeyEvent(display, 230, 1, 0)
            x11.XSync(display, 0)
            change(230, [ord('c')] + [0] * (len(mapping(230)) - 1))
            x11.XSync(display, 0)
            assert xtst.XTestFakeKeyEvent(display, 230, 0, 0)
            tap(230)
        else:
            tap(x11.XKeysymToKeycode(display, ord('a')))
            tap(248)
            tap(x11.XKeysymToKeycode(display, ord('e')))
            tap(230)
            tap(x11.XKeysymToKeycode(display, ord("'")))
            shift = x11.XKeysymToKeycode(display, 0xffe1)
            assert xtst.XTestFakeKeyEvent(display, shift, 1, 0)
            tap(x11.XKeysymToKeycode(display, ord('j')))
            assert xtst.XTestFakeKeyEvent(display, shift, 0, 0)
        x11.XSync(display, 0)
    else:
        raise ValueError(mode)
finally:
    x11.XCloseDisplay(display)
