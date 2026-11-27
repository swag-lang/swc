"""Send real keypad keycodes on an isolated X11 display, restoring its lock state."""
import ctypes as c
import os
import sys
import signal
import time
from pathlib import Path

assert os.environ.get('SWAG_TEST_ISOLATED_X11') == '1'
x11, xtst = c.CDLL('libX11.so.6'), c.CDLL('libXtst.so.6')
P, U = c.c_void_p, c.c_ulong
class State(c.Structure):
    _fields_ = [('group', c.c_ubyte), ('locked_group', c.c_ubyte),
                ('base_group', c.c_ushort), ('latched_group', c.c_ushort),
                *[(name, c.c_ubyte) for name in ('mods', 'base_mods', 'latched_mods',
                  'locked_mods', 'compat_state', 'grab_mods', 'compat_grab_mods',
                  'lookup_mods', 'compat_lookup_mods')], ('ptr_buttons', c.c_ushort)]
x11.XOpenDisplay.argtypes = [c.c_char_p]
x11.XOpenDisplay.restype = P
x11.XCloseDisplay.argtypes = [P]
x11.XSync.argtypes = [P, c.c_int]
x11.XSetInputFocus.argtypes = [P, U, c.c_int, U]
x11.XKeysymToKeycode.argtypes = [P, U]
x11.XKeysymToKeycode.restype = c.c_ubyte
x11.XkbKeysymToModifiers.argtypes = [P, U]
x11.XkbKeysymToModifiers.restype = c.c_uint
x11.XkbGetState.argtypes = [P, c.c_uint, c.POINTER(State)]
x11.XkbLockModifiers.argtypes = [P, c.c_uint, c.c_uint, c.c_uint]
xtst.XTestFakeKeyEvent.argtypes = [P, c.c_uint, c.c_int, U]
display = x11.XOpenDisplay(None)
assert display
held = set()
state = State()
num_mask = x11.XkbKeysymToModifiers(display, 0xff7f)
assert num_mask
status = x11.XkbGetState(display, 0x100, c.byref(state))
assert status == 0
mode, directory = int(sys.argv[1]), Path(sys.argv[2])
signal.signal(signal.SIGTERM, lambda *_: sys.exit(1))
try:
    locked = x11.XkbLockModifiers(display, 0x100, num_mask, num_mask if mode in (1, 3) else 0)
    assert locked
    def hold(symbol):
        code = x11.XKeysymToKeycode(display, symbol)
        assert code
        sent = xtst.XTestFakeKeyEvent(display, code, 1, 0)
        assert sent
        held.add(code)
    if mode in (2, 3):
        hold(0xffe1)
    hold(0xff8d if mode == 4 else 0xffb1)
    x11.XSync(display, 0)
    (directory / 'ready').write_text('ready')
    deadline = time.monotonic() + 4
    while not (directory / 'done').exists():
        if time.monotonic() >= deadline:
            raise TimeoutError('polling fixture did not finish')
        time.sleep(0.005)
finally:
    for code in held:
        xtst.XTestFakeKeyEvent(display, code, 0, 0)
    x11.XkbLockModifiers(display, 0x100, num_mask, state.locked_mods & num_mask)
    x11.XSync(display, 0)
    x11.XCloseDisplay(display)
