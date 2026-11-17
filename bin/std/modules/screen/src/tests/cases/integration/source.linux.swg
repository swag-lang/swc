#global if #os == Swag.TargetOs.Linux
#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel

private func warpPointer(capture: *X11Capture, x, y: s16)
{
    let warp = expect X11Capture.symbol'Linux.xcb_warp_pointer_checked_fn(
        unwrap capture.nativeLibrary(), "xcb_warp_pointer")
    discard warp(unwrap capture.nativeConnection(), 0, capture.rootWindow(), 0, 0, 0, 0, x, y)
}

private func pointerPosition(capture: *X11Capture)->{x: s16, y: s16} fail
{
    let query = expect X11Capture.symbol'Linux.xcb_query_pointer_fn(
        unwrap capture.nativeLibrary(), "xcb_query_pointer")
    let replyQuery = expect X11Capture.symbol'Linux.xcb_query_pointer_reply_fn(
        unwrap capture.nativeLibrary(), "xcb_query_pointer_reply")
    let connection = unwrap capture.nativeConnection()
    let reply = replyQuery(connection, query(connection, capture.rootWindow()), null)
    if not reply do
        fail Swag.SystemError{"cannot read the X11 pointer position"}
    defer Linux.free(reply)
    return {reply.root_x, reply.root_y}
}

private func openDescriptorCount()->u64
{
    let directory = unwrap Linux.opendir("/proc/self/fd".buffer)
    defer discard Linux.closedir(directory)
    var count = 0'u64
    while Linux.readdir(directory) do
        count += 1
    return count
}

private func sharedMappingCount()->u64 fail
{
    let maps = try File.readAllLines("/proc/self/maps")
    var count = 0'u64
    for line in maps where line.contains("/SYSV") do
        count += 1
    return count
}

private func sharedSegmentCount()->u64 fail
{
    let segments = try File.readAllLines("/proc/sysvipc/shm")
    return segments.count - 1
}

// Opens the complete first monitor reported by the physical display enumeration.
#[Swag.TestTag("integration.host.linux")]
#test
{
    let monitors = Env.getMonitors()
    if not monitors.count do
        return
    let bounds = monitors[0].physicalBounds
    var source = expect Source.openMonitor(monitors[0])
    let pointSource = expect Source.openMonitorAt({bounds.x + bounds.width / 2,
                                                    bounds.y + bounds.height / 2})
    let pointOptions = pointSource.captureOptions()
    Swag.require(pointOptions.x == cast(s32, bounds.x) and pointOptions.y == cast(s32, bounds.y) and
                 pointOptions.width == cast(s32, bounds.width) and
                 pointOptions.height == cast(s32, bounds.height))
    var image: Image
    let fresh = expect source.grabInto(&image)
    Swag.require(fresh)
    Swag.require(image.width == cast(s32, bounds.width) and
                 image.height == cast(s32, bounds.height) and image.pixelFormat == .BGRA8)
}

// Opens the full virtual desktop, including any gaps between monitors.
#[Swag.TestTag("integration.host.linux")]
#test
{
    let width = Env.getSystemMetric(.DesktopWidth)
    let height = Env.getSystemMetric(.DesktopHeight)
    if width <= 0 or height <= 0 do
        return
    var source = expect Source.openDesktop()
    let options = source.captureOptions()
    Swag.require(options.width == width and options.height == height)
    var image: Image
    let fresh = expect source.grabInto(&image)
    Swag.require(fresh)
    Swag.require(image.width == width and image.height == height and image.pixelFormat == .BGRA8)
}

// A region outside the connected X11 screen is rejected while opening the source.
#[Swag.TestTag("integration.host.linux")]
#test
{
    var capture = expect X11Capture.create()
    let x = cast(s32, capture.desktopWidth())
    var failure: Swag.Error
    discard catch Source.open({x, 0, 1, 1, false}) as failure
    Swag.require(failure.value() is Errors.BadParameterError)
}

