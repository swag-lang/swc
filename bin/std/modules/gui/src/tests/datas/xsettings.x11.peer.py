"""Own XSETTINGS on an isolated X server and publish live desktop settings."""
import ctypes as c
import os
import pathlib
import struct
import sys
import time

assert os.environ.get('SWAG_TEST_ISOLATED_X11') == '1'
root = pathlib.Path(sys.argv[1])
x11 = c.CDLL('libX11.so.6')
P, U = c.c_void_p, c.c_ulong
x11.XOpenDisplay.argtypes = [c.c_char_p]
x11.XOpenDisplay.restype = P
x11.XDefaultRootWindow.argtypes = [P]
x11.XDefaultRootWindow.restype = U
x11.XCreateSimpleWindow.argtypes = [P, U, c.c_int, c.c_int, c.c_uint, c.c_uint,
                                    c.c_uint, U, U]
x11.XCreateSimpleWindow.restype = U
x11.XInternAtom.argtypes = [P, c.c_char_p, c.c_int]
x11.XInternAtom.restype = U
x11.XSetSelectionOwner.argtypes = [P, U, U, U]
x11.XGetSelectionOwner.argtypes = [P, U]
x11.XGetSelectionOwner.restype = U
x11.XSendEvent.argtypes = [P, U, c.c_int, c.c_long, P]
x11.XSendEvent.restype = c.c_int
x11.XChangeProperty.argtypes = [P, U, U, U, c.c_int, c.c_int, P, c.c_int]
x11.XSync.argtypes = [P, c.c_int]
x11.XDestroyWindow.argtypes = [P, U]
x11.XCloseDisplay.argtypes = [P]
display = x11.XOpenDisplay(None)
assert display
window = x11.XCreateSimpleWindow(display, x11.XDefaultRootWindow(display),
                                 0, 0, 1, 1, 0, 0, 0)
selection = x11.XInternAtom(display, b'_XSETTINGS_S0', 0)
property_atom = x11.XInternAtom(display, b'_XSETTINGS_SETTINGS', 0)
manager_atom = x11.XInternAtom(display, b'MANAGER', 0)
x11.XSetSelectionOwner(display, selection, window, 0)
x11.XSync(display, 0)
assert x11.XGetSelectionOwner(display, selection) == window

class ClientMessage(c.Structure):
    _fields_ = [('type', c.c_int), ('serial', U), ('send_event', c.c_int),
                ('display', P), ('window', U), ('message_type', U),
                ('format', c.c_int), ('data', c.c_long * 5)]

def announce():
    message = ClientMessage()
    message.type = 33
    message.display = display
    message.window = x11.XDefaultRootWindow(display)
    message.message_type = manager_atom
    message.format = 32
    message.data[1] = selection
    message.data[2] = window
    assert x11.XSendEvent(display, message.window, 0, 1 << 17, c.byref(message))
    x11.XSync(display, 0)

def publish(dark, animations, serial):
    entries = b''
    for name, value in ((b'Gtk/ApplicationPreferDarkTheme', int(dark)),
                        (b'Gtk/EnableAnimations', int(animations))):
        entry = struct.pack('<BBH', 0, 0, len(name)) + name
        entry += b'\0' * ((-len(entry)) % 4)
        entries += entry + struct.pack('<II', serial, value)
    data = struct.pack('<B3xII', 0, serial, 2) + entries
    buffer = c.create_string_buffer(data)
    x11.XChangeProperty(display, window, property_atom, property_atom, 8, 0,
                        buffer, len(data))
    x11.XSync(display, 0)

try:
    dark = 'dark' in sys.argv[2:]
    animations = 'reduce' not in sys.argv[2:]
    publish(dark, animations, 1)
    announce()
    (root / 'ready').write_text('ready', encoding='ascii')
    previous = ''
    serial = 1
    while True:
        command = root / 'command'
        value = command.read_text(encoding='ascii') if command.exists() else ''
        if value != previous and value in ('dark', 'light', 'reduce', 'restore'):
            serial += 1
            if value in ('dark', 'light'):
                dark = value == 'dark'
            else:
                animations = value == 'restore'
            publish(dark, animations, serial)
            (root / 'ack').write_text(value, encoding='ascii')
            previous = value
        time.sleep(.005)
finally:
    x11.XDestroyWindow(display, window)
    x11.XCloseDisplay(display)
