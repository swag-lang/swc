"""Independent XDND source/target; run only on the test's isolated Xvfb server."""
import ctypes as c
import importlib.util
from pathlib import Path
import struct
import sys
import time

spec = importlib.util.spec_from_file_location('selection_peer', Path(__file__).with_name('clipboard.x11.peer.py'))
p = importlib.util.module_from_spec(spec)
spec.loader.exec_module(p)
p.clipboard = p.atom('XdndSelection')
enter, position, status, leave, drop, finished = map(p.atom, ['XdndEnter', 'XdndPosition', 'XdndStatus', 'XdndLeave', 'XdndDrop', 'XdndFinished'])
copy = p.atom('XdndActionCopy')
uri = p.atom('text/uri-list')

def message(destination, kind, data):
    packet = struct.pack('<BBHII5I', 33, 32, 0, destination, kind, *data)
    p.check(p.send_event(p.conn, 0, destination, 0, c.create_string_buffer(packet)))

def owner():
    reply = p.owner_reply(p.conn, p.get_owner(p.conn, p.clipboard), None)
    assert reply
    result = p.U.from_address(reply + 8).value
    p.libc.free(reply)
    return result

def serve(packet, entries):
    _, _, _, timestamp, window, requestor, selection, target, prop = struct.unpack_from('<BBHIIIIII', packet)
    prop = prop or target
    data = entries.get(target)
    if data is not None:
        p.put(requestor, prop, 4 if target == p.targets else target, 32 if target == p.targets else 8, data)
    reply = struct.pack('<BBHIIIII', 31, 0, 0, timestamp, requestor, selection, target, prop if data is not None else 0).ljust(32, b'\0')
    p.check(p.send_event(p.conn, 0, requestor, 0, c.create_string_buffer(reply)))

