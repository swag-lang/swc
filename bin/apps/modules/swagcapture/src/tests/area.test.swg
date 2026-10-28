#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// The area overlay of the charter: the desktop dimmed but the chosen zone, a 1 px Voltage edge, the
// size in a mono chip, the pixel loupe by the pointer, the modes on a floating bar and the keys at
// the foot.
#[Swag.TestTag("golden")]
#test
{
    var f: HeadlessFixture
    f.setup(1024, 640)
    defer f.shutdown()

    var desktop = Gui.Testing.indexedImage(1024, 640)
    g_DesktopTexture = f.gui.app.renderer.addImage(desktop)
    defer f.gui.app.renderer.removeTexture(&g_DesktopTexture)
    g_DesktopX, g_DesktopY = 0
    g_ScreenWidth  = 1024
    g_ScreenHeight = 640
    g_StartGrabX   = 300
    g_StartGrabY   = 220
    g_EndGrabX     = 880
    g_EndGrabY     = 520

    f.gui.theme.setDark()
    f.gui.notify(.ThemeChanged)

    with let wnd = Wnd.create'CaptureRectWnd(&f.gui.root, {0, 0, 1024, 640})
    {
        .main      = f.main
        .startGrab = true
        .pointer   = {880, 520}
    }

    with wnd.hintLine = HintLine.create(wnd)
    {
        .addHint(appStrings().key_Enter, appStrings().hint_Capture)
        .addHint(Gui.strings().key_Escape, appStrings().hint_Cancel)
    }

    wnd.applyLayout()
    var image = f.gui.render(wnd)
    Pixel.Testing.assertImageGolden(&image, "area")

    // The bar takes its own clicks: the tabs of the modes stand on it, the area first.
    Swag.assert(wnd.modeTabs.count == AreaModes.count)
    Swag.assert(wnd.barRect.contains(wnd.modeTabs[1].center()))
    Swag.assert(wnd.modeAt(wnd.modeTabs[2].center()) == 2)
}
