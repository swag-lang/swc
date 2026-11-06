#global public
#global namespace Testing
#global if #os == Swag.TargetOs.Linux

using Core, Pixel

// Compares an X11 surface's presented pixels with its completed OpenGL render target.
// Call on the window thread between frames; false means no frame has been presented yet.
// This inspects the native window drawable, not the composited desktop image.
func verifyNativePresentation(surface: *Surface)->bool fail
{
    if not (surface.app.renderer is RenderOgl) do
        fail Errors.InvalidFormatError{Errors.mkString("presentation verification needs an OpenGL surface")}
    if not surface.renderFailure.isEmpty() do
        fail Errors.InvalidFormatError{Errors.mkString(surface.renderFailure.toString())}
    if not surface.presentedFrame do
        return false

    let drawable = try surface.xcbDrawable()
    let context  = try LinuxDesktop.ensure()
    let connection = unwrap context.connection
    let width  = surface.rc.width
    let height = surface.rc.height
    let reply = context.xcb_get_image_reply(connection,
                                            context.xcb_get_image(connection, 2, drawable.window, 0, 0,
                                                                  cast(u16, width), cast(u16, height), 0xFFFFFFFF),
                                            null)
    if not reply do
        fail Errors.InvalidFormatError{Errors.mkString("cannot read the X11 window for presentation verification")}
    defer Linux.free(reply)
    if reply.depth != 32 or context.xcb_get_setup(connection).image_byte_order != 0 do
        fail Errors.InvalidFormatError{Errors.mkString("unsupported X11 presentation pixel layout")}

    let target = surface.isDisabled and surface.app.fadeDisabledSurface ? &surface.presentationTarget : &surface.rt
    surface.app.renderer.setCurrentContext(surface.rc)
    let expected = surface.app.renderer.readRenderTarget(target, 0, 0, width, height)
    if not expected.isValid() or cast(u64, context.xcb_get_image_data_length(reply)) != expected.byteCount do
        fail Errors.InvalidFormatError{Errors.mkString("X11 presentation dimensions differ from the render target")}

    var actual = Image.create(width, height, .BGRA8)
    Memory.copy(unwrap actual.pixels.buffer, context.xcb_get_image_data(reply), actual.byteCount)
    actual.flip()
    for index in expected.byteCount
    {
        if Math.abs(cast(s32, actual.pixels[index]) - expected.pixels[index]) > 1 do
            fail Errors.InvalidFormatError{Errors.mkString(Format.toString("presented pixels differ from the GPU target (% x %)", width, height))}
    }

    return true
}
