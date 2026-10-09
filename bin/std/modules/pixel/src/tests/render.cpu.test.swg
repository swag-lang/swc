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

// Alpha is an exact byte-weighted average, including integral results at float rounding boundaries.
#test
{
    const Sources = [Color.fromArgb(85'u8, 110'u8, 110'u8, 110'u8),
                     Color.fromArgb(165'u8, 96'u8, 96'u8, 106'u8),
                     Color.fromArgb(127'u8, 132'u8, 132'u8, 144'u8),
                     Color.fromArgb(85'u8, 110'u8, 110'u8, 110'u8),
                     Color.fromArgb(0'u8, 255'u8, 255'u8, 255'u8),
                     Color.fromArgb(255'u8, 3'u8, 5'u8, 7'u8),
                     Color.fromArgb(18'u8, 200'u8, 200'u8, 200'u8),
                     Color.fromArgb(128'u8, 0'u8, 255'u8, 0'u8),
                     Color.fromArgb(127'u8, 115'u8, 115'u8, 115'u8)]
    const Destinations = [Color.fromArgb(255'u8, 53'u8, 53'u8, 53'u8),
                          Color.fromArgb(255'u8, 32'u8, 32'u8, 38'u8),
                          Color.fromArgb(255'u8, 132'u8, 132'u8, 144'u8),
                          Color.fromArgb(70'u8, 53'u8, 53'u8, 53'u8),
                          Color.fromArgb(68'u8, 17'u8, 18'u8, 19'u8),
                          Color.fromArgb(68'u8, 17'u8, 18'u8, 19'u8),
                          Color.fromArgb(70'u8, 20'u8, 20'u8, 20'u8),
                          Color.fromArgb(255'u8, 255'u8, 0'u8, 255'u8),
                          Color.fromArgb(255'u8, 115'u8, 115'u8, 115'u8)]

    // Independent rational results: 110/3 + 2*53/3 = 72; 106*11/17 + 38*6/17 = 82.
    // The 18/255 case has a fractional result and keeps truncation, while equal colors are fixed.
    const Expected = [Color.fromArgb(255'u8, 72'u8, 72'u8, 72'u8),
                      Color.fromArgb(255'u8, 73'u8, 73'u8, 82'u8),
                      Color.fromArgb(255'u8, 132'u8, 132'u8, 144'u8),
                      Color.fromArgb(131'u8, 72'u8, 72'u8, 72'u8),
                      Color.fromArgb(68'u8, 17'u8, 18'u8, 19'u8),
                      Color.fromArgb(255'u8, 3'u8, 5'u8, 7'u8),
                      Color.fromArgb(83'u8, 32'u8, 32'u8, 32'u8),
                      Color.fromArgb(255'u8, 127'u8, 128'u8, 127'u8),
                      Color.fromArgb(255'u8, 115'u8, 115'u8, 115'u8)]

    for mask in 3
    {
        for source, index in Sources
        {
            var painter: Painter
            painter.begin()
            painter.setColorMaskFull()
            painter.clear(Destinations[index])
            if mask == 0 do
                painter.setColorMaskColor()
            elif mask == 2 do
                painter.setColorMask(true, false, false, true)
            painter.setAntialiased(false)
            painter.fillRect(0, 0, 7, 2, source)
            painter.end()

            var expected = Expected[index]
            if mask == 0
            {
                expected.a = Destinations[index].a
            }
            elif mask == 2
            {
                expected.g = Destinations[index].g
                expected.b = Destinations[index].b
            }

            let image = renderCpu(7, 2, &painter)
            for x in 7 do
                assertPixel(image, x, 0, expected)
        }
    }
}

