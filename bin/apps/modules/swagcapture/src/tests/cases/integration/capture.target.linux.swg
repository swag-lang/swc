#global if #command == Swag.CompilerCommand.Test and #os == Swag.TargetOs.Linux
#global private

using Core

impl Recorder
{
    mtd testAdvance() { .advance() }
}

func paintRecordFixtureWindow(window: *Env.Window, pixel: u32)
{
    let drawable = expect window.xcbDrawable()
    let library = unwrap Linux.dlopen("libxcb.so.1".buffer, Linux.RTLD_NOW | Linux.RTLD_LOCAL)
    defer discard Linux.dlclose(library)
    let attributes = expect X11Capture.symbol'Linux.xcb_change_window_attributes_checked_fn(library, "xcb_change_window_attributes_checked")
    let clear = expect X11Capture.symbol'Linux.xcb_clear_area_checked_fn(library, "xcb_clear_area_checked")
    let check = expect X11Capture.symbol'Linux.xcb_request_check_fn(library, "xcb_request_check")
    let connection = unwrap drawable.connection
    let changed = check(connection, attributes(connection, drawable.window, 2, &pixel))
    Swag.require(changed == null)
    let cleared = check(connection, clear(connection, 0, drawable.window, 0, 0, 0, 0))
    Swag.require(cleared == null)
}

// A full-screen root read excludes a floating control even when it covers recorded pixels.
#[Swag.TestTag("integration.capture.x11")]
#test
{
    var background = expect Env.createWindow({identifier: "record-under", title: "Recorded pixels",
                                              width: 64, height: 48, stopLoopOnClose: false})
    var chrome = expect Env.createWindow({identifier: "record-chrome", title: "Recording control",
                                          width: 20, height: 20, stopLoopOnClose: false})
    expect background.setPosition(300, 300)
    expect chrome.setPosition(305, 305)
    expect background.show()
    paintRecordFixtureWindow(&background, 0xFF0000)
    expect chrome.show()
    paintRecordFixtureWindow(&chrome, 0x0000FF)
    let covered = expect getScreenRectImage(false, 308, 308, 8, 8)
    Swag.require(covered.pixelColor(0, 0).argb == Pixel.Argb.Blue)

    let clear = expect captureRecordingFrameWithWindow(false, expect chrome.xcbDrawable(), 308, 308, 8, 8)
    Swag.require(clear.pixelColor(0, 0).argb == Pixel.Argb.Red)
    let restored = expect getScreenRectImage(false, 308, 308, 8, 8)
    Swag.require(restored.pixelColor(0, 0).argb == Pixel.Argb.Blue)
}

// A window-relative area follows its frame and waits while the window is hidden.
#[Swag.TestTag("integration.capture.x11")]
#test
{
    var window = expect Env.createWindow({identifier: "capture-target", title: "Following window",
                                          width: 64, height: 48, stopLoopOnClose: false})
    expect window.setPosition(50, 60)
    expect window.show()
    let id = cast(u64, (expect window.xcbDrawable()).window)
    let first = getCaptureWindowBounds(id)
    Swag.require(first.exists and first.visible)

    let target = CaptureTarget.create({first.rect.x + 5, first.rect.y + 7, 20, 15}, id)
    expect window.setPosition(90, 110)
    let moved = getCaptureWindowBounds(id)
    let area = target.resolve()
    Swag.require(area.visible and area.area ==
                 Math.Rectangle{moved.rect.x + 5, moved.rect.y + 7, 20, 15})

    expect window.hide()
    let hidden = target.resolve()
    Swag.require(hidden.exists and not hidden.visible)
    expect window.show()
    Swag.require(target.resolve().visible)
}

// The recorder moves its area with the window and excludes hidden time from its clock.
#[Swag.TestTag("integration.capture.x11")]
#test
{
    var fixture: HeadlessFixture
    fixture.setup()
    defer fixture.shutdown()

    var window = expect Env.createWindow({identifier: "record-target", title: "Record target",
                                          width: 64, height: 48, stopLoopOnClose: false})
    expect window.setPosition(40, 45)
    expect window.show()
    let id = cast(u64, (expect window.xcbDrawable()).window)
    let first = getCaptureWindowBounds(id)
    var recorder: Recorder
    recorder.main = fixture.main
    recorder.target = CaptureTarget.create({first.rect.x + 3, first.rect.y + 4, 20, 15}, id)
    recorder.area = recorder.target.area
    recorder.state = .Recording
    recorder.clock.startAt(Time.monotonicMicroseconds())
    recorder.nextFrame = Swag.U64.Max

    expect window.setPosition(80, 90)
    recorder.testAdvance()
    Swag.require(recorder.area == recorder.target.resolve().area)

    expect window.hide()
    recorder.nextTargetCheck = 0
    recorder.testAdvance()
    Swag.require(recorder.state == .Paused and recorder.pausedForTarget)
    let elapsed = recorder.elapsed()

    expect window.show()
    recorder.nextTargetCheck = 0
    recorder.testAdvance()
    Swag.require(recorder.state == .Recording and not recorder.pausedForTarget)
    Swag.require(recorder.elapsed() >= elapsed)

    expect window.close()
    recorder.nextTargetCheck = 0
    recorder.testAdvance()
    Swag.require(recorder.state == .Stopped)
}
