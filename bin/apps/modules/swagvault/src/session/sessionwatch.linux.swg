#global if #os == Swag.TargetOs.Linux

using Core

namespace SessionWatch
{
    const LoginService = "org.freedesktop.login1"
    const ManagerPath = "/org/freedesktop/login1"
    const ManagerInterface = "org.freedesktop.login1.Manager"
    const SessionInterface = "org.freedesktop.login1.Session"

    struct Snapshot
    {
        locked: bool
        suspending: bool
        idleMilliseconds: u64
    }

    // Queried only by the GUI thread. Holding the delay inhibitor gives that thread time to
    // commit and unmount before logind suspends; release it only after handling the notification.
    #[Swag.NoCopy]
    struct Monitor
    {
        systemd: *void?
        bus: *void?
        sessionPath: String
        inhibitor: s32 = -1
        wasLocked: bool
        wasSuspending: bool
        late unref: Linux.sd_bus_unref_fn
        late property: Linux.sd_bus_get_property_trivial_fn
        late call: Linux.sd_bus_call_method_fn
        late read: Linux.sd_bus_message_read_fn
        late messageUnref: Linux.sd_bus_message_unref_fn
        xlib: *void?
        xss: *void?
        display: *void?
        late closeDisplay: Linux.XCloseDisplay_fn
        late rootWindow: Linux.XDefaultRootWindow_fn
        late queryIdle: Linux.XScreenSaverQueryInfo_fn
    }

    func(T) symbol(library: *void, name: string)->T fail
    {
        let address = Linux.dlsym(library, name.buffer)
        if not address do fail volumeError(.DriverUnavailable)
        return cast(T, address)
    }

    impl Monitor
    {
        mtd openBus() fail
        {
            .systemd = Linux.dlopen("libsystemd.so.0".buffer, Linux.RTLD_NOW | Linux.RTLD_LOCAL)
            if not .systemd do fail volumeError(.DriverUnavailable)
            .unref = try symbol'Linux.sd_bus_unref_fn(.systemd, "sd_bus_unref")
            .property = try symbol'Linux.sd_bus_get_property_trivial_fn(.systemd, "sd_bus_get_property_trivial")
            .call = try symbol'Linux.sd_bus_call_method_fn(.systemd, "sd_bus_call_method")
            .read = try symbol'Linux.sd_bus_message_read_fn(.systemd, "sd_bus_message_read")
            .messageUnref = try symbol'Linux.sd_bus_message_unref_fn(.systemd, "sd_bus_message_unref")
            let open = try symbol'Linux.sd_bus_open_system_fn(.systemd, "sd_bus_open_system")
            let timeout = try symbol'Linux.sd_bus_set_method_call_timeout_fn(.systemd, "sd_bus_set_method_call_timeout")
            let session = try symbol'Linux.sd_pid_get_session_fn(.systemd, "sd_pid_get_session")
            let encode = try symbol'Linux.sd_bus_path_encode_fn(.systemd, "sd_bus_path_encode")
            if open(&.bus) < 0 or not .bus do fail volumeError(.DriverUnavailable)
            if timeout(.bus, 100_000) < 0 do fail volumeError(.DriverUnavailable)
            var sessionId: [*]u8?
            defer if sessionId do Linux.free(sessionId)
            var id = Env.variable("XDG_SESSION_ID")
            if session(0, &sessionId) >= 0 and sessionId do
                id = cast(string, cast(cstring, sessionId))
            if not id.isEmpty()
            {
                var path: [*]u8?
                defer if path do Linux.free(path)
                if encode("/org/freedesktop/login1/session".buffer, unwrap id.buffer, &path) >= 0 and path do
                    .sessionPath = cast(string, cast(cstring, path))
            }
            .acquireInhibitor()
        }

