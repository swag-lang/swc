#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Pixel

// A document palette styles all caption controls and survives their full-screen recreation.

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

// The top strip is the window's own ground: no band, no rail and no glow. It stays draggable
// wherever no control sits, the title included, and the window buttons are not part of it.

// The view takes the whole body and the strip floats over it. Content reaching the top edge
// passes under the title and still drags the window there, a control set in the strip keeps its
// clicks, and a band that must keep clear of the chrome reads its inset.

// Under the strip, the view names its own ground: there, and only there, the window drags.

// Taking the caption away, as full screen does, removes the strip and tells the view, even when
// its size does not change.

// A document starting at the top edge, in Encre: its first lines pass under the
// faint title and window buttons, which are drawn above it.
#[Swag.TestTag("golden")]
#test
{
    let light = false
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

// A document that writes the title itself takes it out of the strip, and gives it back; the
// surface keeps it for the system either way.

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
    let light = true
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
