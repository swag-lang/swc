#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// Encre compares the same leading caption glyph available and unavailable.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    host.setup(480, 160)
    host.surface.flags = SurfaceFlags.StandardWindow | .NoShadow
    host.theme.setDark()
    host.notify(.ThemeChanged)
    host.surfaceWnd.create(&host.root, null)

    let unavailable = CaptionButton.createLeading(&host.surface, .ChevronLeft)
    let available   = CaptionButton.createLeading(&host.surface, .ChevronLeft)
    unavailable.disable()
    host.surfaceWnd.sendResizeEvent()
    Swag.require(not unavailable.isEnabled() and available.isEnabled())

    var image = host.renderSettled(&host.surfaceWnd)
    image.crop({0, 0, 480, host.theme.metrics.wnd_StripHeight + 20})
    Pixel.Testing.assertImageGolden(&image, "caption.disabled.encre")
}

// Papier compares the parent-folder glyph at the trailing edge of the caption.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    host.setup(480, 160)
    host.surface.flags = SurfaceFlags.StandardWindow | .NoShadow
    host.theme.setLight()
    host.notify(.ThemeChanged)
    host.surfaceWnd.create(&host.root, null)

    let unavailable = CaptionButton.create(&host.surface, .ParentFolder)
    let available   = CaptionButton.create(&host.surface, .ParentFolder)
    unavailable.disable()
    host.surfaceWnd.sendResizeEvent()
    Swag.require(not unavailable.isEnabled() and available.isEnabled())

    var image = host.renderSettled(&host.surfaceWnd)
    image.crop({0, 0, 480, host.theme.metrics.wnd_StripHeight + 20})
    Pixel.Testing.assertImageGolden(&image, "caption.disabled.paper")
}

// A named lens door fits its label, routes a pointer command without taking focus, and survives language changes.
#[Swag.TestTag("golden")]
#test
{
    let light = true
    var host: Testing.HeadlessHost
    host.setup(480, 160)
    defer discard catch host.app.setLanguage(ReferenceLanguage)
    host.surface.flags = SurfaceFlags.StandardWindow
    host.surfaceWnd.create(&host.root, null)
    if light
    {
        host.theme.setLight()
        host.notify(.ThemeChanged)
    }

    host.recordCommands()
    let button = Lens.Launcher.create(&host.root, "test.lens")
    host.surfaceWnd.sendResizeEvent()
    Swag.require(button.position.width >= button.itf.measureContent({}).x)
    host.click(button.surfaceRect().center())
    host.pump()
    Swag.require(host.commandCount == 1 and host.lastCommand == "test.lens")
    Swag.require(button.focusPolicy == .None and not button.hasFocus())
    button.setFocus()
    Swag.require(not button.hasFocus())

    expect host.app.setLanguage("fr")
    host.pump()
    Swag.require(button.name.raw == "Commandes")
    Swag.require(button.position.width >= button.itf.measureContent({}).x)
    var image = host.renderSettled(&host.surfaceWnd)
    Pixel.Testing.assertImageGolden(&image, light ? "lens.launcher.light" : "lens.launcher.dark")

    button.destroy()
    host.pump()
    Swag.require(host.surfaceWnd.captionButtons.isEmpty())
}
