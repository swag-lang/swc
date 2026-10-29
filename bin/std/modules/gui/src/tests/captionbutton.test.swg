#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// A named lens door fits its label, routes the same command, and survives language changes.
#[Swag.TestTag("golden")]
#test
{
    for light in [false, true]
    {
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
        Swag.assert(button.position.width >= button.itf.measureContent({}).x)
        host.click(button.surfaceRect().center())
        host.pump()
        Swag.assert(host.commandCount == 1 and host.lastCommand == "test.lens")
        button.setFocus()
        host.keyPress(.Return)
        host.pump()
        Swag.assert(host.commandCount == 2 and host.lastCommand == "test.lens")

        expect host.app.setLanguage("fr")
        host.pump()
        Swag.assert(button.name.raw == "Commandes")
        Swag.assert(button.position.width >= button.itf.measureContent({}).x)
        host.settleAnimations(&host.surfaceWnd, 4)
        var image = host.render(&host.surfaceWnd)
        Pixel.Testing.assertImageGolden(&image, light ? "lens.launcher.light" : "lens.launcher.dark")

        button.destroy()
        host.pump()
        Swag.assert(host.surfaceWnd.captionButtons.isEmpty())
    }
}

#test
{
    var host: Testing.HeadlessHost
    host.setup(480, 240)
    host.surface.flags = SurfaceFlags.StandardWindow
    host.surfaceWnd.create(&host.root, null)
    host.surfaceWnd.sendResizeEvent()

    let button = CaptionButton.create(&host.surface, ThemeIcons.Settings)
    Swag.assert(host.surfaceWnd.captionButtons.count == 1)
    Swag.assert(button.parent == &host.surfaceWnd)
    Swag.assert(button.icon.index == cast(s32, ThemeIcons.Settings))

    button.destroy()
    host.pump()
    Swag.assert(host.surfaceWnd.captionButtons.isEmpty())
}

// A hidden caption action leaves the caption: the pointer reaches the strip where it stood.
#test
{
    var host: Testing.HeadlessHost
    host.setup(480, 240)
    host.surface.flags = SurfaceFlags.StandardWindow
    host.surfaceWnd.create(&host.root, null)
    host.surfaceWnd.sendResizeEvent()

    let button = CaptionButton.create(&host.surface, ThemeIcons.Settings)
    let center = button.surfaceRect().center()
    Swag.assert(host.surfaceWnd.hitTestCaptionButton(center))

    button.hide()
    host.surfaceWnd.sendResizeEvent()
    Swag.assert(not host.surfaceWnd.hitTestCaptionButton(center))
}
