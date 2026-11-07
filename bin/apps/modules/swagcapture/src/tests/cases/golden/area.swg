#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// The area overlay of the charter: the desktop dimmed but the chosen zone, a 1 px Voltage edge, the
// size in a mono chip, the pixel loupe by the pointer, and the keys at the foot.
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
    g_ScreenWidth          = 1024
    g_ScreenHeight         = 640
    g_StartGrabX           = 300
    g_StartGrabY           = 220
    g_EndGrabX             = 880
    g_EndGrabY             = 520

    f.gui.theme.setDark()
    f.gui.notify(.ThemeChanged)

    with let wnd = Wnd.create'CaptureRectWnd(&f.gui.root, {0, 0, 1024, 640})
    {
        .main      = f.main
        .startGrab = true
        .pointer   = {880, 520}
    }

    wnd.createHintLine()
    wnd.applyLayout()
    var image = f.gui.render(wnd)
    Pixel.Testing.assertImageGolden(&image, "area")

    Swag.require(wnd.hintLine.grounded)

    // The keys teach Tab, which chooses the picture or the animation, and the right click, which
    // abandons the rectangle for another.
    Swag.require(wnd.hintLine.hints.count == 4 and wnd.hintLine.hints.back().text == appStrings().hint_RedrawArea)
}
