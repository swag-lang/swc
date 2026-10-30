#global if #command == Swag.CompilerCommand.Test

using Core

// The separable Gaussian reuses its capture for the second axis.
#test
{
    var cpu:      RenderCpu
    let renderer: IRenderer = &cpu
    renderer.begin({width: 96, height: 64})
    var painter = Painter.create(renderer)
    painter.begin()
    BackdropEffect{algorithm: .Gaussian, radius: 6}.draw(&painter, {0, 0, 96, 64})
    painter.end()
    var targets = 0
    for command in painter.commandBuffer where Swag.kindOf(command.op) == .ReleaseRenderTarget do
        targets += 1
    Swag.assert(targets == 2)
    renderer.draw(&painter)
    renderer.end()
}

// Both backends run this scene, with a translated, clipped material over an opaque ground.
func renderBackdropScene(renderer: IRenderer, algorithm: BackdropBlur, scale: f32 = 1)->Image
{
    let width  = cast(s32, 96 * scale)
    let height = cast(s32, 64 * scale)
    var target = renderer.createRenderTarget(width, height)
    defer renderer.deleteRenderTarget(&target)
    var painter = Painter.create(renderer)
    painter.begin()
    painter.setContentScale(scale)
    painter.bindRenderTarget(&target)
    painter.setColorMaskFull()
    painter.clear(Argb.White)
    painter.setAntialiased(false)
    for x in 12 do
        painter.fillRect(Math.Rectangle{x * 8, 0, 4, 64}, Argb.Black)
    painter.translateTransform(8, 4)
    painter.pushClippingRect({8, 4, 64, 48})
    let effect = BackdropEffect{algorithm: algorithm, radius: 6}
    effect.draw(&painter, {0, 0, 80, 56})
    painter.popClippingRect()

    // Foreground is drawn after the material and must stay sharp.
    painter.fillRect(Math.Rectangle{32, 24, 8, 8}, Argb.Red)
    painter.unbindRenderTarget()
    painter.end()
    renderer.draw(&painter)
    return renderer.readRenderTarget(&target, 0, 0, width, height)
}

#test
{
    for algorithm in [BackdropBlur.Gaussian, .DualKawase]
    {
        for scale in [1.0'f32, 1.5]
        {
            var cpu: RenderCpu
            let image = renderBackdropScene(&cpu, algorithm, scale)
            assertPixel(image, cast(s32, 42 * scale), cast(s32, 30 * scale), Argb.Red)
            assertPixel(image, cast(s32, 2 * scale), cast(s32, 20 * scale), Argb.Black)
            let softened = image.pixelColor(cast(s32, 34 * scale), cast(s32, 20 * scale))
            Swag.assert(softened.r > 20 and softened.r < 235, Format.toString("algorithm=% scale=% red=%", algorithm, scale, softened.r))
            Swag.assert(softened.a == 255)
        }
    }
}

// A flat field keeps its brightness, including at the target edges and after repeated passes.
#test
{
    for algorithm in [BackdropBlur.Gaussian, .DualKawase]
    {
        var cpu:      RenderCpu
        let renderer: IRenderer = &cpu
        renderer.begin({width: 31, height: 19})
        var painter = Painter.create(renderer)
        painter.begin()
        painter.setColorMaskFull()
        painter.clear(Color.fromArgb(0xFF6080A0))
        let effect = BackdropEffect{algorithm: algorithm, radius: 12}
        effect.draw(&painter, {-4, -3, 40, 30})
        effect.draw(&painter, {0, 0, 31, 19})
        painter.end()
        renderer.draw(&painter)
        renderer.end()
        let image = cpu.surfaceImage()
        for y in image.height
        {
            for x in image.width
            {
                let color = image.pixelColor(x, y)
                Swag.assert(Math.abs(cast(s32, color.r) - 96) <= 2, Format.toString("algorithm=% x=% y=% red=%", algorithm, x, y, color.r))
                Swag.assert(Math.abs(cast(s32, color.g) - 128) <= 2)
                Swag.assert(Math.abs(cast(s32, color.b) - 160) <= 2)
                Swag.assert(color.a == 255)
            }
        }
    }
}

// Saturation, tint, zero extent, and opacity are independent of the spatial filter.
#test
{
    var cpu:      RenderCpu
    let renderer: IRenderer = &cpu
    renderer.begin({width: 12, height: 8})
    var painter = Painter.create(renderer)
    painter.begin()
    painter.setColorMaskFull()
    painter.clear(Argb.Red)
    BackdropEffect{radius: 0, saturation: 0}.draw(&painter, {0, 0, 4, 8})
    BackdropEffect{radius: 0, tint: Color.fromArgb(Argb.Blue)}.draw(&painter, {4, 0, 4, 8})
    BackdropEffect{opacity: 0}.draw(&painter, {8, 0, 4, 8})
    BackdropEffect{}.draw(&painter, {})
    painter.end()
    renderer.draw(&painter)
    renderer.end()
    let image = cpu.surfaceImage()
    let gray  = image.pixelColor(1, 1)
    Swag.assert(gray.r == gray.g and gray.g == gray.b and gray.r > 50 and gray.r < 56)
    assertPixel(image, 5, 1, Argb.Blue)
    assertPixel(image, 9, 1, Argb.Red)
}

// A material keeps target coverage and obeys a stencil without leaking its drawing state.
#test
{
    var cpu:      RenderCpu
    let renderer: IRenderer = &cpu
    renderer.begin({width: 24, height: 16})
    var painter = Painter.create(renderer)
    painter.begin()
    painter.setColorMaskFull()
    painter.clear(Color.fromArgb(71'u8, 200'u8, 40'u8, 20'u8))
    painter.setAntialiased(false)
    painter.startClippingRegion()
    painter.fillRect(Math.Rectangle{4, 4, 12, 8}, Argb.White)
    painter.endClippingRegion()
    BackdropEffect{radius: 4, tint: Color.fromArgb(Argb.Blue), opacity: 0.5}.draw(&painter, {0, 0, 24, 16})
    painter.resetClippingRegion()

    // The material must have restored the caller's full mask and unrestricted scissor.
    painter.fillRect(Math.Rectangle{20, 12, 4, 4}, Argb.Green)
    painter.end()
    renderer.draw(&painter)
    renderer.end()
    let image  = cpu.surfaceImage()
    let inside = image.pixelColor(8, 8)
    Swag.assert(inside.a == 71 and inside.r >= 99 and inside.r <= 101)
    Swag.assert(inside.b >= 136 and inside.b <= 138)
    assertPixel(image, 1, 1, Color.fromArgb(71'u8, 200'u8, 40'u8, 20'u8))
    assertPixel(image, 22, 14, Argb.Green)
}
