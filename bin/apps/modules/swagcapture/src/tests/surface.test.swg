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

    with let main = MainWnd.create(&host.surfaceWnd)
    {
        .setPosition(host.surfaceWnd.paddedClientRect())
        .applyLayout()
    }

    return main
}

// Opens the shipped library page with the same deterministic dark geometry used by its surface
// golden. Menu snapshots must exercise the real command-bar button and its real modal path: a
// detached MenuCtrl would miss precisely the anchor junction these tests protect.
func testSetupLibrarySurface(host: *Gui.Testing.HeadlessHost)->*MainWnd
{
    let main = testSetupSurfaceMain(host)
    testEmptyTrash()
    g_Library.loaded = true
    main.swapLibraryMode()

    host.theme.setDark()
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
    host.app.sigFrame += func|host, main, button, golden, captured = &captured|(_)
    {
        if captured[] do
            return

        let menu = host.capturedPopupMenu()
        Swag.assert(menu != null)
        Swag.assert(not button.icon.isValid())
        Swag.assert(menu.themeMetrics().menuPopup_IconSize == themeRowIconSize(main.themeMetrics()))
        var image = host.render(main)
        Pixel.Testing.assertImageGolden(&image, golden)
        let menuDismissed = host.dismissPopupMenu()
        Swag.assert(menuDismissed)
        captured[] = true
    }

    button.sigPressed.call(cast(*Button, button))
    Swag.assert(captured)
    host.pump()
}

// Opens the option sheet of `button`, follows the link worded `link` when there is one, and
// compares the library with the sheet open to `golden`.
func testAssertLibrarySheetGolden(host: *Gui.Testing.HeadlessHost, main: *MainWnd, button: *IconButton, golden: string, link: string? = null)
{
    var captured: bool
    host.app.sigFrame += func|host, main, golden, link, captured = &captured|(_)
    {
        let sheet = host.capturedOptionSheet()
        if captured[] or not sheet do
            return
        host.finishAnimations()
        if link
        {
            Swag.assert(sheet.activateRow(link))
            host.finishAnimations()
        }

        var image = host.render(main)
        Pixel.Testing.assertImageGolden(&image, golden)
        sheet.close()
        captured[] = true
    }

    button.sigPressed.call(cast(*Button, button))
    host.app.sigFrame.clear()
    Swag.assert(captured)
    host.pump()
}

// Builds the editor over a white capture holding one selected text, in `dark` or light, and lays
// it out the way the shipped window is.
func testSetupEditorSurface(host: *Gui.Testing.HeadlessHost, dark: bool)->*MainWnd
{
    let main = testSetupSurfaceMain(host)

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
    main.quickWnd.setDefault()

    if dark do
        host.theme.setDark()
    else do
        host.theme.setLight()
    host.theme.metrics.surfaceWnd_ShadowSize   = 0
    host.theme.metrics.surfaceWnd_CornerRadius = 0
    host.notify(.ThemeChanged)
    main.applyLayout()
    main.updateState()
    host.finishAnimations()
    return main
}

// The caption carries the window buttons and nothing else: the appearance owner stays hidden,
// and its choices, like every command, are entries of the lens.
#test
{
    var host: Gui.Testing.HeadlessHost
    let main = testSetupSurfaceMain(&host, caption: true)
    defer
    {
        host.shutdown()
        g_Main = null
    }

    Swag.assert(not main.appearanceButton.isLocallyVisible())

    // Every command the old menus held is a lens entry.
    main.lens.open("")
    var titles: Array'String
    for section in main.lens.results.sections
    {
        for entry in section!.entries do
            titles.add(entry.title)
    }

    main.lens.close()
    for id in [ActionFile.NewImage, ActionFile.OpenImage, ActionFile.SaveAsImage, ActionCapture.Area, ActionCapture.FullScreen,
               ActionUndo.DoUndo, ActionImage.ResizeImage, ActionImage.ExpandImage, ActionZoom.ZoomFit, ActionGlobal.ShowLibrary,
               ActionOptions.Options, ActionToolMode.Arrow, ActionAlign.SendToFront, ActionView.Inspector]
    {
        let state = main.sendComputeCommandStateEvent(id)
        if state.updatedFields.has(.Hidden) and state.hidden do
            continue
        Swag.assert(titles.contains(state.name), state.name)
    }
}

