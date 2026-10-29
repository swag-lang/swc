#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel

func paintBackdropDocument(wnd: *Wnd, event: IEvent)->bool
{
    if event is PaintEvent as paint where paint.kind == .Content
    {
        let painter = paint.paintContext.painter
        let colors  = wnd.themeColors()
        let font    = wnd.theme().createDefaultFont(14)
        for row in 14
        {
            let y = 30 + row * 30
            painter.fillRect(Math.Rectangle{24, y, 4, 16}, colors.arc)
            painter.drawString(44, y, "A document stays in place while its commands come into focus.", font, colors.text)
        }
    }

    return false
}

func backdropLens(host: *Testing.HeadlessHost, light: bool, scale: f32 = 1, compact = false)->*Lens.View
{
    host.setup(compact ? 320 : 760, compact ? 240 : 520, scale)
    if light do
        host.theme.setLight()
    else do
        host.theme.setDark()
    host.notify(.ThemeChanged)
    host.root.backgroundStyle = .Window
    host.root.hookOnEvent     = &paintBackdropDocument
    let lens = Lens.View.create(&host.root)
    lens.addRestSource(func(results)
    {
        let section = results.addSection("Document")
        discard section.addEntry("Find in Document")
        discard section.addEntry("Save as Image")
    })
    return lens
}

// Compare light frosted-glass materials over the two-to-four-pixel reading range.
func backdropMaterialSheet(light: bool)->Image
{
    var sheet = Image.create(1140, 780, .BGRA8)
    for tint, row in [0.08'f32, 0.14, 0.20]
    {
        for radius, column in [2.0'f32, 3.5, 4.0]
        {
            var host: Testing.HeadlessHost
            let lens = backdropLens(&host, light, 0.5)
            lens.open()
            lens.backdrop = BackdropEffect{algorithm: .Gaussian, radius: radius * 3, saturation: 1,
                                           tint: host.theme.colors.floating_Shadow.withAlphaF32(tint)}
            lens.input.setPlaceholder(Format.toString("% px / tint %", radius, cast(s32, Math.round(tint * 100))))
            let image = host.render()
            sheet.mix(image, cast(s32, column) * 380, (2 - cast(s32, row)) * 260)
        }
    }

    return sheet
}

#[Swag.TestTag("golden")]
#test
{
    let image = backdropMaterialSheet(false)
    Pixel.Testing.assertImageGolden(&image, "backdrop.materials.ink")
}

#[Swag.TestTag("golden")]
#test
{
    let image = backdropMaterialSheet(true)
    Pixel.Testing.assertImageGolden(&image, "backdrop.materials.paper")
}

#[Swag.TestTag("golden")]
#test
{
    for light in [false, true]
    {
        var host: Testing.HeadlessHost
        let lens = backdropLens(&host, light)
        lens.open()
        host.settleAnimations()
        let image = host.render()
        Pixel.Testing.assertImageGolden(&image, light ? "backdrop.lens.paper" : "backdrop.lens.ink")
    }
}

// A small invalidation reconstructs the same backdrop as a full paint, without cumulative blur.
#test
{
    var host: Testing.HeadlessHost
    let lens = backdropLens(&host, false, 1.5, compact: true)
    lens.open()
    host.settleAnimations()
    let expected = host.render()
    for count in 3
    {
        discard count
        host.surface.invalidateRect({40, 40, 12, 12})
        host.surface.paintWnd(&host.root)
        let actual = host.app.renderer.readRenderTarget(&host.surface.rt, 0, 0, expected.width, expected.height)
        Pixel.Testing.assertImagesNear(&expected, &actual, "backdrop.partial", {maxChannelDelta: 0})
    }

    lens.close()
    host.settleAnimations()
    Swag.assert(not host.root.hasBackdrop())
}

// The material samples the parent before the lens's own opacity layer is recorded.
#test
{
    var host: Testing.HeadlessHost
    let lens  = backdropLens(&host, true, compact: true)
    let clear = host.render()
    lens.open()
    host.settleAnimations()
    let blurred = host.render()
    lens.setPresentationOpacity(0.5)
    let halfway = host.render()
    let x       = 46
    let y       = 34
    let before  = clear.pixelColor(x, y)
    let after   = blurred.pixelColor(x, y)
    let middle  = halfway.pixelColor(x, y)
    Swag.assert(before != after)
    Swag.assert(Math.abs(cast(s32, middle.r) * 2 - before.r - after.r) <= 4)
}
