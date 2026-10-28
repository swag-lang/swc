#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Pixel

// A product mark as an application ships it: a Voltage glyph cut from an ink tile.
func chromeTestMark()->Image
{
    var result = Image.create(32, 32, .RGBA8)
    result.visitPixels()
    {
        let frame = x >= 6 and x < 26 and y >= 6 and y < 26
        let hole  = x >= 12 and x < 20 and y >= 12 and y < 20
        let color = (frame and not hole) ? MarkVoltage : MarkInk
        pix[0] = color.r
        pix[1] = color.g
        pix[2] = color.b
        pix[3] = 0xFF
    }

    return result
}

// Builds a standard application window around an empty document, in the theme the host wears.
//
// The window keeps the corner of the charter; the host squares it by default because a headless
// image has no desktop under it, and the corner is part of what this test pins. The strip floats
// over the view, so the view takes the whole body inside the outline.
func buildChromeWindow(host: *Testing.HeadlessHost)
{
    host.app.setAppIcon(chromeTestMark())
    host.theme.metrics.surfaceWnd_CornerRadius = 10
    host.surface.flags        = .StandardWindow
    host.surfaceWnd.padding   = {1, 1, 1, 1}
    host.root.backgroundStyle = .Window
    host.surface.setTitle("viewerchrome.swg")
    host.surfaceWnd.create(&host.root, null)
    host.surfaceWnd.sendResizeEvent()
}

// The window glyph is the shape of the mark alone, in white, so the chrome can tint it with one
// ink in either theme: its Voltage and its ink tile are both gone.
#test
{
    var host: Testing.HeadlessHost
    host.setup(64, 64)
    host.app.setAppIcon(chromeTestMark())

    let glyph  = host.app.appGlyph(18)
    let pixels = host.app.renderer.readTexturePixels(glyph.imageList!.texture, .RGBA8)

    func at(pixels: const [..] u8, x, y: s32)->u32
    {
        let offset = cast(u64, (y * 32 + x) * 4)
        return Math.make32(pixels[offset + 3], pixels[offset], pixels[offset + 1], pixels[offset + 2])
    }

    Swag.assert(glyph.sizeX == 18 and glyph.color.a == 0)
    Swag.assert(at(pixels.toSlice(), 8, 8) == 0xFFFFFFFF)
    Swag.assert(at(pixels.toSlice(), 2, 2) >> 24 == 0)
    Swag.assert(at(pixels.toSlice(), 16, 16) >> 24 == 0)
}

// The top strip is the window's own ground: no band, no rail and no glow. It stays draggable
// wherever no control sits, the title included, and the window buttons are not part of it.
#test
{
    var host: Testing.HeadlessHost
    host.setup(480, 120)
    buildChromeWindow(&host)

    let strip = host.theme.metrics.wnd_StripHeight
    Swag.assert(host.surfaceWnd.stripHeight() == strip)
    Swag.assert(host.surfaceWnd.hitTestCaption({240, strip * 0.5}))
    Swag.assert(host.surfaceWnd.hitTestCaption({10, strip * 0.5}))
    Swag.assert(not host.surfaceWnd.hitTestCaption({240, strip + 10}))

    let close = unwrap host.surfaceWnd.closeBtn
    Swag.assert(not host.surfaceWnd.hitTestCaption(close.surfaceRect().center()))
    Swag.assert(close.position.right() <= host.surfaceWnd.clientRect().right())

    var image  = host.render(&host.surfaceWnd)
    let ground = host.theme.colors.wnd_Bk
    Swag.assert(image.pixelColor(240, 4).argb == ground.argb)
    Swag.assert(image.pixelColor(240, cast(s32, strip) + 8).argb == ground.argb)
}

// The view takes the whole body and the strip floats over it. Content reaching the top edge
// passes under the title and still drags the window there, a control set in the strip keeps its
// clicks, and a band that must keep clear of the chrome reads its inset.
#test
{
    var host: Testing.HeadlessHost
    host.setup(480, 200)
    buildChromeWindow(&host)

    let strip = host.theme.metrics.wnd_StripHeight
    Swag.assert(host.root.position.y == 1 and host.root.position.height == 198)
    Swag.assert(host.root.stripInset() == strip - 1)

    // A document continuing below the strip is content: the strip drags over it.
    with let document = Wnd.create'Wnd(&host.root, {0, 0, 478, 198})
    {
        .focusPolicy = .Tab
    }

    Swag.assert(host.surfaceWnd.hitTestCaption({240, 20}))
    Swag.assert(not host.surfaceWnd.hitTestCaption({240, strip + 10}))
    Swag.assert(document.stripInset() == strip - 1)

    // A button set in the strip is a control: it keeps its clicks, and the strip around it drags.
    let share = PushButton.create(&host.root, "Share", {100, 10, 80, 32})
    Swag.assert(not host.surfaceWnd.hitTestCaption({140, 26}))
    Swag.assert(host.surfaceWnd.hitTestCaption({240, 26}))

    // A band laid below the strip has nothing to keep clear of.
    let band = Wnd.create'Wnd(&host.root, {0, strip, 478, 40})
    Swag.assert(band.stripInset() == 0)

    // The window buttons stay above the view, and over them nothing drags.
    let close = unwrap host.surfaceWnd.closeBtn
    Swag.assert(host.surfaceWnd.windowAt(close.position.horzCenter(), close.position.vertCenter(), true) == close)

    share.destroy()
    band.destroy()
    host.pump()
}

