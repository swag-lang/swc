#global if #os == Swag.TargetOs.Linux
#global namespace Env

private func x11Cardinals(context: *LinuxDesktop.Context, name: string)->Array'u32
{
    let property   = catch LinuxDesktop.atom(context, name) { return {} }
    let connection = unwrap context.connection
    let reply      = context.xcb_get_property_reply(connection,
                                                    context.xcb_get_property(connection, 0, context.screen.root, property, 6, 0, 4096),
                                                    null)
    if not reply do
        return {}
    defer Linux.free(reply)
    var result: #returntype
    if reply.type != 6 or reply.format != 32 do
        return result
    let size = context.xcb_get_property_value_length(reply)
    if size < 0 or cast(u32, size) / 4 < reply.value_len do
        return result
    let values = cast([*]u32, context.xcb_get_property_value(reply))
    for i in 0 until reply.value_len do
        result.add(values[i])
    return result
}

private func x11Monitor(bounds: Math.Rectangle, workArea: const *Math.Rectangle?)->Monitor
{
    var work = bounds
    if workArea do
        work.intersect(workArea[])
    return {bounds: bounds, workArea: work, scaleFactor: 1,
            physicalBounds: bounds, physicalWorkArea: work}
}

private func x11RandrMonitors(context: *LinuxDesktop.Context, workArea: const *Math.Rectangle?)->Array'Monitor fail
{
    let library = LinuxDesktop.randrLibrary(context)
    if not library do
        fail Swag.SystemError{"RandR library is unavailable"}
    if not LinuxDesktop.hasExtension(context, library, "xcb_randr_id") do
        fail Swag.SystemError{"RandR extension is unavailable"}
    let query         = try LinuxDesktop.symbol'Linux.xcb_randr_query_version_fn(library, "xcb_randr_query_version")
    let versionReply  = try LinuxDesktop.symbol'Linux.xcb_randr_query_version_reply_fn(library, "xcb_randr_query_version_reply")
    let monitors      = try LinuxDesktop.symbol'Linux.xcb_randr_get_monitors_fn(library, "xcb_randr_get_monitors")
    let monitorsReply = try LinuxDesktop.symbol'Linux.xcb_randr_get_monitors_reply_fn(library, "xcb_randr_get_monitors_reply")
    let iterator      = try LinuxDesktop.symbol'Linux.xcb_randr_get_monitors_monitors_iterator_fn(library, "xcb_randr_get_monitors_monitors_iterator")
    let next          = try LinuxDesktop.symbol'Linux.xcb_randr_monitor_info_next_fn(library, "xcb_randr_monitor_info_next")
    let connection    = unwrap context.connection
    let version       = versionReply(connection, query(connection, 1, 5), null)
    if not version do
        fail Swag.SystemError{"RandR extension is unavailable"}
    defer Linux.free(version)
    if version.major_version < 1 or (version.major_version == 1 and version.minor_version < 5) do
        fail Swag.SystemError{"RandR 1.5 is unavailable"}
    let reply = monitorsReply(connection, monitors(connection, context.screen.root, 1), null)
    if not reply do
        fail Swag.SystemError{"cannot query RandR monitors"}
    defer Linux.free(reply)
    var result: #returntype
    var current = iterator(reply)
    while current.rem > 0 and current.data
    {
        let info = current.data
        if info.width and info.height do
            result.add(x11Monitor({cast(f32, info.x), cast(f32, info.y), cast(f32, info.width), cast(f32, info.height)}, workArea))
        next(&current)
    }

    return result
}

// Returns active RandR 1.5 monitors of the DISPLAY-selected X11 screen.
//
// X11 coordinates are physical pixels, with scaleFactor one. The current desktop's
// EWMH work area is clipped to each monitor when available. Without RandR 1.5, returns
// the real root-screen bounds as one virtual monitor. An unavailable display returns
// an empty array. Native Wayland and per-monitor scaling are not provided by this adapter.
public func getMonitors()->Array'Monitor
{
    let context   = catch LinuxDesktop.ensure() { return {} }
    let desktop   = x11Cardinals(context, "_NET_CURRENT_DESKTOP")
    let workAreas = x11Cardinals(context, "_NET_WORKAREA")
    var workStorage: Math.Rectangle
    var workArea:    const *Math.Rectangle?
    if desktop.count and cast(u64, desktop[0]) * 4 + 3 < workAreas.count
    {
        let offset = cast(u64, desktop[0]) * 4
        workStorage = Math.Rectangle{cast(f32, cast #bit(s32, workAreas[offset])),
                                     cast(f32, cast #bit(s32, workAreas[offset + 1])),
                                     cast(f32, workAreas[offset + 2]), cast(f32, workAreas[offset + 3])}
        workArea = &workStorage
    }

    var result: Array'Monitor
    catch { result = try x11RandrMonitors(context, workArea) }
    if not result.isEmpty() do
        return result
    let connection = unwrap context.connection
    let geometry   = context.xcb_get_geometry_reply(connection,
                                                    context.xcb_get_geometry(connection, context.screen.root),
                                                    null)
    if geometry
    {
        defer Linux.free(geometry)
        result.add(x11Monitor({0, 0, cast(f32, geometry.width), cast(f32, geometry.height)}, workArea))
    }

    return result
}

// Returns the physical-pixel bounds of the X11 virtual desktop, or zero without a display.
public func getSystemMetric(what: SystemMetric)->s32
{
    let monitors = getMonitors()
    if monitors.isEmpty() do
        return 0
    var left   = monitors[0].physicalBounds.x
    var top    = monitors[0].physicalBounds.y
    var right  = monitors[0].physicalBounds.right()
    var bottom = monitors[0].physicalBounds.bottom()
    for monitor in monitors
    {
        left   = Math.min(left, monitor.physicalBounds.x)
        top    = Math.min(top, monitor.physicalBounds.y)
        right  = Math.max(right, monitor.physicalBounds.right())
        bottom = Math.max(bottom, monitor.physicalBounds.bottom())
    }

    switch #complete what
    {
    case .DesktopX:      return cast(s32, left)
    case .DesktopY:      return cast(s32, top)
    case .DesktopWidth:  return cast(s32, right - left)
    case .DesktopHeight: return cast(s32, bottom - top)
    }
}
