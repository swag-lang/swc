#global if #os == Swag.TargetOs.Windows
#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel

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
            pixels[at] = cast(u8, y * 8 + x)
            pixels[at + 1] = 0x31
            pixels[at + 2] = 0x52
            pixels[at + 3] = 0xFF
        }
    }
    let mapped = D3D11_MAPPED_SUBRESOURCE{cast(*void, pixels.storage()), 40, 0}
    var image = Image.create(8, 8, .BGRA8)
    Memory.set(image.pixels.storage(), 0xAA, image.byteCount)
    native.copyMappedRect(&image, &mapped, 0, 0, RECT{0, 0, 2, 2})
    native.copyMappedRect(&image, &mapped, 0, 0, RECT{6, 6, 8, 8})
    Swag.require(native.metrics.copiedPixels == 8)
    for y in 8'u64
    {
        for x in 8'u64
        {
            let at = (7 - y) * 32 + x * 4
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
    let bounds = monitors[0].physicalBounds
    var source = expect Source.open({cast(s32, bounds.x), cast(s32, bounds.y),
                                     cast(s32, bounds.width), cast(s32, bounds.height), false})
    let native = source.sources[0]
    Swag.require(expect native.beginGrab())
    Swag.require(native.pending)
    native.abortGrab()
    Swag.require(not native.pending and native.pendingResource == null and native.pendingTexture == null)
    let originalX = native.options.x
    native.options.x = Env.getSystemMetric(.DesktopX) + Env.getSystemMetric(.DesktopWidth) + 32
    var rejected = false
    catch native.reopen() { rejected = true }
    Swag.require(rejected, "reopening an unavailable output should fail")
    rejected = false
    discard catch native.beginGrab() { rejected = true }
    Swag.require(rejected, "a failed reopen should leave a recoverable source")
    native.options.x = originalX
    expect native.reopen()
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
    Swag.require(expect source.grabInto(&image, copyUnchanged: false,
                                        updateChangedOnly: true))
    let firstMetrics = source.metrics()
    Swag.require(firstMetrics.maxReadbackMicroseconds > 0 and
                 firstMetrics.maxReadbackMicroseconds <= firstMetrics.readbackMicroseconds and
                 firstMetrics.maxAcquireMicroseconds <= firstMetrics.acquireMicroseconds)
    for 12
    {
        discard expect source.grabInto(&image, copyUnchanged: false,
                                       updateChangedOnly: true)
        Swag.require(Memory.compare(image.pixels.storage(), source.composed.pixels.storage(),
                                    image.byteCount) == 0,
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
    let first = monitors[0].physicalBounds
    let second = monitors[1].physicalBounds
    let left = cast(s32, Math.min(first.x, second.x))
    let right = cast(s32, Math.max(first.right(), second.right()))
    let top = cast(s32, Math.max(first.y, second.y))
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
    let x = Env.getSystemMetric(.DesktopX)
    let y = Env.getSystemMetric(.DesktopY)
    let width = Env.getSystemMetric(.DesktopWidth)
    let height = Env.getSystemMetric(.DesktopHeight)
    if width <= 0 or height <= 0 do
        return
    var source = expect Source.open({x, y, width, height, false})
    var image: Image
    Swag.require(expect source.grabInto(&image, copyUnchanged: false,
                                        updateChangedOnly: true))
    for native in source.sources do
        Swag.require(not native.pending)
    Swag.require(image.width == width and image.height == height)
    Swag.require(image.pixelFormat == .BGRA8)
    if source.sources.count > 1
    {
        for 12
        {
            discard expect source.grabInto(&image, copyUnchanged: false,
                                           updateChangedOnly: true)
            for native in source.sources do
                Swag.require(not native.pending)
            Swag.require(Memory.compare(image.pixels.storage(), source.composed.pixels.storage(),
                                        image.byteCount) == 0,
                         "incremental output differs from the composed desktop")
        }
    }
}
