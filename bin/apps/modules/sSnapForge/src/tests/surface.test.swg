#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// Builds the shipped window on the surface root, including every application pane.
func testSetupSurfaceMain(host: *Gui.Testing.HeadlessHost, caption = false, dpiScale = 1'f32)->*MainWnd
{
    testUseScratchLibrary()
    host.setup(1024, 640, dpiScale)
    host.bindApplication(&g_App)
    registerAppStrings(&g_App.resources)
    registerAppStrings(&host.app.resources)
    if caption do
        host.surface.updateFlags(.LargeCaption)

    let main = MainWnd.create(&host.surfaceWnd)
    main.setPosition(host.surfaceWnd.paddedClientRect())
    main.applyLayout()
    return main
}

// Opens the shipped library page with the same deterministic dark geometry used by its surface
// golden. Menu snapshots must exercise the real command-bar button and its real modal path: a
// detached MenuCtrl would miss precisely the anchor junction these tests protect.
func testSetupLibrarySurface(host: *Gui.Testing.HeadlessHost)->*MainWnd
{
    let main = testSetupSurfaceMain(host)
    g_Library.loaded = true
    main.swapLibraryMode()

    host.theme.setSwagDark()
    host.theme.metrics.surfaceWnd_ShadowSize   = 0
    host.theme.metrics.surfaceWnd_CornerRadius = 0
    host.notify(.ThemeChanged)
    main.applyLayout()
    host.finishAnimations()
    return main
}

// Presses one real library command, captures its attached popup while the modal loop owns the
// surface, then dismisses it. The full-surface image keeps the button, the junction and the menu
// body in one regression boundary.
func testAssertLibraryMenuGolden(host: *Gui.Testing.HeadlessHost, main: *MainWnd, button: *IconButton, golden: string)
{
    var captured: bool
    host.app.sigFrame += func|host, main, button, golden, captured = &captured|(app)
    {
        discard app
        if captured[] do
            return

        let menu = host.capturedPopupMenu()
        @assert(menu != null)
        @assert(button.icon.sizeX == LibCommandGlyphSize and button.icon.sizeY == LibCommandGlyphSize)
        @assert(menu!.themeMetrics().menuPopup_IconSize == LibRowGlyphSize)
        var image = host.render(main)
        Pixel.Testing.assertImageGolden(&image, golden)
        @assert(host.dismissPopupMenu())
        captured[] = true
    }

    button.sigPressed.call(cast(*Button) button)
    @assert(captured)
    host.pump()
}

// Captures one popup from the caption menu bar at a desktop DPI. Each menu owns its fixture so a
// regression in File cannot prevent Capture, Edit, Image, View, and Help from producing evidence.
func testAssertMainMenuGolden(index: u32, golden: string)
{
    var host: Gui.Testing.HeadlessHost
    let main = testSetupSurfaceMain(&host, caption: true, dpiScale: 1.5)
    defer
    {
        host.shutdown()
        g_Main = null
    }

    main.createTopMenu()
    host.surfaceWnd.applyLayout()
    host.theme.setSwagDark()
    host.theme.metrics.surfaceWnd_ShadowSize   = 0
    host.theme.metrics.surfaceWnd_CornerRadius = 0
    host.notify(.ThemeChanged)
    main.applyLayout()
    host.finishAnimations()

    let bar = main.topMenu
    @assert(bar.items.count == 6)
    @assert(index < bar.items.count)
    discard host.render(bar)

    let item  = bar.items[index]!
    let local = Math.Point{item.pos + item.size * 0.5, bar.position.height * 0.5}
    var pt    = bar.localToSurface(local)
    bar.surface!.surfaceToScreen(&pt)

    // The headless application view owns the complete synthetic surface hit target, while the
    // native caption routes this press to its sibling menu bar. Deliver that same routed event.
    host.sendMouseEvent(bar, .Pressed, pt, .Left, .None)

    let popup = host.capturedPopupMenu()
    @assert(popup != null)
    @assert(popup == item.popup)
    @assert(popup!.themeMetrics().menuPopup_IconSize == 16)
    var image     = host.render(&host.surfaceWnd)
    let cropWidth = cast(s32) (720 * bar.deviceScale())
    image.crop(0, 0, cropWidth, image.height)
    Pixel.Testing.assertImageGolden(&image, golden)

    @assert(host.dismissPopupMenu())
}

// The complete sSnapForge surface must survive its first layout and paint without a desktop.
// This is the visual boundary that the smaller interaction fixtures deliberately avoid.
#test
{
    var host: Gui.Testing.HeadlessHost
    let main = testSetupSurfaceMain(&host)
    defer
    {
        main.libWnd.requestClose()
        host.shutdown()
        g_Main = null
    }

    @assert(!main.quickStyleBar.flags.has(.HideDividers))

    let capture = Memory.new'Capture()
    capture.width, capture.widthOrg   = 400
    capture.height, capture.heightOrg = 240

    // The coordinate-coded testing image is useful for byte round-trips but aliases into
    // stripes at editor zoom. A surface golden needs quiet screenshot pixels instead.
    capture.backImg = Image.create(400, 240, .BGRA8)
    capture.backImg.fill(Argb.White)
    let text = testAddText(capture, 48, 40, 144, 80)
    text.text = "Theme"
    capture.selection.add(0)
    main.editWnd.editView.setCapture(capture)

    host.theme.setSwagDark()
    host.theme.metrics.surfaceWnd_ShadowSize   = 0
    host.theme.metrics.surfaceWnd_CornerRadius = 0
    host.notify(.ThemeChanged)
    main.applyLayout()
    host.finishAnimations()

    var image = host.render(main)
    Pixel.Testing.assertImageGolden(&image, "snapforge.surface")

    // Library keeps the same push-button silhouette as Capture. Only the active page gives
    // it the informational blue ground; returning to the editor removes that local style.
    g_Library.loaded = true
    main.swapLibraryMode()
    main.applyLayout()
    host.finishAnimations()

    image = host.render(main)
    Pixel.Testing.assertImageGolden(&image, "snapforge.library.surface")
}

// The six shipped caption menus pin the actual HiDPI text-anchor junction. Their widths and
// contents cover the narrow Help popup, the deep Edit/Image lists and Capture's submenu.
#test
{
    testAssertMainMenuGolden(0, "snapforge.main.menu.file")
}

#test
{
    testAssertMainMenuGolden(1, "snapforge.main.menu.capture")
}

#test
{
    testAssertMainMenuGolden(2, "snapforge.main.menu.edit")
}

#test
{
    testAssertMainMenuGolden(3, "snapforge.main.menu.image")
}

#test
{
    testAssertMainMenuGolden(4, "snapforge.main.menu.view")
}

#test
{
    testAssertMainMenuGolden(5, "snapforge.main.menu.help")
}

// Every text-and-icon command of the library bar keeps a continuous attached outline and the
// standard 20-pixel command / 16-pixel menu hierarchy.
#test
{
    var host: Gui.Testing.HeadlessHost
    let main = testSetupLibrarySurface(&host)
    defer
    {
        main.libWnd.requestClose()
        host.shutdown()
        g_Main = null
    }

    testAssertLibraryMenuGolden(&host, main, main.libWnd.viewBtn, "snapforge.library.menu.view")
}

#test
{
    var host: Gui.Testing.HeadlessHost
    let main = testSetupLibrarySurface(&host)
    defer
    {
        main.libWnd.requestClose()
        host.shutdown()
        g_Main = null
    }

    testAssertLibraryMenuGolden(&host, main, main.libWnd.sortBtn, "snapforge.library.menu.sort")
}

#test
{
    var host: Gui.Testing.HeadlessHost
    let main = testSetupLibrarySurface(&host)
    defer
    {
        main.libWnd.requestClose()
        host.shutdown()
        g_Main = null
    }

    testAssertLibraryMenuGolden(&host, main, main.libWnd.filterBtn, "snapforge.library.menu.filter")
}

#test
{
    var host: Gui.Testing.HeadlessHost
    let main = testSetupLibrarySurface(&host)
    defer
    {
        main.libWnd.requestClose()
        host.shutdown()
        g_Main = null
    }

    testAssertLibraryMenuGolden(&host, main, main.libWnd.folderBtn, "snapforge.library.menu.folders")
}

// Repeated painted document replacement exercises the ownership boundary between Capture,
// EditView and renderer-owned background/form textures.
#test
{
    var f: HeadlessFixture
    f.setup(320, 240)
    defer f.shutdown()

    for i in 32
    {
        let capture = Memory.new'Capture()
        capture.width, capture.widthOrg   = 96 + cast(s32) i
        capture.height, capture.heightOrg = 64 + cast(s32) i
        capture.backImg                   = Gui.Testing.indexedImage(capture.width, capture.height)

        let image = testAddImage(capture, 8, 8, 40, 32)
        image.kind  = .Image
        image.image = Gui.Testing.indexedImage(16 + cast(s32) (i % 7), 12 + cast(s32) (i % 5))

        f.editView.setCapture(capture)
        f.editView.setZoom(1)
        var rendered = f.gui.render(f.editView)
        @assert(rendered.isValid())
    }
}
