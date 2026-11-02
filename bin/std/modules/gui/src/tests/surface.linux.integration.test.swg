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
    discard PushButton.create(surface.wnd.view, "Native button", {24, 72, 160, 36})
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

    // XCB rows start at the top; Pixel.Image storage starts at the bottom.
    let snapshot = context.xcb_get_image_reply(connection,
                                               context.xcb_get_image(connection,
                                                                     2,
                                                                     drawable.window,
                                                                     0,
                                                                     0,
                                                                     cast(u16, surface.rc.width),
                                                                     cast(u16, surface.rc.height),
                                                                     0xFFFFFFFF),
                                               null)
    Swag.assert(snapshot != null)
    defer Linux.free(snapshot)
    var saved = Image.create(surface.rc.width, surface.rc.height, .BGRA8)
    Swag.assert(cast(u64, context.xcb_get_image_data_length(snapshot)) == saved.byteCount)
    Memory.copy(unwrap saved.pixels.buffer, context.xcb_get_image_data(snapshot), saved.byteCount)
    saved.flip()
    let reference = app.renderer.readRenderTarget(&surface.rt, 0, 0, surface.rc.width, surface.rc.height)
    for index in saved.byteCount do
        Swag.assert(Math.abs(cast(s32, saved.pixels[index]) - reference.pixels[index]) <= 1,
                    "native presentation differs from its render target")
    if Env.variable("SWAG_GUI_NATIVE_CAPTURE") == "1"
    {
        let capturePath = Path.combine(Env.getSpecialDirectory(.Temp), "gui-native-window.png")
        expect saved.save(capturePath.toString())
        Console.println("Native GUI capture: ", capturePath)
    }

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
    app.runFrame()
    Swag.assert(app.surfaces.isEmpty() and app.mustQuit)
}

struct NativeInputProbe
{
    pressed, released, extra, wheel, shiftA, controlA, characters: u32
    character: rune
}

// Actual queued X11 input preserves a click completed between GUI frames and modifier text.
#[Swag.TestTag("integration.desktop")]
#test
{
    Swag.assert(Env.variable("SWAG_TEST_ISOLATED_X11") == "1")
    var app: Application
    app.setMotionPreference(.Reduced)
    let surface = expect app.createSurface(60, 50, 320, 240, surfaceId: "linux-native-input")
    surface.show()
    for 4 do
        app.runFrame()
    surface.wnd.view.focusPolicy = .Click
    surface.wnd.view.setFocus()
    var probe: NativeInputProbe
    surface.wnd.view.hookOnEvent = func|&probe|(_, event)->bool
    {
        if event is MouseEvent as mouse
        {
            if mouse.kind == .Pressed and mouse.button == .Left do
                probe.pressed += 1
            elif mouse.kind == .Released and mouse.button == .Left do
                probe.released += 1
            elif mouse.kind == .Pressed and mouse.button == .XButton1 do
                probe.extra += 1
            elif mouse.kind == .Wheel do
                probe.wheel += 1
        }
        elif event is KeyEvent as key
        {
            if key.kind == .Pressed and key.key == .A and key.modifiers.has(.Shift)
            {
                probe.shiftA += 1
            }
            elif key.kind == .Pressed and key.key == .A and key.modifiers.has(.Control)
            {
                probe.controlA += 1
            }
            elif key.kind == .Character
            {
                probe.characters += 1
                probe.character  = key.character
            }

            return true
        }

        return false
    }

    defer surface.wnd.view.hookOnEvent = null
    let script = Path.combine(unwrap Path.directoryName(#curlocation.fileName), "datas/input.x11.peer.py")
    let id     = Format.toString("%", surface.windowId)
    var peer   = expect Env.startProcess(Env.StartInfo{fileName: "python3", arguments: [script.toString(), id.toString()],
                                                       standardOutput: .Pipe, standardError: .Pipe})
    defer { discard catch peer.kill(); discard catch peer.waitForExit(); }
    let deadline = Time.monotonicMilliseconds() + 3000
    while peer.isRunning() and Time.monotonicMilliseconds() < deadline
    {
        app.runFrame()
        discard expect peer.tryWaitForExit(5'ms)
    }

    for 8 do
        app.runFrame()
    Swag.assert(not peer.isRunning() and peer.exitCode() == 0, peer.standardError())
    Swag.assert(probe.pressed == 1 and probe.released == 1 and probe.extra == 1 and probe.wheel == 1)
    Swag.assert(probe.shiftA == 1 and probe.controlA == 1 and probe.characters == 1 and probe.character == 'A',
                Format.toString("shift=%, control=%, characters=%, rune=%", probe.shiftA, probe.controlA, probe.characters, cast(u32, probe.character)))
}