def client_center(window):
    geometry = p.bind('xcb_get_geometry', p.U, p.P, p.U)
    geometry_reply = p.bind('xcb_get_geometry_reply', p.P, p.P, p.U, p.P)
    attributes = p.bind('xcb_get_window_attributes', p.U, p.P, p.U)
    attributes_reply = p.bind('xcb_get_window_attributes_reply', p.P, p.P, p.U, p.P)
    translate = p.bind('xcb_translate_coordinates', p.U, p.P, p.U, p.U, c.c_int16, c.c_int16)
    translate_reply = p.bind('xcb_translate_coordinates_reply', p.P, p.P, p.U, p.P)
    deadline = time.monotonic() + 3
    while True:
        reply = attributes_reply(p.conn, attributes(p.conn, window), None)
        assert reply
        mapped = c.c_uint8.from_address(reply + 26).value == 2
        p.libc.free(reply)
        if mapped:
            break
        assert time.monotonic() < deadline, 'window was not mapped by the window manager'
        time.sleep(.01)
    reply = geometry_reply(p.conn, geometry(p.conn, window), None)
    assert reply
    width, height = struct.unpack_from('<HH', c.string_at(reply, 32), 16)
    p.libc.free(reply)
    reply = translate_reply(p.conn, translate(p.conn, window, p.root, width // 2, height // 2), None)
    assert reply
    x, y = struct.unpack_from('<hh', c.string_at(reply, 32), 12)
    p.libc.free(reply)
    return x, y


def source(destination):
    entries = {p.utf8: 'external-é'.encode(), uri: b'file:///tmp/space%20and%20%C3%A9.txt\r\n'}
    entries[p.targets] = struct.pack('<3I', p.targets, p.utf8, uri)
    p.check(p.set_owner(p.conn, p.window, p.clipboard, 0))
    p.put(p.window, p.atom('XdndActionList'), 4, 32, struct.pack('<I', copy))
    message(destination, enter, [p.window, 5 << 24, p.utf8, uri, 0])
    x, y = client_center(destination)
    message(destination, position, [p.window, 0, ((x & 65535) << 16) | (y & 65535), 0, copy])
    deadline = time.monotonic() + 8
    while True:
        packet = p.event(deadline)
        if packet[0] & 127 == 30:
            serve(packet, entries)
            continue
        if packet[0] & 127 != 33:
            continue
        _, _, _, window, kind, *data = struct.unpack('<BBHII5I', packet)
        if kind == status:
            assert window == p.window and data[0] == destination and data[1] & 1 and data[4] == copy, data
            message(destination, drop, [p.window, 0, 0, 0, 0])
        elif kind == finished:
            assert window == p.window and data[0] == destination and data[1] & 1 and data[2] == copy, data
            print('ok', flush=True)
            return


def target(reject=False, save_path=None):
    window = p.generate(p.conn)
    p.check(p.create(p.conn, 0, window, p.root, 320, 40, 200, 160, 0, 1, 0, 1 << 11, c.byref(p.mask)))
    map_window = p.bind('xcb_map_window_checked', p.U, p.P, p.U)
    p.put(window, p.atom('XdndAware'), 4, 32, struct.pack('<I', 5))
    p.check(map_window(p.conn, window))
    p.window = window
    x11, xtst = c.CDLL('libX11.so.6'), c.CDLL('libXtst.so.6')
    x11.XOpenDisplay.restype = p.P
    x11.XOpenDisplay.argtypes = [c.c_char_p]
    x11.XSync.argtypes = [p.P, c.c_int]
    x11.XCloseDisplay.argtypes = [p.P]
    xtst.XTestFakeMotionEvent.argtypes = [p.P, c.c_int, c.c_int, c.c_int, c.c_ulong]
    xtst.XTestFakeButtonEvent.argtypes = [p.P, c.c_uint, c.c_int, c.c_ulong]
    display = x11.XOpenDisplay(None)
    assert display
    try:
        x, y = client_center(window)
        assert xtst.XTestFakeMotionEvent(display, -1, x, y, 0)
        assert xtst.XTestFakeButtonEvent(display, 1, 1, 0)
        x11.XSync(display, 0)
        print('ready', flush=True)
        deadline = time.monotonic() + 8
        source_id = 0
        while True:
            packet = p.event(deadline)
            if packet[0] & 127 != 33:
                continue
            _, _, _, recipient, kind, *data = struct.unpack('<BBHII5I', packet)
            assert recipient == window
            if kind == enter:
                source_id = data[0]
                assert data[1] >> 24 == 5 and owner() == source_id
            elif kind == position:
                assert data[0] == source_id
                message(source_id, status, [window, 2 if reject else 3, 0, 0, 0 if reject else copy])
                assert xtst.XTestFakeButtonEvent(display, 1, 0, 0)
                x11.XSync(display, 0)
            elif kind == drop:
                assert data[0] == source_id
                assert not reject
                assert p.read(p.utf8) == 'source-é'.encode()
                if save_path:
                    xds = p.atom('XdndDirectSave0')
                    p.put(source_id, xds, p.atom('text/plain'), 8, Path(save_path).as_uri().encode())
                    assert p.read(xds) == b'S'
                    assert Path(save_path).read_bytes() == b'deferred-content'
                else:
                    metadata = p.read(p.atom('application/x-swag-drag-contents'))
                    assert struct.unpack_from('<I', metadata)[0] == 1
                    assert p.read(p.atom('application/x-swag-drag-content-0')) == b'deferred-content'
                message(source_id, finished, [window, 1, copy, 0, 0])
                print('ok', flush=True)
                return
            elif kind == leave:
                if reject:
                    print('ok', flush=True)
                    return
                raise AssertionError('source cancelled instead of dropping')
    finally:
        xtst.XTestFakeButtonEvent(display, 1, 0, 0)
        x11.XSync(display, 0)
        x11.XCloseDisplay(display)

try:
    if sys.argv[1] == 'source':
        source(int(sys.argv[2]))
    elif sys.argv[1] in ('target', 'reject', 'save'):
        target(reject=sys.argv[1] == 'reject', save_path=sys.argv[2] if sys.argv[1] == 'save' else None)
    else:
        raise AssertionError(sys.argv[1])
finally:
    p.disconnect(p.conn)
