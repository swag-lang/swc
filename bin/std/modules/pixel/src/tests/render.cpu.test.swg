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

// A nearly collinear viewport-wide polygon must not corrupt the geometry recorded after it.
#test
{
    let strip = [Vector2{0, 100}, Vector2{1400, 100}, Vector2{1398, 102}, Vector2{2, 102}]

    var painter: Painter
    painter.begin()
    painter.setColorMaskFull()
    painter.clear(Color.fromArgb(Argb.Zero))
    painter.fillPolygon(strip, Brush.createSolid(Color.fromArgb(Argb.Red)))
    painter.fillRect({100, 800, 120, 24}, Color.fromArgb(Argb.DodgerBlue))
    painter.end()

    let image = renderCpu(1400, 1000, &painter)
    assertPixel(image, 700, 101, Argb.Red)
    assertPixel(image, 700, 150, Argb.Zero)
    assertPixel(image, 120, 810, Argb.DodgerBlue)
    assertPixel(image, 120, 110, Argb.Zero)
}

// Constant vertex colors produce a uniform blend across both triangles of a filled rectangle.
#test
{
    const Dst = Color.fromArgb(255'u8, 64'u8, 128'u8, 192'u8)
    const Src = Color.fromArgb(128'u8, 192'u8, 64'u8, 128'u8)

    var cpu:      RenderCpu
    let renderer: IRenderer = &cpu
    renderer.init()
    var target = renderer.createRenderTarget(72, 12)
    defer renderer.deleteRenderTarget(&target)

    var painter = Painter.create(renderer)
    painter.begin()
    painter.bindRenderTarget(&target)
    painter.setColorMaskFull()
    painter.clear(Color.fromArgb(Argb.Zero))
    painter.setBlendingMode(.Copy)
    painter.fillRect({60, 0, 12, 12}, Dst)
    painter.setBlendingMode(.ColorDodge)
    painter.fillRect({60, 0, 12, 12}, Src)
    painter.unbindRenderTarget()
    painter.end()
    renderer.draw(&painter)

    let image    = renderer.readRenderTarget(&target, 0, 0, 72, 12)
    let expected = image.pixelColor(60, 0)
    for var y = 0; y < 12; y += 1
    {
        for var x = 60; x < 72; x += 1 do
            assertPixel(image, x, y, expected)
    }
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

// The separable modes follow the standard per-channel blend functions, then apply source-over
// coverage. The source is translucent so this distinguishes them from raw component equations.
#test
{
    const modes:    [11] BlendingMode = [.Multiply, .Screen, .Overlay, .Darken, .Lighten, .ColorDodge, .ColorBurn, .HardLight, .SoftLight, .Difference, .Exclusion]
    const expected: [11] Color        = [Color.fromArgb(255'u8, 56'u8, 79'u8, 144'u8),
                                         Color.fromArgb(255'u8, 136'u8, 143'u8, 207'u8),
                                         Color.fromArgb(255'u8, 80'u8, 96'u8, 192'u8),
                                         Color.fromArgb(255'u8, 64'u8, 95'u8, 159'u8),
                                         Color.fromArgb(255'u8, 128'u8, 128'u8, 192'u8),
                                         Color.fromArgb(255'u8, 159'u8, 149'u8, 223'u8),
                                         Color.fromArgb(255'u8, 32'u8, 63'u8, 160'u8),
                                         Color.fromArgb(255'u8, 112'u8, 96'u8, 192'u8),
                                         Color.fromArgb(255'u8, 80'u8, 112'u8, 192'u8),
                                         Color.fromArgb(255'u8, 96'u8, 95'u8, 127'u8),
                                         Color.fromArgb(255'u8, 111'u8, 127'u8, 159'u8)]

    const Dst = Color.fromArgb(255'u8, 64'u8, 128'u8, 192'u8)
    const Src = Color.fromArgb(128'u8, 192'u8, 64'u8, 128'u8)

    var painter: Painter
    painter.begin()
    painter.setColorMaskFull()
    for mode, idx in modes
    {
        let x = cast(f32) idx * 2.0
        painter.setBlendingMode(.Copy)
        painter.fillRect(x, 0, 2, 2, Dst)
        painter.setBlendingMode(mode)
        painter.fillRect(x, 0, 2, 2, Src)
    }

    painter.end()

    let image = renderCpu(22, 2, &painter)
    for value, idx in expected do
        assertPixel(image, cast(s32) idx * 2, 0, value)
}

// The non-separable modes transfer hue, saturation, or luminosity across the complete color,
// then use the same source-over coverage as the separable modes.
#test
{
    const modes:    [4] BlendingMode = [.Hue, .Saturation, .Color, .Luminosity]
    const expected: [4] Color        = [Color.fromArgb(255'u8, 148'u8, 74'u8, 119'u8),
                                        Color.fromArgb(255'u8, 37'u8, 117'u8, 189'u8),
                                        Color.fromArgb(255'u8, 135'u8, 80'u8, 123'u8),
                                        Color.fromArgb(255'u8, 44'u8, 134'u8, 214'u8)]

    const Dst = Color.fromArgb(255'u8, 30'u8, 120'u8, 200'u8)
    const Src = Color.fromArgb(160'u8, 220'u8, 80'u8, 100'u8)

    var painter: Painter
    painter.begin()
    painter.setColorMaskFull()
    for mode, idx in modes
    {
        let x = cast(f32) idx * 2.0
        painter.setBlendingMode(.Copy)
        painter.fillRect(x, 0, 2, 2, Dst)
        painter.setBlendingMode(mode)
        painter.fillRect(x, 0, 2, 2, Src)
    }

    painter.end()

    let image = renderCpu(8, 2, &painter)
    for value, idx in expected do
        assertPixel(image, cast(s32) idx * 2, 0, value)
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

// A one-to-one BGRA sub-rectangle copy preserves every source byte and its destination offset.
#test
{
    var source = Image.create(6, 4, .BGRA8)
    for y in source.height
    {
        for x in source.width
        {
            let pixel = source.pixels.buffer! + cast(u64) ((source.height - y - 1) * source.rowStride + x * 4)
            pixel[0] = cast(u8) (20 + x * 17)
            pixel[1] = cast(u8) (30 + y * 31)
            pixel[2] = cast(u8) (40 + x * 7 + y * 5)
            pixel[3] = cast(u8) (80 + x * 11 + y * 13)
        }
    }

    var renderer: RenderCpu
    renderer.begin(8, 6)
    let render: IRenderer = &renderer
    var texture           = render.addImage(source)
    defer render.removeTexture(&texture)
    defer render.end()

    var painter: Painter
    painter.begin()
    painter.setColorMaskFull()
    painter.clear(Color.fromArgb(Argb.Zero))
    painter.setInterpolationMode(.Pixel)
    painter.setBlendingMode(.Copy)
    painter.drawTexture({2, 2, 4, 3}, {1, 0, 4, 3}, texture)
    painter.end()
    render.draw(&painter)

    let image = renderer.surfaceImage()
    for y in 3's32
    {
        for x in 4's32 do
            @assert(image.pixelColor(x + 2, y + 2) == source.pixelColor(x + 1, y))
    }

    assertPixel(image, 1, 2, Argb.Zero)
    assertPixel(image, 6, 4, Argb.Zero)
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

    // Geometry recorded before the target bind belongs to the parent surface. Replaying it
    // into the target's alpha pass would turn untouched transparent pixels opaque.
    painter.fillRect(0, 0, 32, 32, Color.fromArgb(Argb.White))
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

// Packed clear and solid spans preserve masked channels through their non-vector tail.
#test
{
    var painter: Painter
    painter.begin()
    painter.setColorMaskFull()
    painter.clear(Color.fromArgb(37'u8, 10'u8, 20'u8, 30'u8))
    painter.setColorMaskColor()
    painter.clear(Color.fromArgb(200'u8, 90'u8, 80'u8, 70'u8))
    painter.setColorMaskAlpha()
    painter.fillRect({1, 0, 7, 3}, Color.fromArgb(Argb.White))
    painter.end()

    let image = renderCpu(9, 3, &painter)
    for y in 3
    {
        assertPixel(image, 0, y, Color.fromArgb(37'u8, 90'u8, 80'u8, 70'u8))
        for var x = 1; x < 8; x += 1 do
            assertPixel(image, x, y, Color.fromArgb(255'u8, 90'u8, 80'u8, 70'u8))
        assertPixel(image, 8, y, Color.fromArgb(37'u8, 90'u8, 80'u8, 70'u8))
    }
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
    for y in 4
    {
        for x in 4
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
