#global if #os == Swag.TargetOs.Windows
#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel

// Cursor-only motion produces a new image without leaving the previous cursor behind.
#[Swag.TestTag("integration.host.windows")]
#test
{
    let monitors = Env.getMonitors()
    if not monitors.count do
        return
    let bounds = monitors[0].physicalBounds
    if bounds.width < 64 or bounds.height < 64 do
        return
    let monitorX      = cast(s32, bounds.x)
    let monitorY      = cast(s32, bounds.y)
    let monitorWidth  = cast(s32, bounds.width)
    let monitorHeight = cast(s32, bounds.height)
    let captureWidth  = Math.min(256's32, monitorWidth)
    let captureHeight = Math.min(256's32, monitorHeight)
    let captureX      = monitorX + (monitorWidth - captureWidth) / 2
    let captureY      = monitorY + (monitorHeight - captureHeight) / 2

    var cursor: CURSORINFO
    cursor.cbSize = #sizeof(CURSORINFO)
    if not GetCursorInfo(&cursor) or not (cursor.flags & CURSOR_SHOWING) do
        return
    let originalX = cursor.ptScreenPos.x
    let originalY = cursor.ptScreenPos.y
    defer SetCursorPos(originalX, originalY)

    var source = expect Source.open({captureX, captureY, captureWidth, captureHeight, true})
    SetCursorPos(captureX + captureWidth / 4, captureY + captureHeight / 4)
    var image: Image
    Swag.require(expect source.grabInto(&image))
    var previous = Image.create(image.width, image.height, image.pixelFormat)
    Memory.copy(previous.pixels.storage(), image.pixels.storage(), image.byteCount)

    SetCursorPos(captureX + captureWidth * 3 / 4, captureY + captureHeight * 3 / 4)
    let fresh = expect source.grabInto(&image, copyUnchanged: false)
    Swag.require(fresh, "cursor movement should make the captured image fresh")
    Swag.require(Memory.compare(previous.pixels.storage(), image.pixels.storage(), image.byteCount) != 0,
                 "moving the cursor should change the captured image")
    Swag.require(Memory.compare(image.pixels.storage(), cast([*] u8, unwrap source.cursorPixels), image.byteCount) == 0,
                 "moving the cursor should redraw from cursorless desktop pixels")

    image = Image.create(1, 1, .BGRA8)
    discard expect source.grabInto(&image, copyUnchanged: false)
    Swag.require(image.width == captureWidth and image.height == captureHeight)
    Swag.require(Memory.compare(image.pixels.storage(), cast([*] u8, source.cursorPixels), image.byteCount) == 0,
                 "a replacement target should receive the current cursor-composited frame")
}

// Split readbacks copy only the selected top-down regions into bottom-up image storage.
#[Swag.TestTag("integration.host.windows")]
#test
{
    var native: NativeSource
    native.options = {0, 0, 8, 8, false}
    var pixels: Array'u8
    pixels.resize(8 * 40)
    for y in 8'u64
    {
        for x in 8'u64
        {
            let at = y * 40 + x * 4
            pixels[at]     = cast(u8, y * 8 + x)
            pixels[at + 1] = 0x31
            pixels[at + 2] = 0x52
            pixels[at + 3] = 0xFF
        }
    }

    let mapped = D3D11_MAPPED_SUBRESOURCE{cast(*void, pixels.storage()), 40, 0}
    var image  = Image.create(8, 8, .BGRA8)
    Memory.set(image.pixels.storage(), 0xAA, image.byteCount)
    native.copyMappedRect(&image, &mapped, 0, 0, RECT{0, 0, 2, 2})
    native.copyMappedRect(&image, &mapped, 0, 0, RECT{6, 6, 8, 8})
    Swag.require(native.metrics.copiedPixels == 8)
    for y in 8'u64
    {
        for x in 8'u64
        {
            let at       = (7 - y) * 32 + x * 4
            let selected = (x < 2 and y < 2) or (x >= 6 and y >= 6)
            Swag.require(image.pixels[at] == (selected ? cast(u8, y * 8 + x) : 0xAA'u8) and
                         image.pixels[at + 1] == (selected ? 0x31'u8 : 0xAA'u8))
        }
    }
}

// Aborting an in-flight readback releases its DXGI frame and texture.
#[Swag.TestTag("integration.host.windows")]
#test
{
    let monitors = Env.getMonitors()
    if not monitors.count do
        return
    var source        = expect Source.openMonitor(0)
    let selection     = source.captureOptions()
    let monitorBounds = monitors[0].physicalBounds
    Swag.require(selection.x == cast(s32, monitorBounds.x) and
                 selection.y == cast(s32, monitorBounds.y) and
                 selection.width == cast(s32, monitorBounds.width) and
                 selection.height == cast(s32, monitorBounds.height))
    let pointSource = expect Source.openMonitorAt({monitorBounds.x + monitorBounds.width / 2,
                                                   monitorBounds.y + monitorBounds.height / 2})
    let pointOptions = pointSource.captureOptions()
    Swag.require(pointOptions.x == selection.x and
                 pointOptions.y == selection.y and
                 pointOptions.width == selection.width and
                 pointOptions.height == selection.height)
    let native = source.sources[0]
    Swag.require(expect native.beginGrab())
    Swag.require(native.pending)
    native.abortGrab()
    Swag.require(not native.pending and native.pendingResource == null and native.pendingTexture == null)
    var image: Image
    let fresh = expect source.grabInto(&image)
    Swag.require(fresh)
    let lastCaptureTime = source.lastFrameCaptureMicroseconds()
    Swag.require(lastCaptureTime > 0)
    let lastPresentationTime = source.lastFramePresentationMicroseconds()
    Swag.require(lastPresentationTime > 0)
    let originalX = native.options.x
    native.options.x = Env.getSystemMetric(.DesktopX) + Env.getSystemMetric(.DesktopWidth) + 32
    var rejected = false
    catch source.reopen() { rejected = true }
    Swag.require(rejected, "reopening an unavailable output should fail")
    Swag.require(source.lastFrameCaptureMicroseconds() == lastCaptureTime and
                 source.lastFramePresentationMicroseconds() == lastPresentationTime)
    rejected = false
    discard catch native.beginGrab() { rejected = true }
    Swag.require(rejected, "a failed reopen should leave a recoverable source")
    native.options.x = originalX
    expect source.reopen()
    Swag.require(source.lastFrameCaptureMicroseconds() == 0)
    Swag.require(source.lastFramePresentationMicroseconds() == 0)
    Swag.require(expect native.beginGrab())
    native.abortGrab()
}

// A single output reuses its composed frame and updates a stable caller image.
#[Swag.TestTag("integration.host.windows")]
#test
{
    let monitors = Env.getMonitors()
    if not monitors.count do
        return
    let bounds = monitors[0].physicalBounds
    var source = expect Source.open({cast(s32, bounds.x), cast(s32, bounds.y),
                                     cast(s32, bounds.width), cast(s32, bounds.height), false})
    var image: Image
    let firstFresh = expect source.grabInto(&image, copyUnchanged: false, updateChangedOnly: true)
    Swag.require(firstFresh and source.lastFrameCaptureMicroseconds() > 0)
    Swag.require(source.lastFramePresentationMicroseconds() > 0 and
                 source.lastFramePresentationMicroseconds() <= source.lastFrameCaptureMicroseconds())
    var lastCaptureTime = source.lastFrameCaptureMicroseconds()
    let firstMetrics    = source.metrics()
    Swag.require(firstMetrics.maxReadbackMicroseconds > 0 and
                 firstMetrics.maxReadbackMicroseconds <= firstMetrics.readbackMicroseconds and
                 firstMetrics.maxAcquireMicroseconds <= firstMetrics.acquireMicroseconds)
    let firstCaptureTime = source.lastFrameCaptureMicroseconds()
    source.resetMetrics()
    let resetMetrics = source.metrics()
    Swag.require(resetMetrics.acquiredFrames == 0 and
                 resetMetrics.unchangedFrames == 0 and
                 resetMetrics.acquireMicroseconds == 0 and
                 resetMetrics.readbackMicroseconds == 0 and
                 resetMetrics.copyMicroseconds == 0 and
                 resetMetrics.composeMicroseconds == 0 and
                 resetMetrics.changeDetectionMicroseconds == 0 and
                 resetMetrics.copiedPixels == 0 and
                 resetMetrics.mirroredPixels == 0)
    Swag.require(source.lastFrameCaptureMicroseconds() == firstCaptureTime)
    for 12
    {
        let fresh       = expect source.grabInto(&image, copyUnchanged: false, updateChangedOnly: true)
        let captureTime = source.lastFrameCaptureMicroseconds()
        Swag.require(captureTime >= lastCaptureTime and (not fresh or captureTime > 0))
        lastCaptureTime = captureTime
        Swag.require(Memory.compare(image.pixels.storage(), source.composed.pixels.storage(), image.byteCount) == 0,
                     "incremental output differs from the composed monitor")
    }
}

// One source composes the overlapping strip from adjacent physical monitors.
#[Swag.TestTag("integration.host.windows")]
#test
{
    let monitors = Env.getMonitors()
    if monitors.count < 2 do
        return
    let first  = monitors[0].physicalBounds
    let second = monitors[1].physicalBounds
    let left   = cast(s32, Math.min(first.x, second.x))
    let right  = cast(s32, Math.max(first.right(), second.right()))
    let top    = cast(s32, Math.max(first.y, second.y))
    let bottom = cast(s32, Math.min(first.bottom(), second.bottom()))
    if bottom <= top do
        return

    var source = expect Source.open({left, top, right - left, Math.min(bottom - top, 128), false})
    Swag.require(source.sources.count >= 2 and
                 source.sources[0].device == source.sources[1].device and
                 source.sources[0].context == source.sources[1].context)
    var image: Image
    discard expect source.grabInto(&image)
    expect source.reopen()
    Swag.require(source.sources[0].device == source.sources[1].device and
                 source.sources[0].context == source.sources[1].context)
    discard expect source.grabInto(&image)
    for native in source.sources do
        Swag.require(not native.pending)
    Swag.require(image.width == right - left and image.height == Math.min(bottom - top, 128))
    Swag.require(image.pixelFormat == .BGRA8 and image.byteCount > 0)
    var untouched = Image.create(image.width, image.height, .BGRA8)
    Memory.set(untouched.pixels.storage(), 0x5A, untouched.byteCount)
    let changed = expect source.grabInto(&untouched, copyUnchanged: false)
    for native in source.sources do
        Swag.require(not native.pending)
    if not changed
    {
        for byte in untouched.pixels do
            Swag.require(byte == 0x5A)
    }
}

// The virtual desktop may contain empty strips between vertically offset monitors.
#[Swag.TestTag("integration.host.windows")]
#test
{
    let monitors = Env.getMonitors()
    if not monitors.count do
        return
    let first  = monitors[0].physicalBounds
    var left   = first.x
    var top    = first.y
    var right  = first.right()
    var bottom = first.bottom()
    for monitor in monitors
    {
        let bounds = monitor.physicalBounds
        left   = Math.min(left, bounds.x)
        top    = Math.min(top, bounds.y)
        right  = Math.max(right, bounds.right())
        bottom = Math.max(bottom, bounds.bottom())
    }

    let width     = cast(s32, right - left)
    let height    = cast(s32, bottom - top)
    var source    = expect Source.openDesktop()
    let selection = source.captureOptions()
    Swag.require(selection.x == cast(s32, left) and
                 selection.y == cast(s32, top) and
                 selection.width == width and
                 selection.height == height)
    var image: Image
    Swag.require(expect source.grabInto(&image, copyUnchanged: false, updateChangedOnly: true))
    for native in source.sources do
        Swag.require(not native.pending)
    Swag.require(image.width == width and image.height == height)
    Swag.require(image.pixelFormat == .BGRA8)
    if source.sources.count > 1
    {
        for 12
        {
            discard expect source.grabInto(&image, copyUnchanged: false, updateChangedOnly: true)
            for native in source.sources do
                Swag.require(not native.pending)
            Swag.require(Memory.compare(image.pixels.storage(), source.composed.pixels.storage(), image.byteCount) == 0,
                         "incremental output differs from the composed desktop")
        }
    }
}

// The first picture of a new source is the desktop. A duplication can hand over a surface that
// was never presented to before its first real frame; taken as a picture, it opened most
// recordings on black.
#[Swag.TestTag("integration.host.windows")]
#test
{
    let monitors = Env.getMonitors()
    if not monitors.count do
        return
    let bounds = monitors[0].physicalBounds
    let width  = Math.min(cast(s32, bounds.width), 320)
    let height = Math.min(cast(s32, bounds.height), 181)
    for 12
    {
        var source = expect Source.open({cast(s32, bounds.x), cast(s32, bounds.y), width, height, false})
        var image: Image
        Swag.require(expect source.grabInto(&image, copyUnchanged: false, updateChangedOnly: true))
        Swag.require(image.width == width and image.height == height)

        // A presented desktop pixel is opaque; the empty surface is zero throughout.
        var opaque = 0'u64
        for pixel in cast(u64, width) * cast(u64, height) where image.pixels[pixel * 4 + 3] != 0 do
            opaque += 1
        Swag.require(opaque != 0, "the first frame of a screen source is empty")
    }
}