// The editor of the charter: the capture on the ground, the dock at the leading edge, the
// inspector at the trailing edge, the mini-bar beside the selection and the hint line at the
// foot, in Encre and in Papier.
#[Swag.TestTag("golden")]
#test
{
    for dark in [true, false]
    {
        var host: Gui.Testing.HeadlessHost
        let main = testSetupEditorSurface(&host, dark)
        defer
        {
            main.libWnd.requestClose()
            host.shutdown()
            g_Main = null
        }

        // The floating parts take no room from the work: the editor takes the whole window.
        let metrics = main.themeMetrics()
        let area    = main.editArea.surfaceRect()
        Swag.assert(main.editWnd.surfaceRect() == area)
        Swag.assert(main.dock.surfaceRect().x == area.x + metrics.floating_Inset)
        Swag.assert(main.inspector.surfaceRect().right() == area.right() - metrics.floating_Inset)
        Swag.assert(main.miniBar.isLocallyVisible() and main.miniBarKind == .Text)
        Swag.assert(not main.hintLine.reading.isEmpty())
        Swag.assert(not main.recentBar.isLocallyVisible())

        var image = host.render(main)
        Pixel.Testing.assertImageGolden(&image, dark ? "surface" : "surface.paper")
    }
}

// The lens over the editor, answering a query with commands of several families, in Papier.
#[Swag.TestTag("golden")]
#test
{
    var host: Gui.Testing.HeadlessHost
    let main = testSetupEditorSurface(&host, dark: false)
    defer
    {
        main.libWnd.requestClose()
        host.shutdown()
        g_Main = null
    }

    main.lens.open("image")
    Swag.assert(main.lens.isOpen() and not main.lens.rows.isEmpty())
    host.finishAnimations()

    var image = host.render(main)
    Pixel.Testing.assertImageGolden(&image, "lens.paper")
    main.lens.close()
}

// Names of the captures of the library golden.
const LibraryGoldenTitles = ["Side panel", "Error bubble", "Swag lexer", "Dark explorer", "Password"]

// The library of the charter: the page title over the folder tabs and the tag chips, the quiet
// menus and the search beside the title, the captures with their names and facts under them.
#[Swag.TestTag("golden")]
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

    host.theme.setDark()
    host.theme.metrics.surfaceWnd_ShadowSize   = 0
    host.theme.metrics.surfaceWnd_CornerRadius = 0
    host.notify(.ThemeChanged)
    testEmptyTrash()

    g_Library.loaded = true
    main.swapLibraryMode()
    main.applyLayout()
    host.finishAnimations()

    // A few captures with names, tags and ratings, one of them chosen.
    let lib = main.libWnd
    for i in 5
    {
        with let it = testAddLibraryItem(lib.view, Format.toString("capture%.scc", i), 1000, cast(u16, 20 + i), title: LibraryGoldenTitles[i])
        {
            .capture!.width  = 1280
            .capture.height = 800
            .capture.rating = cast(u8, i % 3)
            .capture.tags.add(i % 2 == 0 ? "gui" : "scope")
            var preview = Image.create(64, 40, .BGRA8)
            preview.fill(i % 2 == 0 ? Argb.White : Argb.DarkGray)
            .texture = host.app.renderer.addImage(preview)
        }
    }

    lib.view.selModel.select(1)
    lib.refreshAutomaticFilters(force: true)
    main.applyLayout()

    // The page stands on the ground of the window, its header clear of the strip.
    Swag.assert(main.libWnd.backgroundStyle == .Window)
    Swag.assert(main.libWnd.captureHost.backgroundStyle == .Transparent)
    Swag.assert(main.libWnd.header.surfaceRect().y >= main.libWnd.surfaceRect().y + main.libWnd.stripInset())

    var image = host.render(main)
    Pixel.Testing.assertImageGolden(&image, "library.surface")
}

// The quiet menus of the library open their sheet or their menu joined to the word that opened it.
#[Swag.TestTag("golden")]
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

    testAssertLibrarySheetGolden(&host, main, main.libWnd.viewBtn, "library.options.view")
}

#[Swag.TestTag("golden")]
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

    testAssertLibrarySheetGolden(&host, main, main.libWnd.viewBtn, "library.options.sort", appStrings().ui_SortBy)
}

#[Swag.TestTag("golden")]
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

    testAssertLibrarySheetGolden(&host, main, main.libWnd.filterBtn, "library.options.filter")
}

#[Swag.TestTag("golden")]
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

    testAssertLibraryMenuGolden(&host, main, main.libWnd.folderBtn, "library.menu.folders")
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
        capture.width, capture.widthOrg   = 96 + cast(s32, i)
        capture.height, capture.heightOrg = 64 + cast(s32, i)
        capture.backImg = Gui.Testing.indexedImage(capture.width, capture.height)

        let image = testAddImage(capture, 8, 8, 40, 32)
        image.kind  = .Image
        image.image = Gui.Testing.indexedImage(16 + cast(s32, i % 7), 12 + cast(s32, i % 5))

        f.editView.setCapture(capture)
        f.editView.setZoom(1)
        var rendered = f.gui.render(f.editView)
        Swag.assert(rendered.isValid())
    }
}
