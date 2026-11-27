"""Portal chooser peer for an explicit private D-Bus address; never uses the desktop bus.

Run with /usr/bin/python3 and the address printed by the test's private dbus-daemon.
Both org.freedesktop.portal.Desktop and org.swag.TestPortal name this connection.
The control interface lives at /org/freedesktop/portal/desktop alongside OpenURI.
Stats returns UTF-8 file contents (replacement for invalid bytes), or <directory>.
"""

import argparse
import os
import re
import signal
import stat

import gi

gi.require_version('Gio', '2.0')
from gi.repository import Gio, GLib


OBJECT = '/org/freedesktop/portal/desktop'
PORTAL = 'org.freedesktop.portal.OpenURI'
CONTROL = 'org.swag.TestPortal'
XML = '''<node>
  <interface name="org.freedesktop.portal.OpenURI">
    <property name="version" type="u" access="read"/>
    <method name="OpenFile">
      <arg name="parent_window" type="s" direction="in"/>
      <arg name="fd" type="h" direction="in"/>
      <arg name="options" type="a{sv}" direction="in"/>
      <arg name="handle" type="o" direction="out"/>
    </method>
  </interface>
  <interface name="org.swag.TestPortal">
    <method name="Reset">
      <arg name="version" type="u" direction="in"/>
      <arg name="mode" type="s" direction="in"/>
    </method>
    <method name="Stats">
      <arg name="count" type="u" direction="out"/>
      <arg name="ask" type="b" direction="out"/>
      <arg name="senderAlive" type="b" direction="out"/>
      <arg name="contents" type="s" direction="out"/>
    </method>
    <method name="Complete"/>
  </interface>
</node>'''


class Portal:
    def __init__(self, connection, version, mode):
        self.connection = connection
        self.reset(version, mode)

    def reset(self, version, mode):
        if mode not in ('accept', 'reject', 'timeout'):
            raise ValueError('unknown portal test mode')
        self.version, self.mode = version, mode
        self.count, self.ask = 0, False
        self.sender, self.contents, self.request = '', '', ''

    def property(self, connection, sender, path, interface, name):
        if interface == PORTAL and name == 'version':
            return GLib.Variant('u', self.version)
        return None

    def sender_alive(self):
        if not self.sender:
            return False
        result = self.connection.call_sync(
            'org.freedesktop.DBus', '/org/freedesktop/DBus',
            'org.freedesktop.DBus', 'NameHasOwner',
            GLib.Variant('(s)', (self.sender,)), GLib.VariantType.new('(b)'),
            Gio.DBusCallFlags.NONE, 500, None)
        return result.unpack()[0]

    def method(self, connection, sender, path, interface, name, parameters, invocation):
        try:
            if interface == CONTROL:
                if name == 'Reset':
                    self.reset(*parameters.unpack())
                    invocation.return_value(GLib.Variant('()', ()))
                elif name == 'Stats':
                    invocation.return_value(GLib.Variant(
                        '(ubbs)', (self.count, self.ask, self.sender_alive(), self.contents)))
                elif name == 'Complete':
                    if self.request:
                        connection.emit_signal(
                            self.sender, self.request, 'org.freedesktop.portal.Request',
                            'Response', GLib.Variant('(ua{sv})', (0, {})))
                        self.request = ''
                    invocation.return_value(GLib.Variant('()', ()))
                else:
                    raise ValueError('unknown control method')
                return

            if interface != PORTAL or name != 'OpenFile':
                raise ValueError('unknown portal method')
            self.count += 1
            self.sender = sender
            _, handle, options = parameters.unpack()
            self.ask = options.get('ask') is True
            self.contents = ''
            self.request = ''
            if not self.ask:
                raise ValueError('OpenFile must request ask=true')
            descriptors = invocation.get_message().get_unix_fd_list()
            if descriptors is None:
                raise ValueError('OpenFile did not carry a Unix descriptor list')
            descriptor = descriptors.get(handle)
            try:
                kind = os.fstat(descriptor).st_mode
                if stat.S_ISDIR(kind):
                    self.contents = '<directory>'
                elif stat.S_ISREG(kind):
                    content = os.pread(descriptor, 65537, 0)
                    if len(content) > 65536:
                        raise ValueError('chooser fixture exceeds 64 KiB')
                    self.contents = content.decode('utf-8', errors='replace')
                else:
                    raise ValueError('chooser descriptor is neither a regular file nor a directory')
            finally:
                os.close(descriptor)

            if self.mode == 'reject':
                invocation.return_dbus_error('org.freedesktop.portal.Error.NotAllowed',
                                             'Rejected by the private chooser test peer')
            elif self.mode == 'timeout':
                # Keep the event loop responsive to Stats while the client's 2-second call expires.
                def delayed_reply():
                    invocation.return_dbus_error('org.freedesktop.portal.Error.Failed',
                                                 'Delayed private chooser test response')
                    return GLib.SOURCE_REMOVE
                GLib.timeout_add(3500, delayed_reply)
            else:
                token = options.get('handle_token', 'swag_test')
                if not isinstance(token, str) or not re.fullmatch(r'[A-Za-z0-9_]+', token):
                    raise ValueError('invalid portal handle token')
                caller = sender.removeprefix(':').replace('.', '_')
                self.request = f'{OBJECT}/request/{caller}/{token}'
                invocation.return_value(GLib.Variant('(o)', (self.request,)))
        except (GLib.Error, OSError, ValueError) as error:
            invocation.return_dbus_error('org.swag.TestPortal.Error', str(error))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('address', help='explicit address of a test-owned private message bus')
    parser.add_argument('--version', type=int, default=3)
    parser.add_argument('--mode', choices=('accept', 'reject', 'timeout'), default='accept')
    arguments = parser.parse_args()
    if not 0 <= arguments.version <= 0xFFFFFFFF:
        parser.error('version must fit a D-Bus unsigned 32-bit integer')
    connection = Gio.DBusConnection.new_for_address_sync(
        arguments.address,
        Gio.DBusConnectionFlags.AUTHENTICATION_CLIENT | Gio.DBusConnectionFlags.MESSAGE_BUS_CONNECTION,
        None, None)
    connection.set_exit_on_close(False)
    loop = GLib.MainLoop()
    connection.connect('closed', lambda *unused: loop.quit())
    portal = Portal(connection, arguments.version, arguments.mode)
    node = Gio.DBusNodeInfo.new_for_xml(XML)
    registrations = [connection.register_object(OBJECT, interface, portal.method, portal.property, None)
                     for interface in node.interfaces]
    for name in ('org.freedesktop.portal.Desktop', CONTROL):
        result = connection.call_sync(
            'org.freedesktop.DBus', '/org/freedesktop/DBus', 'org.freedesktop.DBus', 'RequestName',
            GLib.Variant('(su)', (name, 4)), GLib.VariantType.new('(u)'),
            Gio.DBusCallFlags.NONE, 1000, None)
        if result.unpack()[0] not in (1, 4):
            raise RuntimeError(f'private bus name already owned: {name}')

    def stop():
        loop.quit()
        return GLib.SOURCE_REMOVE

    GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, signal.SIGTERM, stop)
    GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, signal.SIGINT, stop)
    print('READY', flush=True)
    try:
        loop.run()
    finally:
        for registration in registrations:
            connection.unregister_object(registration)
        if not connection.is_closed():
            connection.close_sync(None)


if __name__ == '__main__':
    main()
