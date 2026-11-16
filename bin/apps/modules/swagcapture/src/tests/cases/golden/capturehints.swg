#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Gui, Pixel

// French shortcuts stay together on the right monitor of a staggered virtual desktop.
#[Swag.TestTag("golden")]
#test
{
    var f: HeadlessFixture
    f.setup(1200, 540)
    defer f.shutdown()
    defer discard catch f.gui.app.setLanguage(Gui.ReferenceLanguage)
    expect f.gui.app.setLanguage("fr")
    f.gui.theme.setLight()
    f.gui.notify(.ThemeChanged)

    f.main.monitors.clear()
    testAddMonitorAt(f.main, {0, 0, 600, 540})
    testAddMonitorAt(f.main, {600, 100, 600, 440})
    g_DesktopX, g_DesktopY = 0
    g_ScreenWidth          = 1200
    g_ScreenHeight         = 540
    g_CaptureMedia         = .Picture
    beginAreaSelection()
    var desktop = Testing.indexedImage(1200, 540)
    g_DesktopTexture = f.gui.app.renderer.addImage(desktop)
    defer f.gui.app.renderer.removeTexture(&g_DesktopTexture)

    with let overlay = Wnd.create'CaptureRectWnd(&f.gui.root, {0, 0, 1200, 540})
    {
        .main = f.main
    }

    overlay.createHints()
    var move = MouseEvent{kind: .Move, surfacePos: {900, 300}}
    overlay.sendEvent(&move)
    overlay.applyLayout()
    var image = f.gui.render(overlay)
    Pixel.Testing.assertImageGolden(&image, "area.hints.multiscreen.fr.papier")
}
