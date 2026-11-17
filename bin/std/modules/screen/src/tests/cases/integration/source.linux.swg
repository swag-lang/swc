#global if #os == Swag.TargetOs.Linux
#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel

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
    var source = expect Source.openMonitor(0)
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
    Swag.require(source.lastFrameCaptureMicroseconds() == 0)
    var image = Image.create(8, 8, .RGBA8)
    let firstFresh = expect source.grabInto(&image)
    Swag.require(firstFresh)
    let firstCaptureTime = source.lastFrameCaptureMicroseconds()
    Swag.require(firstCaptureTime > 0)
    Swag.require(image.width == 320 and image.height == 240)
    Swag.require(image.pixelFormat == .BGRA8 and image.byteCount == 320 * 240 * 4)
    let storage = image.pixels.storage()
    let firstMetrics = source.metrics()
    Swag.require(firstMetrics.acquiredFrames == 1 and firstMetrics.unchangedFrames == 0)

    expect source.reopen()
    Swag.require(source.lastFrameCaptureMicroseconds() == 0)
    let secondFresh = expect source.grabInto(&image, copyUnchanged: false)
    Swag.require(secondFresh)
    Swag.require(source.lastFrameCaptureMicroseconds() >= firstCaptureTime)
    Swag.require(image.width == 320 and image.height == 240)
    Swag.require(image.pixels.storage() == storage)
    let secondMetrics = source.metrics()
    Swag.require(secondMetrics.acquiredFrames == 2 and secondMetrics.readbackMicroseconds > 0)
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
