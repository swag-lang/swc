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
// image has no desktop under it, and the corner is part of what this test pins.
func buildChromeWindow(host: *Testing.HeadlessHost)
{
    host.app.setAppIcon(chromeTestMark())
    host.theme.metrics.surfaceWnd_CornerRadius = 10
    host.surface.flags        = .StandardWindow
    host.surfaceWnd.padding   = {1, host.theme.metrics.wnd_BigCaptionCY, 1, 1}
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

    let strip = host.theme.metrics.wnd_BigCaptionCY
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
