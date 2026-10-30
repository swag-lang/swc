#global if #command == Swag.CompilerCommand.Test
#global private

using Core

func drawGaussian(cpu: *RenderCpu, source: Image, radius = 3.5'f32, mode = 0, scale = 1.0'f32, clipped = false, translated = false)->Image
{
    cpu.begin(source.width, source.height)
    let renderer: IRenderer = cpu
    defer renderer.end()
    var texture = renderer.addImage(source)
    defer renderer.removeTexture(&texture)
    var painter: Painter
    painter.begin()
    painter.setContentScale(scale)
    painter.setColorMaskFull()
    painter.clear(Argb.Blue)
    painter.setBlendingMode(.Copy)
    painter.setAntialiased(false)
    painter.setInterpolationMode(.Linear)
    if clipped do
        painter.pushClippingRect({0, 0, source.width / (2 * scale), source.height / scale})
    if translated do
        painter.translateTransform(1, 0)
    painter.setBackdropShader({width: source.width, height: source.height, radius: radius, mode: mode})
    painter.drawTexture({0, 0, source.width / scale, source.height / scale}, texture)
    if clipped do
        painter.popClippingRect()
    painter.end()
    renderer.draw(&painter)
    return cpu.surfaceImage()
}

func assertSamePixels(first, second: Image)
{
    Swag.assert(first.width == second.width and first.height == second.height)
    Swag.assert(first.pixels.count == second.pixels.count)
    Swag.assert(Memory.compare(first.pixels.storage(), second.pixels.storage(), first.pixels.count) == 0)
}

// Cache hits preserve every output byte; one changed source byte and a different kernel
// both force convolution again. The retained result is independent of a reused texture handle.
#test
{
    var source = Image.create(37, 23, .BGRA8)
    for i in source.pixels.count do
        source.pixels[i] = cast(u8, (i * 37) % 256)
    var cpu: RenderCpu
    let first = drawGaussian(&cpu, source)
    let again = drawGaussian(&cpu, source)
    Swag.assert(cpu.backdropCache[0].hits == 1)
    assertSamePixels(first, again)

    source.pixels[0] = 255
    let changed = drawGaussian(&cpu, source)
    Swag.assert(cpu.backdropCache[0].hits == 1)
    var fresh: RenderCpu
    assertSamePixels(changed, drawGaussian(&fresh, source))
    let wider = drawGaussian(&cpu, source, radius: 6)
    Swag.assert(cpu.backdropCache[0].hits == 1)
    assertSamePixels(wider, drawGaussian(&fresh, source, radius: 6))

    let vertical = drawGaussian(&cpu, source, mode: 1)
    assertSamePixels(vertical, drawGaussian(&cpu, source, mode: 1))
    Swag.assert(cpu.backdropCache[1].hits == 1)
    Swag.assert(cpu.backdropCache[0].retainedBytes() + cpu.backdropCache[1].retainedBytes() <= 2 * CpuBackdropCache.MaxBytes)
}

// Device scale and extent belong in the key. Clipped and translated draws use the general
// path and let the unused complete-rectangle cache expire.
#test
{
    var source = Image.create(40, 24, .BGRA8)
    source.fill(Argb.Red)
    var cpu:   RenderCpu
    var fresh: RenderCpu
    let first = drawGaussian(&cpu, source, scale: 1.25)
    assertSamePixels(first, drawGaussian(&cpu, source, scale: 1.25))
    Swag.assert(cpu.backdropCache[0].hits == 1)
    assertSamePixels(drawGaussian(&cpu, source, scale: 1.5), drawGaussian(&fresh, source, scale: 1.5))
    Swag.assert(cpu.backdropCache[0].hits == 1)
    assertSamePixels(drawGaussian(&cpu, source, clipped: true), drawGaussian(&fresh, source, clipped: true))
    assertSamePixels(drawGaussian(&cpu, source, translated: true), drawGaussian(&fresh, source, translated: true))
    Swag.assert(cpu.backdropCache[0].retainedBytes() == 0)

    source = Image.create(31, 19, .BGRA8)
    source.fill(Argb.Green)
    assertSamePixels(drawGaussian(&cpu, source), drawGaussian(&fresh, source))
    Swag.assert(cpu.backdropCache[0].hits == 0)
    Swag.assert(cpu.backdropCache[0].source.width == 31 and cpu.backdropCache[0].source.height == 19)
}

// Closing a backdrop releases the cached source/result images on the next ordinary frame.
#test
{
    var source = Image.create(40, 24, .BGRA8)
    source.fill(Argb.Red)
    var cpu: RenderCpu
    discard drawGaussian(&cpu, source)
    discard drawGaussian(&cpu, source)
    Swag.assert(cpu.backdropCache[0].hits == 1)
    Swag.assert(cpu.backdropCache[0].retainedBytes() == 40 * 24 * 8)

    let renderer: IRenderer = &cpu
    renderer.begin({width: 40, height: 24})
    renderer.end()
    for cache in cpu.backdropCache do
        Swag.assert(cache.retainedBytes() == 0 and not cache.valid)
}

// Both passes fit a 4K screen using useful texels, within a fixed total retention budget.
#test
{
    Swag.assert(CpuBackdropCache.acceptsSize(3840, 2160))
    Swag.assert(not CpuBackdropCache.acceptsSize(4096, 4096))
    Swag.assert(not CpuBackdropCache.acceptsSize(0, 10))
    Swag.assert(not CpuBackdropCache.acceptsSize(Swag.S32.Max, Swag.S32.Max))
}
