#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Pixel

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
