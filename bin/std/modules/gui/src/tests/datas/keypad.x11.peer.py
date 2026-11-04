"""Send real keypad keycodes on an isolated X11 display, restoring its lock state."""
import ctypes as c
import os
import sys

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
try:
    x11.XSetInputFocus(display, int(sys.argv[1]), 2, 0)
    locked = x11.XkbLockModifiers(display, 0x100, num_mask, 0)
    assert locked
    def key(symbol, down):
        code = x11.XKeysymToKeycode(display, symbol)
        assert code
        sent = xtst.XTestFakeKeyEvent(display, code, down, 0)
        assert sent
        if down:
            held.add(code)
        else:
            held.discard(code)
    def tap(symbol):
        key(symbol, 1)
        key(symbol, 0)
    tap(0xff8d)  # KP_Enter
    # KP_Delete selects the physical decimal/navigation key; XKB also has an always-decimal key.
    for symbol in (*range(0xffb0, 0xffba), 0xff9f):
        tap(symbol)
    key(0xffe1, 1)
    tap(0xffb1)  # Shift alone keeps navigation while NumLock is off.
    key(0xffe1, 0)
    tap(0xff7f)  # Real NumLock press, rather than hardcoding its modifier bit.
    for symbol in (*range(0xffb0, 0xffba), 0xff9f):
        tap(symbol)
    key(0xffe1, 1)
    tap(0xffb1)  # Shift temporarily selects End with NumLock on.
    key(0xffe1, 0)
    key(0xffb1, 1)
    tap(0xff7f)  # Release must retain the identity chosen before the lock changed.
    key(0xffb1, 0)
    x11.XSync(display, 0)
    print('ok', flush=True)
finally:
    for code in held:
        xtst.XTestFakeKeyEvent(display, code, 0, 0)
    x11.XkbLockModifiers(display, 0x100, num_mask, state.locked_mods & num_mask)
    x11.XSync(display, 0)
    x11.XCloseDisplay(display)
