#global public
#global namespace Testing
#global if #os == Swag.TargetOs.Linux

using Core, Pixel

private func nativePresentationSizeMatches(context: *LinuxDesktop.Context, window: u32, width, height: s32)->bool fail
{
    let connection = unwrap context.connection
    let request    = context.xcb_get_geometry(connection, window)
    let geometry   = context.xcb_get_geometry_reply(connection, request, null)
    if not geometry
    {
        fail Errors.InvalidFormatError{Errors.mkString("cannot read the X11 window size for presentation verification")}
    }

    defer Linux.free(geometry)
    return geometry.width == width and geometry.height == height
}

// Compares an X11 surface's presented pixels with its completed OpenGL render target.
//
// Call on the window thread between frames. Returns false until the X11 drawable has the render
// target's size and shows the latest frame. Reads pixels directly from the native window.
func verifyNativePresentation(surface: *Surface)->bool fail
{
    if not (surface.app.renderer is RenderOgl)
    {
        fail Errors.InvalidFormatError{Errors.mkString("presentation verification needs an OpenGL surface")}
    }

    if not surface.renderFailure.isEmpty()
    {
        fail Errors.InvalidFormatError{Errors.mkString(surface.renderFailure.toString())}
    }

    if not surface.presentedFrame
    {
        return false
    }

    let drawable   = try surface.xcbDrawable()
    let context    = try LinuxDesktop.ensure()
    let connection = unwrap context.connection
    let width      = surface.rc.width
    let height     = surface.rc.height
    if not LinuxDesktop.isWindowViewable(context, drawable.window) or
       not (try nativePresentationSizeMatches(context, drawable.window, width, height))
    {
        return false
    }

    let request = context.xcb_get_image(connection, 2, drawable.window, 0, 0, cast(u16, width), cast(u16, height), 0xFFFFFFFF)
    let reply   = context.xcb_get_image_reply(connection, request, null)
    if not reply
    {
        // The window manager can hide or resize the drawable between the two requests.
        if not LinuxDesktop.isWindowViewable(context, drawable.window) or
           not (try nativePresentationSizeMatches(context, drawable.window, width, height))
        {
            return false
        }

        fail Errors.InvalidFormatError{Errors.mkString("cannot read the X11 window for presentation verification")}
    }

    defer Linux.free(reply)
    if reply.depth != 32 or context.xcb_get_setup(connection).image_byte_order != 0
    {
        fail Errors.InvalidFormatError{Errors.mkString("unsupported X11 presentation pixel layout")}
    }

    let target = surface.hasDisabledTint() ? &surface.presentationTarget : &surface.rt
    surface.app.renderer.setCurrentContext(surface.rc)
    let expected = surface.app.renderer.readRenderTarget(target, 0, 0, width, height)
    if not expected.isValid() or cast(u64, context.xcb_get_image_data_length(reply)) != expected.byteCount
    {
        fail Errors.InvalidFormatError{Errors.mkString("X11 presentation dimensions differ from the render target")}
    }

    var actual = Image.create(width, height, .BGRA8)
    Memory.copy(unwrap actual.pixels.buffer, context.xcb_get_image_data(reply), actual.byteCount)
    actual.flip()
    for index in expected.byteCount
    {
        if Math.abs(cast(s32, actual.pixels[index]) - expected.pixels[index]) > 1
        {
            return false
        }
    }

    return true
}