// Runs against an X11 server such as Xvfb, including its shared-memory path.
#[Swag.TestTag("integration.host.linux")]
#test
{
    var source = expect Source.open({0, 0, 320, 240, false})
    let options = source.captureOptions()
    Swag.require(options.x == 0 and options.y == 0 and options.width == 320 and
                 options.height == 240 and not options.includeCursor)
    Swag.require(source.lastFrameCaptureMicroseconds() == 0)
    var image = Image.create(8, 8, .RGBA8)
    let firstFresh = expect source.grabInto(&image)
    Swag.require(firstFresh)
    let firstCaptureTime = source.lastFrameCaptureMicroseconds()
    Swag.require(firstCaptureTime > 0)
    Swag.require(source.lastFramePresentationMicroseconds() == 0)
    Swag.require(image.width == 320 and image.height == 240)
    Swag.require(image.pixelFormat == .BGRA8 and image.byteCount == 320 * 240 * 4)
    let storage = image.pixels.storage()
    let firstMetrics = source.metrics()
    Swag.require(firstMetrics.acquiredFrames == 1 and firstMetrics.unchangedFrames == 0 and
                 firstMetrics.readbackMicroseconds > 0 and firstMetrics.maxReadbackMicroseconds > 0 and
                 firstMetrics.copyMicroseconds > 0 and firstMetrics.copiedPixels == 320 * 240)

    Memory.set(image.pixels.storage(), 0x5A, image.byteCount)
    let repeatedFresh = expect source.grabInto(&image, copyUnchanged: false)
    Swag.require(not repeatedFresh, "identical X11 pixels should not be a fresh frame")
    for byte in image.pixels do
        Swag.require(byte == 0x5A, "an unchanged grab should leave a reusable target untouched")
    Swag.require(source.lastFrameCaptureMicroseconds() == firstCaptureTime)
    let repeatedMetrics = source.metrics()
    Swag.require(repeatedMetrics.acquiredFrames == 2 and repeatedMetrics.unchangedFrames == 1 and
                 repeatedMetrics.changeDetectionMicroseconds > 0)

    image = Image.create(8, 8, .RGBA8)
    let replacementFresh = expect source.grabInto(&image, copyUnchanged: false)
    Swag.require(not replacementFresh and image.width == 320 and image.height == 240,
                 "a replacement target should receive the cached X11 frame")
    Swag.require(Memory.compare(image.pixels.storage(), source.pictures[0].pixels.storage(),
                                image.byteCount) == 0)

    Memory.set(image.pixels.storage(), 0xA5, image.byteCount)
    let copiedFresh = expect source.grabInto(&image)
    Swag.require(not copiedFresh and
                 Memory.compare(image.pixels.storage(), source.pictures[0].pixels.storage(),
                                image.byteCount) == 0,
                 "default unchanged grabs should copy the cached frame")

    let capture = source.sources[0].capture.nativeConnection()
    source.resetMetrics()
    let resetMetrics = source.metrics()
    Swag.require(resetMetrics.acquiredFrames == 0 and resetMetrics.unchangedFrames == 0 and
                 resetMetrics.acquireMicroseconds == 0 and resetMetrics.readbackMicroseconds == 0 and
                 resetMetrics.copyMicroseconds == 0 and resetMetrics.composeMicroseconds == 0 and
                 resetMetrics.changeDetectionMicroseconds == 0 and
                 resetMetrics.copiedPixels == 0 and resetMetrics.mirroredPixels == 0)
    Swag.require(source.sources[0].capture.nativeConnection() == capture and
                 source.lastFrameCaptureMicroseconds() == firstCaptureTime)

    expect source.reopen()
    Swag.require(source.lastFrameCaptureMicroseconds() == 0)
    Swag.require(source.lastFramePresentationMicroseconds() == 0)
    let secondFresh = expect source.grabInto(&image, copyUnchanged: false)
    Swag.require(secondFresh)
    Swag.require(source.lastFrameCaptureMicroseconds() >= firstCaptureTime)
    Swag.require(image.width == 320 and image.height == 240)
    Swag.require(image.pixels.storage() == storage)
    let secondMetrics = source.metrics()
    Swag.require(secondMetrics.acquiredFrames == 1 and secondMetrics.readbackMicroseconds > 0)
}

