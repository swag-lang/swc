#global if #command == Swag.CompilerCommand.Test and #os == Swag.TargetOs.Linux
#global private

using Core, Pixel

func paintCaptureWindow(window: *Env.Window, pixel: u32)
{
    let drawable = expect window.xcbDrawable()
    let library  = Linux.dlopen("libxcb.so.1".buffer, Linux.RTLD_NOW | Linux.RTLD_LOCAL)
    Swag.require(library != null)
    defer discard Linux.dlclose(unwrap library)
    let attributes = expect X11Capture.symbol'Linux.xcb_change_window_attributes_checked_fn(library, "xcb_change_window_attributes_checked")
    let clear      = expect X11Capture.symbol'Linux.xcb_clear_area_checked_fn(library, "xcb_clear_area_checked")
    let check      = expect X11Capture.symbol'Linux.xcb_request_check_fn(library, "xcb_request_check")
    let connection = unwrap drawable.connection
    let changed    = check(connection, attributes(connection, drawable.window, 2, &pixel))
    defer Linux.free(changed)
    Swag.require(changed == null)
    let cleared = check(connection, clear(connection, 0, drawable.window, 0, 0, 0, 0))
    defer Linux.free(cleared)
    Swag.require(cleared == null)
}

// Run on an isolated X11 display: this exercises actual root pixels, never the test image fake.
#[Swag.TestTag("integration.capture.x11")]
#test
{
    var first  = expect Env.createWindow({identifier: "capture-red", title: "Red capture fixture", width: 64, height: 48, stopLoopOnClose: false})
    var second = expect Env.createWindow({identifier: "capture-blue", title: "Blue capture fixture", width: 32, height: 32, stopLoopOnClose: false})
    expect first.setPosition(10, 20)
    expect second.setPosition(90, 20)
    expect first.show()
    expect second.show()
    paintCaptureWindow(&first, 0xFF0000)
    paintCaptureWindow(&second, 0x0000FF)
    var capture = expect X11Capture.create()
    let actual  = expect capture.image(false, 10, 20, 112, 48)
    Swag.require(actual.width == 112 and actual.height == 48)
    Swag.require(actual.pixelColor(4, 5).argb == Argb.Red)
    Swag.require(actual.pixelColor(84, 5).argb == Argb.Blue)
    Swag.require(actual.pixelColor(4, 42).argb == Argb.Red)
    let firstId  = (expect first.xcbDrawable()).window
    let secondId = (expect second.xcbDrawable()).window
    Swag.require(capture.windowAt(0, 15, 25) == firstId)
    Swag.require(capture.windowAt(firstId, 15, 25) == 0)
    Swag.require(capture.windowAt(0, 95, 25) == secondId)
    let info = capture.windowInfo(firstId)
    Swag.require(info.title == "Red capture fixture")
    let bounds = capture.windowRect(secondId)
    Swag.require(bounds.x == 90 and bounds.y == 20 and bounds.width == 32 and bounds.height == 32)
    var outcome: Swag.Error
    discard catch capture.image(false, -1, 0, 8, 8) as outcome
    Swag.require(outcome.value() is Errors.BadParameterError)
    discard catch capture.image(false, 0, 0, 0, 8) as outcome
    Swag.require(outcome.value() is Errors.BadParameterError)
    discard catch capture.image(false, 0, 0, cast(s32, capture.screen.width_in_pixels) + 1, 8) as outcome
    Swag.require(outcome.value() is Errors.BadParameterError)
}

#[Swag.TestTag("integration.capture.x11")]
#test
{
    var window = expect Env.createWindow({identifier: "capture-cursor", title: "Cursor capture fixture", width: 64, height: 64, stopLoopOnClose: false})
    expect window.setPosition(10, 20)
    expect window.show()
    paintCaptureWindow(&window, 0xFF0000)
    var capture = expect X11Capture.create()
    let warp    = expect X11Capture.symbol'Linux.xcb_warp_pointer_checked_fn(unwrap capture.library, "xcb_warp_pointer_checked")
    let check   = expect X11Capture.symbol'Linux.xcb_request_check_fn(capture.library, "xcb_request_check")
    let error   = check(unwrap capture.connection, warp(capture.connection, 0, capture.screen.root, 0, 0, 0, 0, 40, 50))
    defer Linux.free(error)
    Swag.require(error == null)
    let plain   = expect capture.image(false, 10, 20, 64, 64)
    let cursor  = expect capture.image(true, 10, 20, 64, 64)
    var changed = false
    for index in plain.pixels.count where plain.pixels[index] != cursor.pixels[index]
    {
        changed = true
        break
    }

    Swag.require(changed)
    Swag.require(cursor.pixelColor(0, 0).argb == Argb.Red)
}

