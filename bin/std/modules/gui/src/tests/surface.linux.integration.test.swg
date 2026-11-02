#global if #command == Swag.CompilerCommand.Test and #os == Swag.TargetOs.Linux
#global private

using Core, Pixel

// Exercises a real ARGB XCB drawable and EGL swap, including independent native queries.
#[Swag.TestTag("integration.desktop")]
#test
{
    Swag.assert(Env.variable("SWAG_TEST_ISOLATED_X11") == "1", "native GUI integration requires an isolated X11 server")
    var app: Application
    app.setMotionPreference(.Reduced)
    let surface = expect app.createSurface(70, 60, 360, 240, surfaceId: "linux-native-gui")
    surface.setTitle("Native GUI — é")
    discard PushButton.create(surface.wnd.view, "Native button", {24, 24, 160, 36})
    surface.show()
    for 8 do
        app.runFrame()
    Swag.assert(not surface.isHidden and surface.presentedFrame)
    let drawable = expect surface.xcbDrawable()
    Swag.assert(drawable.window != 0 and drawable.visual != 0)
    let context    = expect LinuxDesktop.ensure()
    let connection = unwrap context.connection
    let attrs      = context.xcb_get_window_attributes_reply(connection, context.xcb_get_window_attributes(connection, drawable.window), null)
    Swag.assert(attrs != null)
    Swag.assert(attrs.map_state == 2 and attrs.visual == drawable.visual)
    Linux.free(attrs)
    let title = expect LinuxDesktop.readProperty(context, drawable.window, expect LinuxDesktop.atom(context, "_NET_WM_NAME"))
    Swag.assert(Utf8.compare(title.toSlice(), "Native GUI — é") == 0)

    app.renderer.setCurrentContext(surface.rc)
    let expected = app.renderer.readRenderTarget(&surface.rt, 160, 140, 1, 1).pixelColor(0, 0)
    let image    = context.xcb_get_image_reply(connection, context.xcb_get_image(connection, 2, drawable.window, 160, 140, 1, 1, 0xFFFFFFFF), null)
    Swag.assert(image != null)
    Swag.assert(image.depth == 32 and context.xcb_get_image_data_length(image) >= 4)
    let bytes = context.xcb_get_image_data(image)
    Swag.assert(context.xcb_get_setup(connection).image_byte_order == 0)
    Swag.assert(Math.abs(cast(s32, bytes[2]) - expected.r) <= 1)
    Swag.assert(Math.abs(cast(s32, bytes[1]) - expected.g) <= 1)
    Swag.assert(Math.abs(cast(s32, bytes[0]) - expected.b) <= 1)
    Swag.assert(bytes[3] == expected.a and expected.a == 255)
    Linux.free(image)

    var message: u64
    surface.wnd.view.hookOnEvent = func|&message|(_, event)->bool
    {
        if event is SysUserEvent as notice where notice.kind == .CustomMessage
        {
            Swag.assert(notice.messageId == 71)
            message = notice.param
            return true
        }

        return false
    }

    let sent = Surface.sendCustomMessage("linux-native-gui", 71, 0x12345678ABCDEF01)
    Swag.assert(sent)
    for 8 do
        app.runFrame()
    Swag.assert(message == 0x12345678ABCDEF01)
    surface.wnd.view.hookOnEvent = null

    surface.hide()
    for 4 do
        app.runFrame()
    Swag.assert(surface.isHidden)
    surface.show()
    surface.setPosition({90, 80, 400, 280})
    for 8 do
        app.runFrame()
    Swag.assert(surface.rc.width == 400 and surface.rc.height == 280)
    var point = Math.Point{20, 30}
    surface.surfaceToScreen(&point)
    surface.screenToSurface(&point)
    Swag.assert(point == {20, 30})
    Cursor.activate(Cursor.from(.IBeam))
    Cursor.activate(Cursor.from(.Arrow))
    let second = expect app.createSurface(500, 80, 180, 160, surfaceId: "linux-native-secondary")
    second.show()
    for 4 do
        app.runFrame()
    second.destroy()
    for 4 do
        app.runFrame()
    Swag.assert(app.surfaces.count == 1 and not app.mustQuit)
    surface.destroy()
    app.runFrame()
    Swag.assert(app.surfaces.isEmpty() and app.mustQuit)
}
