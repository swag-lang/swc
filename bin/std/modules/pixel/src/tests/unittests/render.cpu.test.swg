#global if #command == Swag.CompilerCommand.Test

using Swag, Core

func renderCpu(width, height: s32, painter: *Painter)->Image
{
    var renderer: RenderCpu
    renderer.begin(width, height)
    renderer.draw(painter)
    renderer.end()
    return renderer.surfaceImage()
}

// Solid geometry reaches deterministic surface pixels without a graphics context.
#test
{
    var painter: Painter
    painter.begin()
    painter.setColorMaskFull()
    painter.clear(Color.fromArgb(Argb.Zero))
    painter.fillRect({2, 3, 8, 6}, Color.fromArgb(255'u8, 230'u8, 40'u8, 20'u8))
    painter.end()

    let image = renderCpu(16, 16, &painter)
    assertImage(image, 16, 16, .BGRA8)
    assertPixel(image, 1, 3, Argb.Zero)
    assertPixel(image, 2, 3, Color.fromArgb(255'u8, 230'u8, 40'u8, 20'u8))
    assertPixel(image, 9, 8, Color.fromArgb(255'u8, 230'u8, 40'u8, 20'u8))
    assertPixel(image, 10, 8, Argb.Zero)
}

// The half-open triangle rule draws a rectangle's shared diagonal exactly once.
#test
{
    var painter: Painter
    painter.begin()
    painter.setColorMaskFull()
    painter.clear(Color.fromArgb(255'u8, 0'u8, 0'u8, 0'u8))
    painter.fillRect({2, 2, 8, 8}, Color.fromArgb(128'u8, 255'u8, 0'u8, 0'u8))
    painter.end()

    let image = renderCpu(12, 12, &painter)
    let diagonal = image.pixelColor(5, 5)
    let regular  = image.pixelColor(5, 4)
    @assert(diagonal == regular)
    @assert(diagonal.r >= 127 and diagonal.r <= 129)
}

// Nearest-neighbor texture sampling preserves the source quadrants.
#test
{
    const pixels: [16] u8 = [
        255, 0, 0, 255,   0, 255, 0, 255,
        0, 0, 255, 255,   255, 255, 255, 255]
    let source = Image.create(2, 2, .RGBA8, pixels)

    var renderer: RenderCpu
    renderer.begin(8, 8)
    let texture = renderer.addImage(source)

    var painter: Painter
    painter.begin()
    painter.setColorMaskFull()
    painter.clear(Color.fromArgb(Argb.Zero))
    painter.setInterpolationMode(.Pixel)
    painter.drawTexture({0, 0, 8, 8}, texture)
    painter.end()
    renderer.draw(&painter)

    let image = renderer.surfaceImage()
    assertPixel(image, 1, 1, Color.fromArgb(255'u8, 0'u8, 0'u8, 255'u8))
    assertPixel(image, 6, 1, Color.fromArgb(255'u8, 255'u8, 255'u8, 255'u8))
    assertPixel(image, 1, 6, Color.fromArgb(255'u8, 255'u8, 0'u8, 0'u8))
    assertPixel(image, 6, 6, Color.fromArgb(255'u8, 0'u8, 255'u8, 0'u8))
}

// Scissor and stencil clipping both reject pixels outside their active region.
#test
{
    var painter: Painter
    painter.begin()
    painter.setColorMaskFull()
    painter.clear(Color.fromArgb(Argb.Zero))
    painter.setClippingRect({2, 2, 8, 8})
    painter.startClippingRegion()
    painter.fillRect({4, 0, 4, 12}, Color.fromArgb(Argb.White))
    painter.endClippingRegion()
    painter.fillRect({0, 0, 12, 12}, Color.fromArgb(Argb.DodgerBlue))
    painter.resetClippingRegion()
    painter.resetClippingRect()
    painter.end()

    let image = renderCpu(12, 12, &painter)
    assertPixel(image, 1, 5, Argb.Zero)
    assertPixel(image, 3, 5, Argb.Zero)
    assertPixel(image, 5, 5, Argb.DodgerBlue)
    assertPixel(image, 9, 5, Argb.Zero)
}

// The CPU backend executes nested targets with stable texture handles.
#test
{
    var renderer: RenderCpu
    var outer = renderer.createRenderTarget(12, 12)
    var inner = renderer.createRenderTarget(4, 4)

    var painter: Painter
    painter.begin()
    painter.bindRenderTarget(&outer)
    painter.setColorMaskFull()
    painter.clear(Color.fromArgb(Argb.Black))
    painter.bindRenderTarget(&inner)
    painter.setColorMaskFull()
    painter.clear(Color.fromArgb(Argb.Red))
    painter.unbindRenderTarget()
    painter.setBlendingMode(.Copy)
    painter.drawTexture({4, 4, 4, 4}, inner.colorBuffer)
    painter.unbindRenderTarget()
    painter.end()
    renderer.draw(&painter)

    let image = renderer.readRenderTarget(&outer, 0, 0, 12, 12)
    assertPixel(image, 2, 2, Argb.Black)
    assertPixel(image, 5, 5, Argb.Red)
}

