#global if #command == Swag.CompilerCommand.Test and #os == Swag.TargetOs.Linux
#global private

using Core, Pixel

func paintCaptureWindow(window: *Env.Window, pixel: u32)
{
    let drawable = expect window.xcbDrawable()
    let library  = Linux.dlopen("libxcb.so.1".buffer, Linux.RTLD_NOW | Linux.RTLD_LOCAL)
    Swag.assert(library != null)
    defer discard Linux.dlclose(unwrap library)
    let attributes = expect X11Capture.symbol'Linux.xcb_change_window_attributes_checked_fn(library, "xcb_change_window_attributes_checked")
    let clear      = expect X11Capture.symbol'Linux.xcb_clear_area_checked_fn(library, "xcb_clear_area_checked")
    let check      = expect X11Capture.symbol'Linux.xcb_request_check_fn(library, "xcb_request_check")
    let connection = unwrap drawable.connection
    let changed    = check(connection, attributes(connection, drawable.window, 2, &pixel))
    defer Linux.free(changed)
    Swag.assert(changed == null)
    let cleared = check(connection, clear(connection, 0, drawable.window, 0, 0, 0, 0))
    defer Linux.free(cleared)
    Swag.assert(cleared == null)
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
    Swag.assert(actual.width == 112 and actual.height == 48)
    Swag.assert(actual.pixelColor(4, 5).argb == Argb.Red)
    Swag.assert(actual.pixelColor(84, 5).argb == Argb.Blue)
    Swag.assert(actual.pixelColor(4, 42).argb == Argb.Red)
    let firstId  = (expect first.xcbDrawable()).window
    let secondId = (expect second.xcbDrawable()).window
    Swag.assert(capture.windowAt(0, 15, 25) == firstId)
    Swag.assert(capture.windowAt(firstId, 15, 25) == 0)
    Swag.assert(capture.windowAt(0, 95, 25) == secondId)
    let info = capture.windowInfo(firstId)
    Swag.assert(info.title == "Red capture fixture")
    let bounds = capture.windowRect(secondId)
    Swag.assert(bounds.x == 90 and bounds.y == 20 and bounds.width == 32 and bounds.height == 32)
    var outcome: Swag.Error
    discard catch capture.image(false, -1, 0, 8, 8) as outcome
    Swag.assert(outcome.value() is Errors.BadParameterError)
    discard catch capture.image(false, 0, 0, 0, 8) as outcome
    Swag.assert(outcome.value() is Errors.BadParameterError)
    discard catch capture.image(false, 0, 0, cast(s32, capture.screen.width_in_pixels) + 1, 8) as outcome
    Swag.assert(outcome.value() is Errors.BadParameterError)
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
    let check   = expect X11Capture.symbol'Linux.xcb_request_check_fn(unwrap capture.library, "xcb_request_check")
    let error   = check(unwrap capture.connection, warp(unwrap capture.connection, 0, capture.screen.root, 0, 0, 0, 0, 40, 50))
    defer Linux.free(error)
    Swag.assert(error == null)
    let plain   = expect capture.image(false, 10, 20, 64, 64)
    let cursor  = expect capture.image(true, 10, 20, 64, 64)
    var changed = false
    for index in plain.pixels.count where plain.pixels[index] != cursor.pixels[index]
    {
        changed = true
        break
    }

    Swag.assert(changed)
    Swag.assert(cursor.pixelColor(0, 0).argb == Argb.Red)
}
