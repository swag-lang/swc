"""Independent XCB selection peer for the opt-in clipboard integration tests."""
import ctypes as c
import os
import select
import struct
import sys
import time
import zlib

xcb = c.CDLL('libxcb.so.1')
libc = c.CDLL('libc.so.6')
libc.free.argtypes = [c.c_void_p]

def bind(name, result, *args):
    fn = getattr(xcb, name)
    fn.restype = result
    fn.argtypes = args
    return fn

P, U, B = c.c_void_p, c.c_uint32, c.c_uint8
connect = bind('xcb_connect', P, c.c_char_p, P)
disconnect = bind('xcb_disconnect', None, P)
setup = bind('xcb_get_setup', P, P)
class Iterator(c.Structure):
    _fields_ = [('data', P), ('rem', c.c_int), ('index', c.c_int)]
roots = bind('xcb_setup_roots_iterator', Iterator, P)
generate = bind('xcb_generate_id', U, P)
create = bind('xcb_create_window_checked', U, P, B, U, U, c.c_int16, c.c_int16, c.c_uint16, c.c_uint16, c.c_uint16, c.c_uint16, U, U, P)
change = bind('xcb_change_property_checked', U, P, B, U, U, U, B, U, P)
attributes = bind('xcb_change_window_attributes_checked', U, P, U, U, P)
delete = bind('xcb_delete_property_checked', U, P, U, U)
intern = bind('xcb_intern_atom', U, P, B, c.c_uint16, c.c_char_p)
intern_reply = bind('xcb_intern_atom_reply', P, P, U, P)
set_owner = bind('xcb_set_selection_owner_checked', U, P, U, U, U)
get_owner = bind('xcb_get_selection_owner', U, P, U)
owner_reply = bind('xcb_get_selection_owner_reply', P, P, U, P)
convert = bind('xcb_convert_selection_checked', U, P, U, U, U, U, U)
get_property = bind('xcb_get_property', U, P, B, U, U, U, U, U)
property_reply = bind('xcb_get_property_reply', P, P, U, P)
property_value = bind('xcb_get_property_value', P, P)
property_length = bind('xcb_get_property_value_length', c.c_int, P)
check_request = bind('xcb_request_check', P, P, U)
poll_event = bind('xcb_poll_for_event', P, P)
flush = bind('xcb_flush', c.c_int, P)
get_fd = bind('xcb_get_file_descriptor', c.c_int, P)
send_event = bind('xcb_send_event_checked', U, P, B, U, U, P)
conn = connect(None, None)
assert conn
root = U.from_address(roots(setup(conn)).data).value
window = generate(conn)
mask = U(1 << 22)

def check(cookie):
    error = check_request(conn, cookie)
    if error:
        data = c.string_at(error, 32)
        libc.free(error)
        raise AssertionError(('X error', data[1]))

def atom(name):
    value = name.encode()
    reply = intern_reply(conn, intern(conn, 0, len(value), value), None)
    assert reply
    result = U.from_address(reply + 8).value
    libc.free(reply)
    return result

check(create(conn, 0, window, root, 0, 0, 1, 1, 0, 2, 0, 1 << 11, c.byref(mask)))
clipboard, targets, utf8, incr = map(atom, ['CLIPBOARD', 'TARGETS', 'UTF8_STRING', 'INCR'])
prop = atom('_SWAG_PEER_VALUE')


def event(deadline):
    while time.monotonic() < deadline:
        ptr = poll_event(conn)
        if ptr:
            value = c.string_at(ptr, 32)
            libc.free(ptr)
            return value
        select.select([get_fd(conn)], [], [], min(.05, max(0, deadline - time.monotonic())))
    raise TimeoutError('selection peer deadline')


