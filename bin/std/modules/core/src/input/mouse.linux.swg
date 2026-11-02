#global if #os == Swag.TargetOs.Linux
#global namespace Input

// Returns the cursor in physical X11 desktop pixels, or zero without an available display.
public func mousePosition()->Math.Point
{
    let context    = catch LinuxDesktop.ensure() { return {} }
    let connection = unwrap context.connection
    let reply      = context.xcb_query_pointer_reply(connection, context.xcb_query_pointer(connection, context.screen.root), null)
    if not reply do
        return {}
    defer Linux.free(reply)
    if not reply.same_screen do
        return {}
    return {cast(f32, reply.root_x), cast(f32, reply.root_y)}
}

// Moves the cursor in X11 desktop pixels; unavailable displays and out-of-range coordinates do nothing.
//
// Core X11 pointer coordinates must fit signed 16-bit integers.
public func setMousePosition(x, y: s32)
{
    if x < -32768 or x > 32767 or y < -32768 or y > 32767 do
        return
    let context = catch LinuxDesktop.ensure() { return; }
    catch LinuxDesktop.check(context,
                             context.xcb_warp_pointer_checked(unwrap context.connection,
                                                              0,
                                                              context.screen.root,
                                                              0,
                                                              0,
                                                              0,
                                                              0,
                                                              cast(s16, x),
                                                              cast(s16, y)))
}