// Overlap-safe strokes use the same exact byte weights as ordinary Alpha rendering.
#test
{
    const Sources = [Color.fromArgb(85'u8, 110'u8, 110'u8, 110'u8),
                     Color.fromArgb(165'u8, 96'u8, 96'u8, 106'u8),
                     Color.fromArgb(127'u8, 132'u8, 132'u8, 144'u8)]
    const Destinations = [Color.fromArgb(255'u8, 53'u8, 53'u8, 53'u8),
                          Color.fromArgb(255'u8, 32'u8, 32'u8, 38'u8),
                          Color.fromArgb(255'u8, 132'u8, 132'u8, 144'u8)]
    const Expected = [Color.fromRgb(72, 72, 72), Color.fromRgb(73, 73, 82), Color.fromRgb(132, 132, 144)]
    for source, index in Sources
    {
        var painter: Painter
        painter.begin()
        painter.setColorMaskFull()
        painter.clear(Destinations[index])
        painter.setColorMaskColor()
        painter.setAntialiased(false)
        painter.drawLine(1, 2, 7, 2, Pen.createSolid(source, 2))
        painter.end()

        let image = renderCpu(8, 4, &painter)
        let value = image.pixelColor(4, 2)
        Swag.assert(value.r == Expected[index].r and
                    value.g == Expected[index].g and
                    value.b == Expected[index].b)
    }
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
    for y in 12
    {
        for x in 60 until 72 do
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
    Swag.assert(diagonal == regular)
    Swag.assert(diagonal.r >= 127 and diagonal.r <= 129)
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
        let x = cast(f32, idx) * 2.0
        painter.setBlendingMode(.Copy)
        painter.fillRect(x, 0, 2, 2, Dst)
        painter.setBlendingMode(mode)
        painter.fillRect(x, 0, 2, 2, Src)
    }

    painter.end()

    let image = renderCpu(22, 2, &painter)
    for value, idx in expected do
        assertPixel(image, cast(s32, idx) * 2, 0, value)
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
        let x = cast(f32, idx) * 2.0
        painter.setBlendingMode(.Copy)
        painter.fillRect(x, 0, 2, 2, Dst)
        painter.setBlendingMode(mode)
        painter.fillRect(x, 0, 2, 2, Src)
    }

    painter.end()

    let image = renderCpu(8, 2, &painter)
    for value, idx in expected do
        assertPixel(image, cast(s32, idx) * 2, 0, value)
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
    var texture = render.addImage(source)
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
            let pixel = source.pixels.storage() + cast(u64, ((source.height - y - 1) * source.rowStride + x * 4))
            pixel[0] = cast(u8, (20 + x * 17))
            pixel[1] = cast(u8, (30 + y * 31))
            pixel[2] = cast(u8, (40 + x * 7 + y * 5))
            pixel[3] = cast(u8, (80 + x * 11 + y * 13))
        }
    }

    var renderer: RenderCpu
    renderer.begin(8, 6)
    let render: IRenderer = &renderer
    var texture = render.addImage(source)
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
            Swag.assert(image.pixelColor(x + 2, y + 2) == source.pixelColor(x + 1, y))
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
    var outer = render.createRenderTarget(12, 12)
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
    var target = render.createRenderTarget(32, 32)
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
    Swag.assert(hit.r == 255 and hit.g > 200 and hit.a == 255)
    Swag.assert(image.pixelColor(16, 2).a == 0)
}

// The built-in blur program is interpreted directly by the CPU backend.
#test
{
    var source = Image.create(9, 9, .BGRA8)
    source.clear()
    let white = source.pixels.storage() + cast(u64, ((source.height - 4 - 1) * source.rowStride + 4 * source.bytesPerPixel))
    white[0], white[1], white[2], white[3] = 255

    var renderer: RenderCpu
    let render:   IRenderer = &renderer
    var texture = render.addImage(source)
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
    Swag.assert(image.pixelColor(4, 4).a > 0)
    Swag.assert(image.pixelColor(3, 4).a > 0)
    Swag.assert(image.pixelColor(4, 3).a == 0)
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
    Swag.assert(left.r > left.b)
    Swag.assert(right.b > right.r)
}