        mtd openDisplay() fail
        {
            // X11 has a precise last-input clock. A private connection keeps this observer
            // independent of the GUI renderer's XCB connection and event ownership.
            .xlib = Linux.dlopen("libX11.so.6".buffer, Linux.RTLD_NOW | Linux.RTLD_LOCAL)
            if not .xlib do fail volumeError(.DriverUnavailable)
            .closeDisplay = try symbol'Linux.XCloseDisplay_fn(.xlib, "XCloseDisplay")
            .rootWindow = try symbol'Linux.XDefaultRootWindow_fn(.xlib, "XDefaultRootWindow")
            let open = try symbol'Linux.XOpenDisplay_fn(.xlib, "XOpenDisplay")
            .xss = Linux.dlopen("libXss.so.1".buffer, Linux.RTLD_NOW | Linux.RTLD_LOCAL)
            if not .xss do fail volumeError(.DriverUnavailable)
            .queryIdle = try symbol'Linux.XScreenSaverQueryInfo_fn(.xss, "XScreenSaverQueryInfo")
            .display = open(null)
            if not .display do fail volumeError(.DriverUnavailable)
        }

        mtd start()
        {
            .stop()
            // Optional desktop services are independent: a headless or non-systemd session
            // can still supply X11 idle time, and a Wayland session can supply logind hints.
            catch .openBus() { .closeBus() }
            catch .openDisplay() { .closeDisplayConnection() }
        }

        mtd acquireInhibitor()
        {
            if not .bus or .inhibitor >= 0 do return
            var reply: *void?
            defer if reply do discard .messageUnref(reply)
            if .call(.bus, LoginService.buffer, ManagerPath.buffer, ManagerInterface.buffer, "Inhibit".buffer,
                     null, &reply, "ssss".buffer, "sleep".buffer, "Swag Vault".buffer,
                     "Close encrypted volumes before suspend".buffer, "delay".buffer) < 0 or not reply do return
            var descriptor: s32 = -1
            if .read(reply, "h".buffer, &descriptor) >= 0 and descriptor >= 0 do
                .inhibitor = Linux.fcntl(descriptor, Linux.F_DUPFD_CLOEXEC, 3's32)
        }

        mtd finishSuspend()
        {
            if .inhibitor < 0 do return
            discard Linux.close(.inhibitor)
            .inhibitor = -1
        }

        mtd readProperty(path: string, interfaceName: string, name: string, kind: u8, output: *void)->bool
        {
            if not .bus do return false
            return .property(.bus, LoginService.buffer, path.buffer, interfaceName.buffer, name.buffer, null, kind, output) >= 0
        }

        mtd poll()->Snapshot
        {
            var result: #returntype
            if .bus
            {
                var preparing: s32
                if .readProperty(ManagerPath, ManagerInterface, "PreparingForSleep", 'b', &preparing)
                {
                    result.suspending = preparing != 0 and not .wasSuspending
                    .wasSuspending = preparing != 0
                    if not .wasSuspending do .acquireInhibitor()
                }
                if not .sessionPath.isEmpty()
                {
                    var locked, idle: s32
                    if .readProperty(.sessionPath, SessionInterface, "LockedHint", 'b', &locked)
                    {
                        result.locked = locked != 0 and not .wasLocked
                        .wasLocked = locked != 0
                    }
                    var since: u64
                    if .readProperty(.sessionPath, SessionInterface, "IdleHint", 'b', &idle) and idle != 0 and
                       .readProperty(.sessionPath, SessionInterface, "IdleSinceHintMonotonic", 't', &since)
                    {
                        let now = Time.monotonicMilliseconds()
                        if since / 1000 <= now do result.idleMilliseconds = now - since / 1000
                    }
                }
            }
            if .display
            {
                var info: Linux.XScreenSaverInfo
                if .queryIdle(.display, .rootWindow(.display), &info) != 0 do
                    result.idleMilliseconds = info.idle
            }
            return result
        }

        mtd closeBus()
        {
            .finishSuspend()
            if .bus
            {
                discard .unref(.bus)
                .bus = null
            }
            if .systemd
            {
                discard Linux.dlclose(.systemd)
                .systemd = null
            }
            .sessionPath.clear()
            .wasLocked = false
            .wasSuspending = false
        }

        mtd closeDisplayConnection()
        {
            if .display
            {
                discard .closeDisplay(.display)
                .display = null
            }
            if .xss
            {
                discard Linux.dlclose(.xss)
                .xss = null
            }
            if .xlib
            {
                discard Linux.dlclose(.xlib)
                .xlib = null
            }
        }

        mtd stop() { .closeBus(); .closeDisplayConnection() }
        mtd opDrop() { .stop() }
    }
}