// paintAlpha replays geometry into alpha after overlap-safe color rendering.
#test
{
    var renderer: RenderCpu
    var target = renderer.createRenderTarget(32, 32)

    var path: LinePath
    path.start(4, 16)
    path.lineTo(28, 16)
    var pen = Pen.createSolid(Color.fromArgb(Argb.Gold), 8)
    pen.begCapStyle = .Round
    pen.endCapStyle = .Round

    var painter: Painter
    painter.begin()
    painter.bindRenderTarget(&target, true)
    painter.setColorMaskFull()
    painter.clear(Color.fromArgb(Argb.Zero))
    painter.setColorMaskColor()
    painter.setAntialiased(true)
    painter.drawPath(&path, pen)
    painter.unbindRenderTarget()
    painter.end()
    renderer.draw(&painter)

    let image = renderer.readRenderTarget(&target, 0, 0, 32, 32)
    let hit = image.pixelColor(16, 16)
    @assert(hit.r == 255 and hit.g > 200 and hit.a == 255)
    @assert(image.pixelColor(16, 2).a == 0)
}

// The built-in blur program is interpreted directly by the CPU backend.
#test
{
    var source = Image.create(9, 9, .BGRA8)
    source.clear()
    let white = (notnull source.pixels.buffer) + cast(u64) ((source.height - 4 - 1) * source.rowStride + 4 * source.bytesPerPixel)
    white[0], white[1], white[2], white[3] = 255

    var renderer: RenderCpu
    let texture = renderer.addImage(source)
    var target = renderer.createRenderTarget(9, 9)

    var painter: Painter
    painter.begin()
    painter.bindRenderTarget(&target)
    painter.setBlurShader(0, 2)
    painter.setBlendingMode(.Copy)
    painter.setColorMaskFull()
    painter.clear(Color.fromArgb(Argb.Zero))
    painter.drawTexture({0, 0, 9, 9}, texture)
    painter.setDefaultShader()
    painter.unbindRenderTarget()
    painter.end()
    renderer.draw(&painter)

    let image = renderer.readRenderTarget(&target, 0, 0, 9, 9)
    @assert(image.pixelColor(4, 4).a > 0)
    @assert(image.pixelColor(3, 4).a > 0)
    @assert(image.pixelColor(4, 3).a == 0)
}

// Clear obeys the command-stream scissor and channel mask, as glClear does.
#test
{
    var painter: Painter
    painter.begin()
    painter.setColorMaskFull()
    painter.clear(Color.fromArgb(Argb.Blue))
    painter.setClippingRect({2, 2, 4, 4})
    painter.setColorMask(true, false, false, false)
    painter.clear(Color.fromArgb(Argb.Yellow))
    painter.resetClippingRect()
    painter.end()

    let image = renderCpu(8, 8, &painter)
    assertPixel(image, 1, 3, Argb.Blue)
    assertPixel(image, 3, 3, Color.fromArgb(255'u8, 255'u8, 0'u8, 255'u8))
}

// Gradients stay in painter space while geometry follows the model transform.
#test
{
    let brush = Brush.createLinearGradient(0, 0, 8, 0, Color.fromArgb(Argb.Red), Color.fromArgb(Argb.Blue))
    var painter: Painter
    painter.begin()
    painter.setColorMaskFull()
    painter.clear(Color.fromArgb(Argb.Zero))
    painter.translateTransform(2, 1)
    painter.fillRect({0, 0, 8, 4}, brush)
    painter.end()

    let image = renderCpu(12, 8, &painter)
    assertPixel(image, 1, 2, Argb.Zero)
    let left  = image.pixelColor(2, 2)
    let right = image.pixelColor(9, 2)
    @assert(left.r > left.b)
    @assert(right.b > right.r)
}

// The built-in resolve shader averages each supersampling block and returns straight alpha.
#test
{
    var source = Image.create(4, 4, .BGRA8)
    for var y: s32; y < 4; y += 1
    {
        for var x: s32; x < 4; x += 1
        {
            let pixel = (notnull source.pixels.buffer) + cast(u64) ((3 - y) * source.rowStride + x * source.bytesPerPixel)
            if x < 2
            {
                let value: u8 = ((x + y) & 1) != 0 ? 255 : 0
                pixel[0], pixel[1], pixel[2] = value
            }
            else
            {
                pixel[0] = 255
                pixel[1] = 0
                pixel[2] = 0
            }
            pixel[3] = 255
        }
    }

    var renderer: RenderCpu
    let texture = renderer.addImage(source)
    var target = renderer.createRenderTarget(2, 2)

    var painter: Painter
    painter.begin()
    painter.bindRenderTarget(&target)
    painter.setResolveShader(2)
    painter.setColorMaskFull()
    painter.setBlendingMode(.Copy)
    painter.drawTexture({0, 0, 2, 2}, {0, 0, 4, 4}, texture)
    painter.setDefaultShader()
    painter.unbindRenderTarget()
    painter.end()
    renderer.draw(&painter)

    let image = renderer.readRenderTarget(&target, 0, 0, 2, 2)
    let gray = image.pixelColor(0, 0)
    @assert(gray.r >= 127 and gray.r <= 128 and gray.g == gray.r and gray.b == gray.r and gray.a == 255)
    assertPixel(image, 1, 0, Argb.Blue)
}