// The built-in resolve shader averages each supersampling block and returns straight alpha.
#test
{
    var source = Image.create(4, 4, .BGRA8)
    for y in 4
    {
        for x in 4
        {
            let pixel = source.pixels.storage() + cast(u64, ((3 - y) * source.rowStride + x * source.bytesPerPixel))
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
    var texture = render.addImage(source)
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
    Swag.assert(gray.r >= 127 and gray.r <= 128 and gray.g == gray.r and gray.b == gray.r and gray.a == 255)
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
    // Compile-time execution keeps every partition on the calling thread, so the band split
    // is only reachable in a process that actually runs workers.
    Swag.setWorkerCount(4)
    if Swag.workerCount() < 2 do
        return

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

    for y in Height
    {
        for x in Narrow do
            Swag.assert(serial.pixelColor(x, y) == banded.pixelColor(x, y))
    }
}

// A circle about (50, 50) of radius 40, walked clockwise or anticlockwise in page space.
func circlePathList(anticlockwise: bool)->LinePathList
{
    var result: retval
    with let path = result.newPath()
    {
        .start(90, 50)
        if anticlockwise
        {
            .bezierTo(50, 10, 90, 27.908, 72.092, 10)
            .bezierTo(10, 50, 27.908, 10, 10, 27.908)
            .bezierTo(50, 90, 10, 72.092, 27.908, 90)
            .bezierTo(90, 50, 72.092, 90, 90, 72.092)
        }
        else
        {
            .bezierTo(50, 90, 90, 72.092, 72.092, 90)
            .bezierTo(10, 50, 27.908, 90, 10, 72.092)
            .bezierTo(50, 10, 10, 27.908, 27.908, 10)
            .bezierTo(90, 50, 72.092, 10, 90, 27.908)
        }

        .close()
    }

    return result
}

// A ruled fill does not depend on the direction its contour runs: a lone anticlockwise contour
// gets the same antialiased edge as the clockwise one, not a hard edge a band further out.
#test
{
    var images: [2] Image
    for anticlockwise, index in [false, true]
    {
        var circle = circlePathList(anticlockwise)
        var painter: Painter
        painter.begin()
        painter.setColorMaskFull()
        painter.clear(Color.fromArgb(Argb.White))
        painter.fillPath(&circle, Color.fromArgb(Argb.Blue), PathFillRule.NonZero)
        painter.end()
        images[index] = renderCpu(100, 100, &painter)
    }

    // The edge, where the circle runs diagonally, is a ramp on both.
    var soft = 0
    for y in 21 to 23
    {
        for x in 77 to 79
        {
            let clockwise     = images[0].pixelColor(x, y)
            let anticlockwise = images[1].pixelColor(x, y)
            Swag.assert(Math.abs(cast(s32, clockwise.r) - cast(s32, anticlockwise.r)) <= 1)
            if anticlockwise.r > 20 and anticlockwise.r < 235 do
                soft += 1
        }
    }

    Swag.assert(soft >= 2)
}

// Captured device-space f32 coordinates freeze the one-ulp asymmetry independently of
// transforms, tessellation, SVG parsing, and the compiler's floating-point policy.
const SharedEdgeA = Math.Vector2{cast #bit (f32, 1096403587'u32), cast #bit (f32, 1096403585'u32)}
const SharedEdgeB = Math.Vector2{cast #bit (f32, 1099362556'u32), cast #bit (f32, 1093586878'u32)}
const SharedEdgeC = Math.Vector2{cast #bit (f32, 1106488610'u32), cast #bit (f32, 1106488610'u32)}
const SharedEdgeD = Math.Vector2{cast #bit (f32, 1093586879'u32), cast #bit (f32, 1099362556'u32)}

private func checkSharedEdge(mode: s32)
{
    const Source   = Color.fromArgb(128'u8, 255'u8, 0'u8, 0'u8)
    const Expected = Color.fromArgb(255'u8, 128'u8, 0'u8, 0'u8)
    var cpu:      RenderCpu
    let renderer: IRenderer = &cpu
    renderer.init()
    cpu.begin(40, 40)
    defer renderer.end()

    var texel = Image.create(1, 1, .RGBA8)
    texel.fill(Source)
    var texture = renderer.addImage(texel)
    defer renderer.removeTexture(&texture)

    var brush = Brush.createSolid(Source)
    if mode >= 3
    {
        brush = Brush.createTexture(texture)
        if mode == 3
        {
            brush.uvMode = .FillSubRect
            brush.uvRect = {0, 0, 1, 1}
        }
    }

    var painter = Painter.create(renderer)
    painter.begin()
    painter.setColorMaskFull()
    painter.clear(Color.fromRgb(0, 0, 0))
    painter.setBlendingMode(.Alpha)
    if mode != 2 and mode != 4 do
        painter.setColorMaskColor()
    painter.setAntialiased(false)
    painter.setInterpolationMode(.Pixel)
    if mode == 1 do
        painter.setClippingRect({0, 0, 22, 40})

    // Two public triangle fills keep the shared diagonal A-C fixed. Its orientation is
    // reversed in the second triangle; no mutable access to recorded vertices is used.
    let firstTriangle  = [SharedEdgeA, SharedEdgeB, SharedEdgeC]
    let secondTriangle = [SharedEdgeA, SharedEdgeC, SharedEdgeD]
    painter.fillPolygon(firstTriangle, brush)
    painter.fillPolygon(secondTriangle, brush)
    painter.end()

    renderer.draw(&painter)
    let image = cpu.surfaceImage()
    let last  = mode == 1 ? 22 : 28
    for coordinate in 17 until last
    {
        let actual = image.pixelColor(coordinate, coordinate)
        Swag.assert(actual == Expected, "the shared diagonal must receive one half-alpha blend")
    }

    Swag.assert(image.pixelColor(20, 21) == Expected)
    Swag.assert(image.pixelColor(21, 20) == Expected)
}

// Both triangles use four-pixel coverage spans at the disputed pixel.
#test { checkSharedEdge(0) }

// Clipping makes x=21 a scalar tail in one triangle and a packed lane in its neighbor.
#test { checkSharedEdge(1) }

// Writing alpha takes the general scalar rasterizer rather than the solid-color span path.
#test { checkSharedEdge(2) }

// The single straight-alpha texel exercises the direct nearest-neighbor texture branch.
#test { checkSharedEdge(3) }

// Full-mask texturing exercises the general textured scalar branch.
#test { checkSharedEdge(4) }

// A captured MSDF footprint lands immediately below the alpha 111 truncation boundary.
// Static descriptor storage is retained by the shaped run; the test only reads it.
private var g_MsdfRoundingGlyph: GlyphDesc = {uv: {0.1640625, 0, 0.1484375, 0.15625}, atlasIndex: 0, shiftX: cast #bit (f32, 0x41F73800'u32), shiftY: cast #bit (f32, 0xC21844A5'u32), width: cast #bit (f32, 0x424D3334'u32), height: 54}

#test
{
    var cache: FontCache
    let face = expect TypeFace.load(getTestDataPath("segoeui.ttf"))
    let font = cache.createFont(face, 40, .Msdf)
    var run  = Painter.shapeRun("e", font)
    run.glyphs[0].desc = &g_MsdfRoundingGlyph

    // Only these nine RGBA texels feed the four taps at the checked pixel.
    const Texels: [36] u8 = [
        125, 34, 125, 125, 138, 34, 138, 138, 150, 34, 150, 150,
        116, 19, 116, 116, 127, 19, 127, 127, 138, 19, 138, 138,
        105, 3, 105, 105, 116, 3, 116, 116, 126, 3, 126, 126]
    let atlas = &font.cache.atlases[0]
    Swag.assert(atlas.width == 1024 and atlas.height == 256 and atlas.bytesPerPixel == 4)
    Memory.clear(atlas.data.storage(), atlas.data.count)
    for y in 3
    {
        for x in 3
        {
            let destination = cast(u64, (255 - (27 + y))) * atlas.width + cast(u64, (52 + x)) * 4
            let source      = cast(u64, (y * 3 + x)) * 4
            for channel in 4 do
                atlas.data[destination + channel] = Texels[source + channel]
        }
    }

    var painter: Painter
    painter.begin()
    painter.setColorMaskFull()
    painter.clear(Argb.Zero)
    painter.setBlendingMode(.Copy)
    painter.translateTransform(50, 195)
    painter.drawShapedRun(0, -font.ascent, &run, font, Brush{color: Color.fromArgb(0xFFE9E9ED)})
    painter.end()

    let image = renderCpu(160, 320, &painter)
    Swag.assert(image.pixelColor(96, 271).a == 110)
}