def put(requestor, property, kind, fmt, data):
    buffer = c.create_string_buffer(data)
    check(change(conn, 0, requestor, property, kind, fmt, len(data) // (fmt // 8), buffer))


def read(target):
    check(convert(conn, window, clipboard, target, prop, 0))
    deadline = time.monotonic() + 6
    result = bytearray()
    incremental = False
    while True:
        packet = event(deadline)
        kind = packet[0] & 127
        if not incremental:
            if kind != 31:
                continue
            _, _, _, _, requestor, selection, received_target, property = struct.unpack_from('<BBHIIIII', packet)
            assert (requestor, selection, received_target, property) == (window, clipboard, target, prop)
        else:
            if kind != 28:
                continue
            _, _, _, requestor, property, _, state = struct.unpack_from('<BBHIIIB', packet)
            if requestor != window or property != prop or state != 0:
                continue
        reply = property_reply(conn, get_property(conn, 0, window, prop, 0, 0, 16 * 1024 * 1024), None)
        assert reply
        header = c.string_at(reply, 32)
        returned_type = struct.unpack_from('<I', header, 8)[0]
        remaining = struct.unpack_from('<I', header, 12)[0]
        data = c.string_at(property_value(reply), property_length(reply))
        libc.free(reply)
        assert remaining == 0
        if returned_type == incr and not incremental:
            incremental = True
        else:
            result.extend(data)
            if not incremental or not data:
                check(delete(conn, window, prop))
                return bytes(result)
        check(delete(conn, window, prop))


def offer(mode):
    custom = atom('Swag.Selection.Peer')
    plain = b'q' * 262144 if mode == 'offer-large' else 'étranger'.encode()
    if mode == 'offer-invalid-utf8':
        plain = b'\xff'
    custom_data = struct.pack('<IQ', 0, 7) + b'payload'
    def png_chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data))
    png = b'\x89PNG\r\n\x1a\n' + png_chunk(b'IHDR', struct.pack('>IIBBBBB', 2, 1, 8, 6, 0, 0, 0))
    png += png_chunk(b'IDAT', zlib.compress(b'\0\x10\x20\x30\xff\x40\x50\x60\xff')) + png_chunk(b'IEND', b'')
    png_target = atom('image/png')
    entries = {utf8: plain, custom: custom_data, png_target: png}
    entries[targets] = struct.pack('<4I', targets, utf8, custom, png_target)
    check(set_owner(conn, window, clipboard, 0))
    print('ready', flush=True)
    deadline = time.monotonic() + 12
    pending = {}
    while time.monotonic() < deadline:
        packet = event(deadline)
        kind = packet[0] & 127
        if kind == 29:
            return
        if kind == 30:
            _, _, _, timestamp, owner, requestor, selection, target, property = struct.unpack_from('<BBHIIIIII', packet)
            if mode == 'offer-silent':
                continue
            property = property or target
            data = entries.get(target)
            reply_property = property if data is not None else 0
            if data is not None:
                fmt = 32 if target == targets else 8
                if mode == 'offer-oversize' and target == utf8:
                    put(requestor, property, incr, 32, struct.pack('<I', 64 * 1024 * 1024 + 1))
                elif len(data) > 65536:
                    check(attributes(conn, requestor, 1 << 11, c.byref(mask)))
                    put(requestor, property, incr, 32, struct.pack('<I', len(data)))
                    pending[(requestor, property)] = [target, data, 0]
                else:
                    put(requestor, property, 4 if target == targets else target, fmt, data)
            reply = struct.pack('<BBHIIIII', 31, 0, 0, timestamp, requestor, selection, target, reply_property).ljust(32, b'\0')
            check(send_event(conn, 0, requestor, 0, c.create_string_buffer(reply)))
        elif kind == 28:
            _, _, _, requestor, property, _, state = struct.unpack_from('<BBHIIIB', packet)
            key = requestor, property
            if state == 1 and key in pending:
                target, data, offset = pending[key]
                chunk = data[offset:offset + 4096]
                put(requestor, property, target, 8, chunk)
                pending[key][2] += len(chunk)
                if not chunk:
                    del pending[key]

if __name__ == "__main__":
    try:
        mode = sys.argv[1]
        if mode.startswith('offer'):
            offer(mode)
        elif mode == 'read-text':
            assert read(utf8) == 'native-é'.encode()
            print('ok')
        elif mode == 'read-empty':
            assert read(utf8) == b''
            print('ok')
        elif mode == 'read-large':
            assert read(utf8) == b'x' * 262144
            print('ok')
        elif mode == 'read-png':
            assert read(atom('image/png')).startswith(b'\x89PNG\r\n\x1a\n')
            print('ok')
        else:
            raise AssertionError(mode)
    finally:
        disconnect(conn)