// Taking the caption away, as full screen does, removes the strip and tells the view, even when
// its size does not change.
#test
{
    var resizes = 0
    var host: Testing.HeadlessHost
    host.setup(480, 200)
    buildChromeWindow(&host)
    host.surface.updateFlags(remove: .Border)

    host.root.hookOnEvent = func|resizes = &resizes|(_, evt)->bool
    {
        if evt is ResizeEvent do
            resizes[] += 1
        return false
    }

    host.surface.updateFlags(remove: .LargeCaption)
    Swag.assert(host.surfaceWnd.stripHeight() == 0)
    Swag.assert(host.root.stripInset() == 0)
    Swag.assert(resizes > 0)
    Swag.assert(not host.surfaceWnd.hitTestCaption({240, 20}))

    host.surface.updateFlags(add: .LargeCaption)
    Swag.assert(host.root.stripInset() == host.theme.metrics.wnd_StripHeight)
}

// A document starting at the top edge, in Encre and in Papier: its first lines pass under the
// faint title and window buttons, which are drawn above it.
#[Swag.TestTag("golden")]
#test
{
    for light in [false, true]
    {
        var host: Testing.HeadlessHost
        host.setup(480, 160)
        if light
        {
            host.theme.setLight()
            host.notify(.ThemeChanged)
        }

        buildChromeWindow(&host)
        let lines         = "impl Bar\n{\n    func create(parent: *Wnd)->*Bar\n    {\n        with let result = Wnd.create'Bar(parent)\n    }\n}"
        with let document = Label.create(&host.root, lines, {48, 16, 420, 140})
        {
            .style.setFont(host.theme.createDefaultFontFamilyFs(13))
            .setTextAlignment(.Left, .Top)
        }

        var image = host.render(&host.surfaceWnd)
        Pixel.Testing.assertImageGolden(&image, light ? "surfacewnd.document.paper" : "surfacewnd.document.ink")
    }
}

// A document that writes the title itself takes it out of the strip, and gives it back; the
// surface keeps it for the system either way.
#test
{
    var host: Testing.HeadlessHost
    host.setup(480, 120)
    buildChromeWindow(&host)
    let title = String.from(host.surfaceWnd.name.raw)
    host.surfaceWnd.showTitle(false)
    Swag.assert(host.surfaceWnd.titleHidden and host.surfaceWnd.name.raw == title)
    host.surfaceWnd.showTitle(true)
    Swag.assert(not host.surfaceWnd.titleHidden)
}

// Encre at rest: a faint glyph at the leading corner, the title centred in small faint type, and
// three faint window buttons.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    host.setup(480, 120)
    buildChromeWindow(&host)

    var image = host.render(&host.surfaceWnd)
    Pixel.Testing.assertImageGolden(&image, "surfacewnd.chrome.ink")
}

// Papier at rest: the same chrome, the glyph in the same soft ink rather than in Voltage.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    host.setup(480, 120)
    host.theme.setLight()
    host.notify(.ThemeChanged)
    buildChromeWindow(&host)

    var image = host.render(&host.surfaceWnd)
    Pixel.Testing.assertImageGolden(&image, "surfacewnd.chrome.paper")
}

// Under the pointer a window button reaches the body ink, and close the critical ink; neither
// lays a ground until it is pressed.
#[Swag.TestTag("golden")]
#test
{
    for light in [false, true]
    {
        var host: Testing.HeadlessHost
        host.setup(480, 120)
        if light
        {
            host.theme.setLight()
            host.notify(.ThemeChanged)
        }

        buildChromeWindow(&host)
        host.surfaceWnd.minimizeBtn!.isHot = true
        host.surfaceWnd.closeBtn!.isHot    = true

        var image = host.render(&host.surfaceWnd)
        Pixel.Testing.assertImageGolden(&image, light ? "surfacewnd.chrome.hover.paper" : "surfacewnd.chrome.hover.ink")
    }
}
