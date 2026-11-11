#global if #command == Swag.CompilerCommand.Test and #os == Swag.TargetOs.Linux
#global private

using Swag, Core, Pixel

private func paintBenchmarkWindow(window: *Env.Window, pixel: u32)
{
    let drawable = expect window.xcbDrawable()
    let library  = Linux.dlopen("libxcb.so.1".buffer, Linux.RTLD_NOW | Linux.RTLD_LOCAL)
    Swag.require(library != null)
    defer discard Linux.dlclose(unwrap library)
    let attributes = expect X11Capture.symbol'Linux.xcb_change_window_attributes_checked_fn(library, "xcb_change_window_attributes_checked")
    let clear      = expect X11Capture.symbol'Linux.xcb_clear_area_checked_fn(library, "xcb_clear_area_checked")
    let check      = expect X11Capture.symbol'Linux.xcb_request_check_fn(library, "xcb_request_check")
    let connection = unwrap drawable.connection
    let changed = check(connection, attributes(connection, drawable.window, 2, &pixel))
    defer Linux.free(changed)
    Swag.require(changed == null)
    let cleared = check(connection, clear(connection, 0, drawable.window, 0, 0, 0, 0))
    defer Linux.free(cleared)
    Swag.require(cleared == null)
}

// Reports warmed-up frame acquisition on the active X11 server without image allocation.
#[Swag.TestTag("integration.capture.x11")]
#test
{
    var capture = expect X11Capture.create()
    let width  = Math.min(3840's32, cast(s32, capture.desktopWidth()))
    let height = Math.min(2160's32, cast(s32, capture.desktopHeight()))
    var source = expect ScreenFrameSource.create(false, 0, 0, width, height)
    var frame: Image
    expect source.grabInto(&frame)
    let storage = frame.pixels.storage()

    let iterations = width >= 3840 and height >= 2160 ? 16'u64 : 64'u64
    var watch: Time.Stopwatch
    watch.start()
    for iterations do
        expect source.grabInto(&frame)
    watch.stop()

    Swag.require(frame.pixels.storage() == storage)
    Swag.require(frame.pixels[3] == 255)
    Console.printf("X11 BGRA8 % by %: % us for % frames (% us/frame)\n",
                   width, height, watch.elapsedMicroseconds(), iterations,
                   watch.elapsedMicroseconds() / iterations)
}

// Narrow captures exercise both a vector group and the scalar remainder of a row.
#[Swag.TestTag("integration.capture.x11")]
#test
{
    var reference = expect ScreenFrameSource.create(false, 0, 0, 8, 4)
    var wide: Image
    expect reference.grabInto(&wide)
    const Widths: [2] s32 = [2, 6]
    for width in Widths
    {
        var source = expect ScreenFrameSource.create(false, 0, 0, width, 4)
        var narrow: Image
        expect source.grabInto(&narrow)
        for y in 4
        {
            for x in width do
                Swag.require(narrow.pixelColor(x, y).argb == wide.pixelColor(x, y).argb)
        }
    }
}

// The optional MIT-SHM transfer and the ordinary GetImage path must produce
// identical bottom-up BGRA bytes at the active display resolution.
#[Swag.TestTag("integration.capture.x11")]
#test
{
    var capture = expect X11Capture.create()
    let width  = Math.min(3840's32, cast(s32, capture.desktopWidth()))
    let height = Math.min(2160's32, cast(s32, capture.desktopHeight()))
    if width < 128 or height < 96 do
        return
    var top = expect Env.createWindow({identifier: "capture-parity-top", title: "Top capture parity",
                                       width: 64, height: 48, stopLoopOnClose: false})
    var bottom = expect Env.createWindow({identifier: "capture-parity-bottom", title: "Bottom capture parity",
                                          width: 64, height: 48, stopLoopOnClose: false})
    expect top.setPosition(10, 12)
    expect bottom.setPosition(width - 80, height - 60)
    expect top.show()
    expect bottom.show()
    paintBenchmarkWindow(&top, 0xFF0000)
    paintBenchmarkWindow(&bottom, 0x0000FF)
    var fallback = expect X11Capture.create()
    fallback.disableSharedMemory()
    var shared = expect X11Capture.create()
    var expected: Image
    var actual: Image
    expect fallback.imageInto(&expected, false, 0, 0, width, height)
    expect shared.imageInto(&actual, false, 0, 0, width, height)
    Swag.require(expected.byteCount == actual.byteCount)
    Swag.require(Memory.compare(expected.pixels.storage(), actual.pixels.storage(), expected.byteCount) == 0)
    Swag.require(actual.pixelColor(14, 16).argb == Argb.Red)
    Swag.require(actual.pixelColor(width - 76, height - 56).argb == Argb.Blue)
    Console.printf("X11 MIT-SHM % by %: %\n", width, height, shared.usesSharedMemory() ? "enabled" : "fallback")
}

// Replacing a segment for a larger capture keeps the connection usable.
#[Swag.TestTag("integration.capture.x11")]
#test
{
    var capture = expect X11Capture.create()
    var frame: Image
    expect capture.imageInto(&frame, false, 0, 0, 32, 16)
    let firstSize = capture.sharedMemorySize()
    expect capture.imageInto(&frame, false, 0, 0, 64, 32)
    Swag.require(frame.width == 64 and frame.height == 32)
    if capture.usesSharedMemory() do
        Swag.require(firstSize == 32 * 16 * 4 and capture.sharedMemorySize() == 64 * 32 * 4)
}
