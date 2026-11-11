#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// The area overlay of the charter: the desktop dimmed but the chosen zone, a 1 px Voltage edge,
// what is kept and the size in a mono chip with the key changing it, and the pixel loupe by the
// pointer. The keys stand on floating ground over the frozen desktop.
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
    wnd.createHints()

    wnd.applyLayout()
    var image = f.gui.render(wnd)
    Pixel.Testing.assertImageGolden(&image, "area")
}

// The ordinary zone selector waits for a drag without a rectangle following the pointer.
#[Swag.TestTag("golden")]
#test
{
    var f: HeadlessFixture
    f.setup(800, 500)
    defer f.shutdown()

    var desktop = Gui.Testing.indexedImage(800, 500)
    g_DesktopTexture = f.gui.app.renderer.addImage(desktop)
    defer f.gui.app.renderer.removeTexture(&g_DesktopTexture)
    g_DesktopX, g_DesktopY = 0
    g_ScreenWidth  = 800
    g_ScreenHeight = 500
    // A previous video zone must not appear when the selector opens again.
    g_StartGrabX = 120
    g_EndGrabX   = 620
    g_StartGrabY = 80
    g_EndGrabY   = 390
    beginAreaSelection()
    Swag.require(getGrabRect().isEmpty())

    f.gui.theme.setLight()
    f.gui.notify(.ThemeChanged)

    with let wnd = Wnd.create'CaptureRectWnd(&f.gui.root, {0, 0, 800, 500})
    {
        .main    = f.main
        .pointer = {400, 250}
    }
    wnd.createHints()

    wnd.applyLayout()
    var image = f.gui.render(wnd)
    Pixel.Testing.assertImageGolden(&image, "area.waiting")
}
