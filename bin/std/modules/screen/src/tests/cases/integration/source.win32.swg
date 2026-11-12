#global if #os == Swag.TargetOs.Windows
#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel

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
    var image: Image
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
