#global if #os == Swag.TargetOs.Linux
#global namespace Env

#[Swag.NoCopy]
private struct DesktopChooser
{
    library:          NativeLibrary
    bus:              *void?
    late openUser:    Linux.sd_bus_open_user_fn
    late freeBus:     Linux.sd_bus_unref_fn
    late isOpen:      Linux.sd_bus_is_open_fn
    late setTimeout:  Linux.sd_bus_set_method_call_timeout_fn
    late property:    Linux.sd_bus_get_property_trivial_fn
    late call:        Linux.sd_bus_call_method_fn
    late read:        Linux.sd_bus_message_read_fn
    late freeMessage: Linux.sd_bus_message_unref_fn
    late process:     Linux.sd_bus_process_fn
}

private impl DesktopChooser
{
    mtd close()
    {
        if .bus do
            .bus = .freeBus(.bus)
        .library.close()
    }

    mtd opDrop() { .close() }

    mtd(T) symbol(name: string)->T fail
    {
        let address = .library.symbol(name)
        if not address do
            fail Swag.SystemError{"a required desktop D-Bus symbol is unavailable"}
        return cast(T, address)
    }

    func load()->DesktopChooser fail
    {
        var result: #returntype
        result.library     = try NativeLibrary.load("libsystemd.so.0")
        result.openUser    = try result.symbol'Linux.sd_bus_open_user_fn("sd_bus_open_user")
        result.freeBus     = try result.symbol'Linux.sd_bus_unref_fn("sd_bus_unref")
        result.isOpen      = try result.symbol'Linux.sd_bus_is_open_fn("sd_bus_is_open")
        result.setTimeout  = try result.symbol'Linux.sd_bus_set_method_call_timeout_fn("sd_bus_set_method_call_timeout")
        result.property    = try result.symbol'Linux.sd_bus_get_property_trivial_fn("sd_bus_get_property_trivial")
        result.call        = try result.symbol'Linux.sd_bus_call_method_fn("sd_bus_call_method")
        result.read        = try result.symbol'Linux.sd_bus_message_read_fn("sd_bus_message_read")
        result.freeMessage = try result.symbol'Linux.sd_bus_message_unref_fn("sd_bus_message_unref")
        result.process     = try result.symbol'Linux.sd_bus_process_fn("sd_bus_process")
        let connected = result.openUser(&result.bus)
        if connected < 0 do
            try Errors.failLinuxError(-connected)
        let timeout = result.setTimeout(unwrap result.bus, 2_000_000)
        if timeout < 0 do
            try Errors.failLinuxError(-timeout)
        return result
    }

    mtd request(descriptor: s32)->bool
    {
        let bus = unwrap .bus

        // Consume earlier responses with a bound against unsolicited traffic.
        // No callbacks enter application code from this connection.
        for 64
        {
            if .process(bus, null) <= 0 do
                break
        }

        const Destination = "org.freedesktop.portal.Desktop"
        const ObjectPath  = "/org/freedesktop/portal/desktop"
        const Interface   = "org.freedesktop.portal.OpenURI"
        var version: u32
        if .property(bus, Destination.buffer, ObjectPath.buffer, Interface.buffer, "version".buffer, null, 'u', &version) < 0 or
           version < 3 do
            return false

        // Version 3 introduced ask=true. Older portals could silently use the default
        // application, which is not the Open With operation requested by this API.
        let parent = String.from("")
        var reply: *void?
        defer discard .freeMessage(reply)
        let accepted = .call(bus,
                             Destination.buffer,
                             ObjectPath.buffer,
                             Interface.buffer,
                             "OpenFile".buffer,
                             null,
                             &reply,
                             "sha{sv}".buffer,
                             parent.storage(),
                             descriptor,
                             1'u32,
                             "ask".buffer,
                             "b".buffer,
                             1's32)
        if accepted < 0 or not reply do
            return false
        var requestPath: const [*]u8?
        return .read(reply, "o".buffer, &requestPath) > 0 and requestPath != null
    }
}

private var g_DesktopChooserMutex: Swag.Mutex
private var g_DesktopChooser:      DesktopChooser

// Asks the desktop portal to show an application chooser for an existing file or directory.
//
// Uses optional libsystemd and the session OpenURI portal, version 3 or newer, with `ask=true`.
// The opened descriptor identifies the target; spaces, Unicode and shell characters need no
// command quoting. Missing services, invalid paths, non-file objects, sandbox refusal and
// unacknowledged requests return `false`. Each D-Bus exchange has a two-second timeout.
// Does not request writable document-portal access for sandboxed target applications.
// Returns after acknowledgement, before the user chooses or cancels; it does not report the
// eventual application launch. Core retains its bus connection so pending dialogs survive
// this call. Unloading Core or exiting the process cancels outstanding portal requests.
#[Swag.Discardable]
public func openFileWith(path: string)->bool
{
    if isSandboxed() or not Utf8.isValid(cast(const [..]u8, path)) do
        return false
    let native = catch Path.nativePath(path) { return false }
    var descriptor: s32 = -1
    for
    {
        descriptor = Linux.openat(Linux.AT_FDCWD, native.storage(), Linux.O_RDONLY | Linux.O_NONBLOCK | Linux.O_NOCTTY | Linux.O_CLOEXEC)
        if descriptor >= 0 do
            break
        if Linux.errno() != Linux.EINTR do
            return false
    }

    defer discard Linux.close(descriptor)
    var info: Linux.stat
    for
    {
        if Linux.fstat(descriptor, &info) == 0 do
            break
        if Linux.errno() != Linux.EINTR do
            return false
    }

    let kind = info.st_mode & Linux.S_IFMT
    if kind != Linux.S_IFREG and kind != Linux.S_IFDIR do
        return false

    Sync.scopedLock(&g_DesktopChooserMutex)
    if g_DesktopChooser.bus and g_DesktopChooser.isOpen(unwrap g_DesktopChooser.bus) <= 0 do
        g_DesktopChooser.close()
    if not g_DesktopChooser.bus do
        g_DesktopChooser = catch DesktopChooser.load() { return false }
    return g_DesktopChooser.request(descriptor)
}
