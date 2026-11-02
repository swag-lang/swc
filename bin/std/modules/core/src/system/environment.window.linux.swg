#global if #os == Swag.TargetOs.Linux
#global namespace Env

private func validateX11Size(width, height: s32) fail
{
    if width <= 0 or height <= 0 or width > 65535 or height > 65535 do
        fail Errors.BadParameterError{"X11 client dimensions must be between 1 and 65535 pixels"}
}

private func releaseX11Window(window: *LinuxDesktop.WindowState)
{
    let context = unwrap window.context
    var link    = &context.windows
    while link[]
    {
        let current = unwrap link[]
        if current == window
        {
            link[] = window.next
            break
        }

        link = &current.next
    }

    if window.owner do
        window.owner.nativeHandle = null
    context.stopRequested = true
    Linux.free(window)
}

internal func createWindowNative(result: *Window, options: WindowOptions) fail
{
    try validateX11Size(options.width, options.height)
    if not Utf8.isValid(cast(const [..]u8, options.identifier)) or not Utf8.isValid(cast(const [..]u8, options.title)) do
        fail Errors.BadParameterError{"window identifier and title must contain valid UTF-8"}
    for value in options.identifier where value == 0 do
        fail Errors.BadParameterError{"window identifier contains a zero byte"}
    for value in options.title where value == 0 do
        fail Errors.BadParameterError{"window title contains a zero byte"}
    if options.title.count > 65535 or options.identifier.count > 65535 do
        fail Errors.BadParameterError{"X11 window title or identifier is too long"}
    let context = try LinuxDesktop.ensure()
    try LinuxDesktop.requireUiThread(context)
    let connection = unwrap context.connection
    let allocation = Linux.calloc(1, #sizeof(LinuxDesktop.WindowState))
    if not allocation do
        try Errors.failLinuxError(Linux.ENOMEM)
    let window = cast(*LinuxDesktop.WindowState, unwrap allocation)
    defer #fail Linux.free(window)
    window.context       = context
    window.resizable     = (options.flags & .Resizable) != .None
    window.id            = context.xcb_generate_id(connection)
    window.drawable      = {context.connection, window.id, context.screen.root_visual, context.screenIndex}
    window.protocolsAtom = try LinuxDesktop.atom(context, "WM_PROTOCOLS")
    window.deleteAtom    = try LinuxDesktop.atom(context, "WM_DELETE_WINDOW")
    let values: [2]u32 = [context.screen.black_pixel, (1 << 15) | (1 << 17)]
    try LinuxDesktop.check(context,
                           context.xcb_create_window_checked(connection,
                                                             context.screen.root_depth,
                                                             window.id,
                                                             context.screen.root,
                                                             0,
                                                             0,
                                                             cast(u16, options.width),
                                                             cast(u16, options.height),
                                                             0,
                                                             1,
                                                             context.screen.root_visual,
                                                             (1 << 1) | (1 << 11),
                                                             values))
    defer #fail
    {
        let error = context.xcb_request_check(connection, context.xcb_destroy_window_checked(connection, window.id))
        if error do
            Linux.free(error)
    }

    try LinuxDesktop.check(context, context.xcb_change_property_checked(connection, 0, window.id, window.protocolsAtom, 4, 32, 1, &window.deleteAtom))
    let utf8 = try LinuxDesktop.atom(context, "UTF8_STRING")
    let name = try LinuxDesktop.atom(context, "_NET_WM_NAME")
    try LinuxDesktop.check(context, context.xcb_change_property_checked(connection, 0, window.id, name, utf8, 8, cast(u32, options.title.count), options.title.buffer))
    try LinuxDesktop.check(context, context.xcb_change_property_checked(connection, 0, window.id, 39, 31, 8, cast(u32, options.title.count), options.title.buffer))
    var className = String.from(options.identifier)
    className.append("\0")
    className.append(options.identifier)
    className.append("\0")
    try LinuxDesktop.check(context, context.xcb_change_property_checked(connection, 0, window.id, 67, 31, 8, cast(u32, className.count), className.buffer))
    if not (options.flags & .Resizable)
    {
        var hints: [18]u32
        hints[0] = (1 << 4) | (1 << 5)
        hints[5] = cast(u32, options.width)
        hints[7] = hints[5]
        hints[6] = cast(u32, options.height)
        hints[8] = hints[6]
        try LinuxDesktop.check(context, context.xcb_change_property_checked(connection, 0, window.id, 40, 41, 32, 18, hints))
    }

    let motif = try LinuxDesktop.atom(context, "_MOTIF_WM_HINTS")
    var capabilities: u32 = 4 | 32
    if options.flags & .Resizable do
        capabilities |= 2
    if options.flags & .Minimizable do
        capabilities |= 8
    if options.flags & .Maximizable do
        capabilities |= 16
    let motifHints: [5]u32 = [1, capabilities, 0, 0, 0]
    try LinuxDesktop.check(context, context.xcb_change_property_checked(connection, 0, window.id, motif, motif, 32, 5, motifHints))
    if not context.windows do
        context.stopRequested = false
    window.owner        = result
    window.next         = context.windows
    context.windows     = window
    result.nativeHandle = window
}

impl Window
{
    private mtd x11State()->*LinuxDesktop.WindowState fail
    {
        if not .nativeHandle do
            fail Errors.BadParameterError{"window is closed"}
        let window = cast #unconst (*LinuxDesktop.WindowState, .nativeHandle)
        try LinuxDesktop.requireUiThread(unwrap window.context)
        return window
    }

    internal mtd renderHandleNative()->const *void?
    {
        if not .nativeHandle do
            return null
        let window = cast(const *LinuxDesktop.WindowState, .nativeHandle)
        return &window.drawable
    }

    internal mtd rebindNative()
    {
        if .nativeHandle
        {
            let window  = cast #unconst (*LinuxDesktop.WindowState, .nativeHandle)
            let context = unwrap window.context
            Swag.assert(context.uiThread == Env.Process.currentThreadId())
            window.owner = me
        }
    }

    internal mtd closeNative() fail
    {
        let window  = try .x11State()
        let context = unwrap window.context

        // A dead connection or an externally destroyed window has already released
        // its server resource. Both still need local owner cleanup before scope exit.
        let connection = unwrap context.connection
        if context.xcb_connection_has_error(connection) == 0
        {
            let error = context.xcb_request_check(connection, context.xcb_destroy_window_checked(connection, window.id))
            if error
            {
                let code = error.error_code
                Linux.free(error)
                if code != 3 and context.xcb_connection_has_error(connection) == 0 do
                    fail Swag.SystemError{"X11 window destruction failed", errorID: code}
            }
        }

        releaseX11Window(window)
    }

    internal mtd requestPaintNative()
    {
        if not .isOpen() do
            return
        let window = catch .x11State()
        {
            return
        }

        let context = unwrap window.context

        // ClearArea only exposes visible pixels. A smoke drawable outside the desktop
        // still needs an explicit paint request, and SendEvent always carries 32 bytes.
        var storage: Linux.xcb_generic_event_t
        let event = cast(*Linux.xcb_expose_event_t, cast(*void, &storage))
        event.response_type = 12
        event.window        = window.id
        catch LinuxDesktop.check(context,
                                 context.xcb_send_event_checked(unwrap context.connection,
                                                                0,
                                                                window.id,
                                                                1 << 15,
                                                                cast(const [*]u8, &storage)))
    }

    // Returns one: X11 logical coordinates are physical pixels in this backend.
    public mtd const dpiScale()->f32 => 1

    internal mtd setClientSizeNative(width, height: s32) fail
    {
        try validateX11Size(width, height)
        let window       = try .x11State()
        let context      = unwrap window.context
        let size: [2]u32 = [cast(u32, width), cast(u32, height)]
        if not window.resizable
        {
            var hints: [18]u32
            hints[0] = (1 << 4) | (1 << 5)
            hints[5] = cast(u32, width)
            hints[7] = hints[5]
            hints[6] = cast(u32, height)
            hints[8] = hints[6]
            try LinuxDesktop.check(context,
                                   context.xcb_change_property_checked(unwrap context.connection,
                                                                       0,
                                                                       window.id,
                                                                       40,
                                                                       41,
                                                                       32,
                                                                       18,
                                                                       hints))
        }

        try LinuxDesktop.check(context, context.xcb_configure_window_checked(unwrap context.connection, window.id, 4 | 8, size))
    }

    internal mtd clientSizeNative()->{width, height: s32} fail
    {
        let window  = try .x11State()
        let context = unwrap window.context
        var error: *Linux.xcb_generic_error_t?
        let reply   = context.xcb_get_geometry_reply(unwrap context.connection,
                                                     context.xcb_get_geometry(context.connection, window.id),
                                                     &error)
        defer if error do
            Linux.free(error)
        defer if reply do
            Linux.free(reply)
        if error or not reply do
            fail Swag.SystemError{"cannot query X11 window geometry"}
        return {cast(s32, reply.width), cast(s32, reply.height)}
    }

    internal mtd showNative() fail
    {
        let window  = try .x11State()
        let context = unwrap window.context
        try LinuxDesktop.check(context, context.xcb_map_window_checked(unwrap context.connection, window.id))
    }

    internal mtd showOffScreenNative() fail
    {
        let {width, height} = try .clientSizeNative()
        if width > 32768 and height > 32768 do
            fail Errors.BadParameterError{"X11 cannot place this client size entirely outside the root screen"}
        let window     = try .x11State()
        let context    = unwrap window.context
        let connection = unwrap context.connection
        try LinuxDesktop.check(context, context.xcb_unmap_window_checked(connection, window.id))

        // Override-redirect prevents a window manager from moving or activating this drawable.
        let overrideRedirect: u32 = 1
        try LinuxDesktop.check(context, context.xcb_change_window_attributes_checked(connection, window.id, 1 << 9, &overrideRedirect))
        let position: [2]u32 = [cast #bit(u32, -32768's32), cast #bit(u32, -32768's32)]
        try LinuxDesktop.check(context, context.xcb_configure_window_checked(connection, window.id, 1 | 2, position))
        try .showNative()
    }
}

// Dispatches pending X11 paint/resize callbacks on the window-creating thread.
//
// Returns false on a close request, destruction or a lost/unavailable display. A close
// request leaves the window owned. Callbacks may close or move their window. At most
// 4096 events are consumed per call, so continuously arriving input cannot starve frames.
public func processWindowMessages()->bool
{
    let context = catch LinuxDesktop.ensure() { return false }
    catch LinuxDesktop.requireUiThread(context) do return false
    for 4096
    {
        if context.stopRequested do
            return false
        let event = context.xcb_poll_for_event(unwrap context.connection)
        if not event do
            return context.xcb_connection_has_error(context.connection) == 0
        defer Linux.free(event)
        let kind = event.response_type & 0x7F
        var id: u32
        switch kind
        {
        case 12: id = cast(*Linux.xcb_expose_event_t, cast(*void, event)).window
        case 17: id = cast(*Linux.xcb_destroy_notify_event_t, cast(*void, event)).window
        case 22: id = cast(*Linux.xcb_configure_notify_event_t, cast(*void, event)).window
        case 33: id = cast(*Linux.xcb_client_message_event_t, cast(*void, event)).window
        default: continue
        }

        var window = context.windows
        while window and window.id != id do
            window = window.next
        if not window or not window.owner do
            continue
        let owner = window.owner
        switch kind
        {
        case 12:
            let paint    = cast(*Linux.xcb_expose_event_t, cast(*void, event))
            let callback = owner.callbacks.onPaint
            if paint.count == 0 and callback do
                callback(owner)

        case 17:
            releaseX11Window(window)
            return false

        case 22:
            let resize   = cast(*Linux.xcb_configure_notify_event_t, cast(*void, event))
            let callback = owner.callbacks.onResize
            if callback do
                callback(owner, resize.width, resize.height)

        case 33:
            let message = cast(*Linux.xcb_client_message_event_t, cast(*void, event))
            if message.format == 32 and
               message.type == window.protocolsAtom and
               message.data[0] == window.deleteAtom do
                return false
        }

        // The callback may have released window and owner; neither is used again.
    }

    return true
}
