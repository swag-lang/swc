#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

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
