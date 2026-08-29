#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Pixel

// Image rows are stored bottom-up; pixelColor answers in top-down coordinates, the
// space every window rectangle in these tests is written in.
func pixelAt(image: const *Image, x, y: s32)->u32
{
    return image.pixelColor(x, y).argb
}

// The plain application grounds are available as window background styles, so a composed
// surface can separate content and chrome without hardcoding palette colors.
#test
{
    var host: Testing.HeadlessHost
    host.setup(180, 20)
    defer host.shutdown()
    host.theme.setSwagDark()
    host.notify(.ThemeChanged)

    let application = Wnd.create'Wnd(&host.root, {0, 0, 20, 20})
    let view        = Wnd.create'Wnd(&host.root, {20, 0, 20, 20})
    let window      = Wnd.create'Wnd(&host.root, {40, 0, 20, 20})
    let infoBar     = Wnd.create'Wnd(&host.root, {60, 0, 20, 20})
    let commandBar  = Wnd.create'Wnd(&host.root, {80, 0, 20, 20})
    let toolBar     = Wnd.create'Wnd(&host.root, {100, 0, 20, 20})
    let panel       = Wnd.create'Wnd(&host.root, {120, 0, 20, 20})
    let panelHost   = Wnd.create'Wnd(&host.root, {140, 0, 20, 20})
    let viewPanel   = Wnd.create'Wnd(&host.root, {160, 0, 20, 20})
    application.backgroundStyle = .Application
    view.backgroundStyle        = .View
    window.backgroundStyle      = .Window
    infoBar.backgroundStyle     = .InformationBar
    commandBar.backgroundStyle  = .CommandBar
    toolBar.backgroundStyle     = .ToolBar
    panel.backgroundStyle       = .Panel
    panelHost.backgroundStyle   = .ToolBar
    viewPanel.backgroundStyle   = .Panel
    viewPanel.style.addStyleSheetColors("wnd_Bk $view_Bk")

    let integratedPanel = Wnd.create'Wnd(panelHost, {0, 0, 20, 20})
    integratedPanel.backgroundStyle = .Panel

    let image = host.render()
    @assert(pixelAt(&image, 10, 10) == host.theme.colors.bk.argb)
    @assert(pixelAt(&image, 30, 10) == host.theme.colors.view_Bk.argb)
    @assert(pixelAt(&image, 50, 10) == host.theme.colors.wnd_Bk.argb)
    @assert(pixelAt(&image, 70, 10) == host.theme.colors.informationBar_Bk.argb)
    @assert(pixelAt(&image, 90, 10) == host.theme.colors.commandBar_Bk.argb)
    @assert(pixelAt(&image, 110, 10) == host.theme.colors.toolBar_Bk.argb)
    @assert(pixelAt(&image, 130, 10) == host.theme.colors.wnd_Bk.argb)
    let roundedCorner = pixelAt(&image, 140, 0)
    @assert(roundedCorner != host.theme.colors.toolBar_Bk.argb and roundedCorner != host.theme.colors.wnd_Bk.argb)
    @assert(pixelAt(&image, 150, 10) == host.theme.colors.wnd_Bk.argb)
    @assert(pixelAt(&image, 170, 10) == host.theme.colors.view_Bk.argb)
}

// A device scale of 2 renders the same logical tree into a doubled physical target:
// logical geometry lands on scaled device pixels while the window tree stays logical.
#test
{
    var host: Testing.HeadlessHost
    host.setup(96, 64, dpiScale: 2)
    defer host.shutdown()

    @assert(host.surface.dpiScale == 2)
    @assert(host.surface.size().x == 96 and host.surface.size().y == 64)

    let background = host.render()
    @assert(background.width == 192 and background.height == 128)

    // A view-background child at logical (16, 8, 32, 24) must cover the physical
    // rectangle (32, 16, 64, 48).
    let child = Wnd.create'Wnd(&host.root, {16, 8, 32, 24})
    child.backgroundStyle = .View
    let framed = host.render()

    let inside  = pixelAt(&framed, 48, 28)
    let outside = pixelAt(&framed, 24, 28)
    @assert(inside != outside)

    // The edges sit on the device grid: just outside the left edge (x = 32) still
    // shows the parent background, just inside shows the child, and likewise around
    // the right edge (x = 96).
    @assert(pixelAt(&framed, 30, 28) == outside)
    @assert(pixelAt(&framed, 34, 28) == inside)
    @assert(pixelAt(&framed, 94, 28) == inside)
    @assert(pixelAt(&framed, 98, 28) == outside)
}

// The identical logical tree rendered at scale 1 and scale 2 must agree: the scaled
// image is the same picture with doubled geometry, not a different layout.
#test
{
    var host1: Testing.HeadlessHost
    host1.setup(96, 64)
    let child1 = Wnd.create'Wnd(&host1.root, {16, 8, 32, 24})
    child1.backgroundStyle = .View
    let image1 = host1.render()
    host1.shutdown()

    var host2: Testing.HeadlessHost
    host2.setup(96, 64, dpiScale: 2)
    defer host2.shutdown()
    let child2 = Wnd.create'Wnd(&host2.root, {16, 8, 32, 24})
    child2.backgroundStyle = .View
    let image2 = host2.render()

    // Compare well inside each region, away from antialiased edges.
    @assert(pixelAt(&image1, 24, 20) == pixelAt(&image2, 48, 40))
    @assert(pixelAt(&image1, 8, 8) == pixelAt(&image2, 16, 16))
    @assert(pixelAt(&image1, 90, 60) == pixelAt(&image2, 180, 120))
}