// The application command must carry real X11 pixels into the editor and its saved document.
#[Swag.TestTag("integration.capture.x11")]
#test
{
    var window = expect Env.createWindow({identifier: "capture-app-red", title: "Capture application fixture", width: 64, height: 48, stopLoopOnClose: false})
    expect window.setPosition(10, 20)
    expect window.show()
    paintCaptureWindow(&window, 0xFF0000)

    var f: HeadlessFixture
    f.setup(registerHeadlessCommands: true)
    defer f.shutdown()
    testRegisterIoActions(f.main)
    testPrepareRecentLibrary(f.main)

    f.main.captureOptions.hideEditorBefore = false
    f.main.captureOptions.captureCursor    = false
    f.main.captureOptions.sendToClipboard  = false
    f.main.captureOptions.sendToEditor     = true
    f.main.captureOptions.inPlaceEdit      = false
    f.main.captureOptions.delay            = 0

    g_StartGrabX = 10
    g_StartGrabY = 20
    g_EndGrabX   = 74
    g_EndGrabY   = 68

    Swag.require(Gui.Testing.actionExecute'ActionCapture(f.main, ActionCapture.LastArea))
    f.gui.pump()

    let capture = unwrap f.main.getCapture()
    let path    = capture.file
    defer
    {
        discard catch File.delete(path)
        g_Library.files.clear()
    }

    Swag.require(capture.sourceKind == .Screen)
    Swag.require(capture.width == 64 and capture.height == 48)
    Swag.require(capture.backImg.pixelColor(4, 5).argb == Argb.Red)
    Swag.require(File.exists(path))

    let loaded = expect Capture.load(path)
    defer Memory.delete(loaded)
    Swag.require(loaded.width == 64 and loaded.height == 48)
    Swag.require(loaded.sourceKind == .Screen)
    Swag.require(loaded.backImg.pixelColor(4, 5).argb == Argb.Red)
}

// A later monitor command must select its own bounds and publish the acquired pixels.
#[Swag.TestTag("integration.capture.x11")]
#test
{
    var window = expect Env.createWindow({identifier: "capture-app-blue", title: "Capture monitor fixture", width: 64, height: 48, stopLoopOnClose: false})
    expect window.setPosition(10, 20)
    expect window.show()
    paintCaptureWindow(&window, 0x0000FF)

    var f: HeadlessFixture
    f.setup(registerHeadlessCommands: true)
    defer f.shutdown()
    testRegisterIoActions(f.main)

    f.main.captureOptions.hideEditorBefore = false
    f.main.captureOptions.captureCursor    = false
    f.main.captureOptions.sendToClipboard  = true
    f.main.captureOptions.sendToEditor     = false
    f.main.captureOptions.inPlaceEdit      = false
    f.main.captureOptions.delay            = 0

    f.main.monitors.clear()
    for 4 do
        testAddMonitorAt(f.main, {0, 0, 8, 8})
    testAddMonitorAt(f.main, {10, 20, 64, 48})

    Swag.require(Gui.Testing.actionExecute'ActionCapture(f.main, ActionCapture.screenId(4)))
    let image = Clipboard.getImage()
    Swag.require(image.isValid())
    Swag.require(image.width == 64 and image.height == 48)
    Swag.require(image.pixelColor(4, 5).argb == Argb.Blue)
}

// A native application surface must keep presenting after its capture command opens the image.
#[Swag.TestTag("integration.capture.application")]
#test
{
    Swag.require(Env.variable("SWAG_TEST_ISOLATED_X11") == "1")
    // Earlier headless fixtures bind their renderer to this global application.
    // Reset it before creating a native surface and after retiring that surface.
    Swag.drop(&g_App, 1)
    Swag.init(&g_App, 1)
    defer
    {
        Swag.drop(&g_App, 1)
        Swag.init(&g_App, 1)
        g_Main = null
    }
    testUseScratchLibrary()
    expect Library.init()
    g_Library.loaded = true

    let stateFile = Gui.Testing.tempFilePath("capture-app-state-", ".scc")
    defer discard catch File.delete(stateFile)
    g_App.setStatePath(stateFile)
    registerAppStrings(&g_App.resources)
    let surface = expect g_App.createSurface(100, 100, 1100, 700, surfaceId: "capture-linux-app-journey")
    let main    = MainWnd.create(surface.wnd)
    surface.show()
    for 12 do
        g_App.runFrame()
    Swag.require(expect Gui.Testing.verifyNativePresentation(surface))

    var window = expect Env.createWindow({identifier: "capture-gui-target", title: "Capture GUI fixture", width: 64, height: 48, stopLoopOnClose: false})
    expect window.setPosition(10, 20)
    expect window.show()
    paintCaptureWindow(&window, 0xFF0000)

    main.captureOptions.hideEditorBefore = false
    main.captureOptions.captureCursor    = false
    main.captureOptions.sendToClipboard  = false
    main.captureOptions.sendToEditor     = true
    main.captureOptions.inPlaceEdit      = false
    main.captureOptions.delay            = 0
    g_StartGrabX = 10
    g_StartGrabY = 20
    g_EndGrabX   = 74
    g_EndGrabY   = 68

    main.sendCommandEvent(ActionCapture.LastArea)
    let capture = unwrap main.editWnd.getCapture()
    let path    = capture.file
    defer discard catch File.delete(path)
    Swag.require(capture.sourceKind == .Screen)
    Swag.require(capture.backImg.pixelColor(4, 5).argb == Argb.Red)
    Swag.require(File.exists(path))

    var presented = false
    for 40
    {
        g_App.runFrame()
        if expect Gui.Testing.verifyNativePresentation(surface)
        {
            presented = true
            break
        }
    }
    Swag.require(presented, "the capture editor never reached its native X11 surface")
}
