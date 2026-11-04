"""Private login1 protocol peer for session.monitor.integration.test.swg.

Pass an address from a dedicated dbus-daemon --session instance. The Swag test
uses the same address as DBUS_SYSTEM_BUS_ADDRESS and XDG_SESSION_ID=vault-test,
with DISPLAY unset. This peer never requests a real session lock or suspension.
Requires Python 3 with PyGObject (Gio/GLib) and dbus-daemon.
"""
from gi.repository import Gio, GLib
import os,sys,time,signal
address=sys.argv[1]
flags=Gio.DBusConnectionFlags.AUTHENTICATION_CLIENT|Gio.DBusConnectionFlags.MESSAGE_BUS_CONNECTION
connection=Gio.DBusConnection.new_for_address_sync(address,flags,None,None)
connection.call_sync('org.freedesktop.DBus','/org/freedesktop/DBus','org.freedesktop.DBus','RequestName',GLib.Variant('(su)',('org.freedesktop.login1',0)),GLib.VariantType.new('(u)'),Gio.DBusCallFlags.NONE,1000,None)
xml='''<node>
<interface name="org.freedesktop.login1.Manager">
<method name="Inhibit"><arg type="s" direction="in"/><arg type="s" direction="in"/><arg type="s" direction="in"/><arg type="s" direction="in"/><arg type="h" direction="out"/></method>
<method name="Advance"><arg type="u" direction="in"/></method>
<method name="InhibitorClosed"><arg type="b" direction="out"/></method>
<property name="PreparingForSleep" type="b" access="read"/>
</interface>
<interface name="org.freedesktop.login1.Session">
<property name="LockedHint" type="b" access="read"/>
<property name="IdleHint" type="b" access="read"/>
<property name="IdleSinceHintMonotonic" type="t" access="read"/>
</interface></node>'''
info=Gio.DBusNodeInfo.new_for_xml(xml)
state=0;writers=[]
def method(conn,sender,path,interface,name,parameters,invocation):
 global state
 if name=='Advance':
  state=parameters.unpack()[0]
  if state==3:
   for value in (True,False):
    connection.emit_signal(None,'/org/freedesktop/login1/session/vault_2dtest','org.freedesktop.DBus.Properties','PropertiesChanged',GLib.Variant('(sa{sv}as)',('org.freedesktop.login1.Session',{'LockedHint':GLib.Variant('b',value)},[])))
  invocation.return_value(None)
 elif name=='Inhibit':
  assert parameters.unpack()[0]=='sleep' and parameters.unpack()[3]=='delay'
  read,write=os.pipe2(os.O_CLOEXEC|os.O_NONBLOCK)
  fds=Gio.UnixFDList.new();index=fds.append(read);os.close(read);writers.append(write)
  invocation.return_value_with_unix_fd_list(GLib.Variant('(h)',(index,)),fds)
 elif name=='InhibitorClosed':
  closed=True
  for write in writers:
   try:os.write(write,b'x');closed=False
   except BrokenPipeError:pass
  invocation.return_value(GLib.Variant('(b)',(closed,)))
def prop(conn,sender,path,interface,name):
 if name=='PreparingForSleep':return GLib.Variant('b',state==2)
 if name=='LockedHint':return GLib.Variant('b',state==1)
 if name=='IdleHint':return GLib.Variant('b',True)
 if name=='IdleSinceHintMonotonic':return GLib.Variant('t',int(time.monotonic()*1000000)-90000000)
connection.register_object('/org/freedesktop/login1',info.interfaces[0],method,prop,None)
connection.register_object('/org/freedesktop/login1/session/vault_2dtest',info.interfaces[1],method,prop,None)
print('ready',flush=True)
GLib.MainLoop().run()
