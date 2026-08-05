#global if #command == Swag.CompilerCommand.Test

using Swag, Core

func renderCpu(width, height: s32, painter: *Painter)->Image
{
    var renderer: RenderCpu
    renderer.begin(width, height)
    let render: IRenderer = &renderer
    render.draw(painter)
    render.end()
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

    let image    = renderCpu(12, 12, &painter)
    let diagonal = image.pixelColor(5, 5)
    let regular  = image.pixelColor(5, 4)
    @assert(diagonal == regular)
    @assert(diagonal.r >= 127 and diagonal.r <= 129)
}

// Nearest-neighbor texture sampling preserves the source quadrants.
#test
{
    const pixels: [16] u8 = [
        255, 0, 0, 255, 0, 255, 0, 255,
        0, 0, 255, 255, 255, 255, 255, 255]
    let source = Image.create(2, 2, .RGBA8, pixels)

    var renderer: RenderCpu
    renderer.begin(8, 8)
    let render: IRenderer = &renderer
    var texture           = render.addImage(source)
    defer render.removeTexture(&texture)
    defer render.end()

    var painter: Painter
    painter.begin()
    painter.setColorMaskFull()
    painter.clear(Color.fromArgb(Argb.Zero))
    painter.setInterpolationMode(.Pixel)
    painter.drawTexture({0, 0, 8, 8}, texture)
    painter.end()
    render.draw(&painter)

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
    let render:   IRenderer = &renderer
    var outer               = render.createRenderTarget(12, 12)
    defer render.deleteRenderTarget(&outer)
    var inner = render.createRenderTarget(4, 4)
    defer render.deleteRenderTarget(&inner)

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
    render.draw(&painter)

    let image = render.readRenderTarget(&outer, 0, 0, 12, 12)
    assertPixel(image, 2, 2, Argb.Black)
    assertPixel(image, 5, 5, Argb.Red)
}

// paintAlpha replays geometry into alpha after overlap-safe color rendering.
#test
{
    var renderer: RenderCpu
    let render:   IRenderer = &renderer
    var target              = render.createRenderTarget(32, 32)
    defer render.deleteRenderTarget(&target)

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
    render.draw(&painter)

    let image = render.readRenderTarget(&target, 0, 0, 32, 32)
    let hit   = image.pixelColor(16, 16)
    @assert(hit.r == 255 and hit.g > 200 and hit.a == 255)
    @assert(image.pixelColor(16, 2).a == 0)
}

// The built-in blur program is interpreted directly by the CPU backend.
#test
{
    var source = Image.create(9, 9, .BGRA8)
    source.clear()
    let white = source.pixels.buffer! + cast(u64) ((source.height - 4 - 1) * source.rowStride + 4 * source.bytesPerPixel)
    white[0], white[1], white[2], white[3] = 255

    var renderer: RenderCpu
    let render:   IRenderer = &renderer
    var texture             = render.addImage(source)
    defer render.removeTexture(&texture)
    var target = render.createRenderTarget(9, 9)
    defer render.deleteRenderTarget(&target)

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
    render.draw(&painter)

    let image = render.readRenderTarget(&target, 0, 0, 9, 9)
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
    for [y] in 4
    {
        for [x] in 4
        {
            let pixel = source.pixels.buffer! + cast(u64) ((3 - y) * source.rowStride + x * source.bytesPerPixel)
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
    let render:   IRenderer = &renderer
    var texture             = render.addImage(source)
    defer render.removeTexture(&texture)
    var target = render.createRenderTarget(2, 2)
    defer render.deleteRenderTarget(&target)

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
    render.draw(&painter)

    let image = render.readRenderTarget(&target, 0, 0, 2, 2)
    let gray  = image.pixelColor(0, 0)
    @assert(gray.r >= 127 and gray.r <= 128 and gray.g == gray.r and gray.b == gray.r and gray.a == 255)
    assertPixel(image, 1, 0, Argb.Blue)
}

// A band-split rasterization stays seamless.
//
// A draw whose bounds are large enough is rasterized in horizontal row bands spread over the
// job pool, so the same scene must come out identical whether or not it was split. A target
// narrow enough to stay under the band threshold gives the serial reference at the same
// height, so the comparison spans every band boundary: a dropped seam row, a doubly blended
// one, or an overlap scratch plane reset over the wrong rows all break it.
#test
{
    // A test process starts no pool, and a single worker keeps parallelFor serial, so the
    // band split needs an explicit multi-worker pool to be reached at all.
    if Jobs.workerCount() < 2 do
        discard expect Jobs.initialize(4)

    const Height = 512
    const Narrow = 8     // Columns the two renders have in common, and the serial width.
    const Wide   = 1024

    // Drawn once, rasterized into both targets: the geometry is in device pixels, so a pixel
    // of one render addresses the very same shape samples as that pixel of the other. The
    // rounded corners and the two overlapping translucent paths make the shared columns carry
    // per-row coverage rather than one flat color.
    var painter: Painter
    painter.begin()
    painter.setColorMaskFull()
    painter.clear(Color.fromArgb(255'u8, 0'u8, 0'u8, 0'u8))
    painter.fillRect(0, 0, 1024.0, 512.0, Color.fromArgb(128'u8, 255'u8, 0'u8, 0'u8))
    painter.fillRoundRect(0, 0, 960.0, 480.0, 24, 24, Color.fromArgb(128'u8, 0'u8, 255'u8, 0'u8))
    painter.fillRoundRect(0, 16, 900.0, 460.0, 40, 40, Color.fromArgb(96'u8, 0'u8, 0'u8, 255'u8))
    painter.end()

    let serial = renderCpu(Narrow, Height, &painter)
    let banded = renderCpu(Wide, Height, &painter)
    assertImage(serial, Narrow, Height, .BGRA8)
    assertImage(banded, Wide, Height, .BGRA8)

    for var y = 0; y < Height; y += 1
    {
        for var x = 0; x < Narrow; x += 1 do
            @assert(serial.pixelColor(x, y) == banded.pixelColor(x, y))
    }
}