// XFixes cursor motion creates a fresh composed frame even when the desktop is static.
#[Swag.TestTag("integration.host.linux")]
#test
{
    var source = expect Source.open({0, 0, 320, 240, true})
    let capture = &source.sources[0].capture
    let original = expect pointerPosition(capture)
    defer warpPointer(capture, original.x, original.y)

    warpPointer(capture, 48, 48)
    var image: Image
    Swag.require(expect source.grabInto(&image, copyUnchanged: false))
    var previous = Image.create(image.width, image.height, .BGRA8)
    Memory.copy(previous.pixels.storage(), image.pixels.storage(), image.byteCount)

    warpPointer(capture, 240, 180)
    let fresh = expect source.grabInto(&image, copyUnchanged: false)
    Swag.require(fresh, "cursor-only movement should create a fresh X11 frame")
    Swag.require(Memory.compare(previous.pixels.storage(), image.pixels.storage(), image.byteCount) != 0,
                 "cursor-only movement should change the composed X11 image")
}

// A failed reopen after a geometry change preserves the current connection and last delivered frame time.
#[Swag.TestTag("integration.host.linux")]
#test
{
    var source = expect Source.open({0, 0, 64, 48, false})
    var image: Image
    let fresh = expect source.grabInto(&image)
    Swag.require(fresh)
    let captureTime = source.lastFrameCaptureMicroseconds()
    let native = source.sources[0]
    let connection = native.capture.nativeConnection()
    let originalX = native.options.x
    native.options.x = cast(s32, native.capture.desktopWidth())
    var failure: Swag.Error
    discard catch source.reopen() as failure
    Swag.require(failure.value() is Errors.BadParameterError)
    Swag.require(source.lastFrameCaptureMicroseconds() == captureTime and
                 native.capture.nativeConnection() == connection)

    native.options.x = originalX
    let staleAfterFailure = expect source.grabInto(&image, copyUnchanged: false)
    Swag.require(not staleAfterFailure and source.lastFrameCaptureMicroseconds() == captureTime,
                 "a failed reopen should preserve the cached Linux frame")
    expect source.reopen()
    Swag.require(source.lastFrameCaptureMicroseconds() == 0)
    let freshAfterReopen = expect source.grabInto(&image)
    Swag.require(freshAfterReopen and source.lastFrameCaptureMicroseconds() >= captureTime)
}

// A broken XCB socket reconnects without keeping its old descriptor or SysV mapping.
#[Swag.TestTag("integration.host.linux")]
#test
{
    let descriptors = openDescriptorCount()
    let mappings = expect sharedMappingCount()
    let segments = expect sharedSegmentCount()
    var usedSharedMemory = false
    for 4
    {
        scope
        {
            var source = expect Source.open({0, 0, 64, 48, false})
            var image: Image
            discard expect source.grabInto(&image)
            let storage = image.pixels.storage()
            let capture = &source.sources[0].capture
            if capture.shmData
            {
                usedSharedMemory = true
                Swag.require((expect sharedMappingCount()) == mappings + 1)
            }
            let fileDescriptor = expect X11Capture.symbol'Linux.xcb_get_file_descriptor_fn(
                unwrap capture.library, "xcb_get_file_descriptor")
            let socket = fileDescriptor(unwrap capture.connection)
            Swag.require(socket >= 0 and Linux.shutdown(socket, 0) == 0)
            var failure: Swag.Error
            discard catch source.grabInto(&image) as failure
            Swag.require(failure.value() is Swag.SystemError)
            expect source.reopen()
            discard expect source.grabInto(&image)
            Swag.require(image.pixels.storage() == storage)
        }
        Swag.require(openDescriptorCount() == descriptors)
        Swag.require((expect sharedMappingCount()) == mappings)
    }
    for 100
    {
        if (expect sharedSegmentCount()) == segments do
            break
        Threading.Thread.sleep(1'ms)
    }
    Swag.require((expect sharedSegmentCount()) == segments)
    Console.println("X11 socket recovery: shared memory=", usedSharedMemory)
}
