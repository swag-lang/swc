#global if #command == Swag.CompilerCommand.Test
#global private

using Core.Serialization
using Swag, Core

// Restoring unchanged preferences does not rebuild the localized controls. Changed saved
// preferences still reach the application before its first frame.
#test
{
    var languageChanges: u32
    var host: Gui.Testing.HeadlessHost
    let main = testSetupSurfaceMain(&host)
    defer
    {
        host.shutdown()
        g_Main = null
    }

    main.editorOptions.theme    = .Dark
    main.editorOptions.language = .English
    main.setTheme()
    main.setLanguage()

    var buffer: ConcatBuffer
    var writer: Encoder'Write.TagBin
    var output: Serializer
    expect output.startWrite(&writer, &buffer)
    expect output.beginSection(.Unordered)
    var writeEvent = SerializeStateEvent{serializer: &output}
    main.IWnd.onSerializeStateEvent(&writeEvent)
    expect output.endSection()
    expect output.end()
    buffer.makeLinear()

    main.hookOnEvent = func|count = &languageChanges|(_, evt)->bool
    {
        if evt is NotifyEvent as notify where notify.kind == .LanguageChanged do
            count[] += 1
        return false
    }

    func restore(main: *MainWnd, bytes: const [..] u8)
    {
        var reader: Decoder'Read.TagBin
        var input:  Serializer
        expect input.startRead(&reader, bytes)
        expect input.beginSection(.Unordered)
        var event = SerializeStateEvent{serializer: &input}
        main.IWnd.onSerializeStateEvent(&event)
        expect input.endSection()
        expect input.end()
    }

    let revision = host.app.dirtyTheme
    restore(main, unwrap buffer.toSlice())
    Swag.assert(host.app.dirtyTheme == revision and languageChanges == 0)

    main.editorOptions.theme    = .Light
    main.editorOptions.language = .French
    main.setTheme()
    main.setLanguage()
    languageChanges = 0
    let changedRevision = host.app.dirtyTheme
    restore(main, unwrap buffer.toSlice())
    Swag.assert(host.app.dirtyTheme == changedRevision + 1 and languageChanges == 1)
    Swag.assert(main.appearanceButton.appearanceTheme == .Dark)
    Swag.assert(Application.language() == "en")
}

// Optional load regression over an external, read-only corpus. Only the ordinary test
// sandbox receives application state; the corpus is enumerated and decoded, never saved.
#[Swag.TestTag("integration.capture.corpus")]
#test
{
    let folder = Env.variable("SWAG_CAPTURE_CORPUS")
    Swag.assert(not folder.isEmpty())
    var host: Gui.Testing.HeadlessHost
    let main = testSetupSurfaceMain(&host)
    defer
    {
        main.libWnd.requestClose()
        host.shutdown()
        g_Main = null
    }

    g_Library.files  = expect Library.enumerateSupportedFiles(folder)
    g_Library.loaded = true
    Swag.assert(not g_Library.files.isEmpty())
    var watch: Time.Stopwatch
    watch.start()
    main.swapLibraryMode()
    main.libWnd.view.thread.wait()
    host.finishAnimations()
    let view = main.libWnd.view
    Swag.assert(view.allItems.count == g_Library.files.count)
    for item in view.allItems do
        Swag.assert(item!.loaded)
    Console.print("Corpus items: ", view.allItems.count, "; load ms: ", watch.elapsedMilliseconds(), "\n")

    for 8 do
        discard host.render(main)
    let count = view.allItems.count
    watch.restart()
    for 4
    {
        main.swapLibraryMode()
        main.swapLibraryMode()
        host.finishAnimations()
        discard host.render(main)
        Swag.assert(view.allItems.count == count and not g_UpdatingLib)
    }

    Console.print("Four warm library returns with off-screen painting, ms: ", watch.elapsedMilliseconds(), "\n")
}

// Builds the shipped window on the surface root, including every application pane.
func testSetupSurfaceMain(host: *Gui.Testing.HeadlessHost, caption = false, dpiScale = 1'f32)->*MainWnd
{
    testUseScratchLibrary()
    host.setup(1024, 640, dpiScale)
    host.bindApplication(&g_App)
    registerAppStrings(&g_App.resources)
    registerAppStrings(&host.app.resources)
    if caption do
        host.surface.updateFlags(Gui.SurfaceFlags.StandardWindow)

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

// Builds the editor over a white capture, in `dark` or light, the way the shipped window is; with
// `text`, the capture holds one selected text.
internal func testSetupEditorSurface(host: *Gui.Testing.HeadlessHost, dark: bool, text = true, caption = false, dpiScale = 1'f32)->*MainWnd
{
    let main = testSetupSurfaceMain(host, caption, dpiScale)

    let capture = Memory.new'Capture()
    capture.width, capture.widthOrg   = 400
    capture.height, capture.heightOrg = 240

    // The coordinate-coded testing image is useful for byte round-trips but aliases into
    // stripes at editor zoom. A surface golden needs quiet screenshot pixels instead.
    capture.backImg = Image.create(400, 240, .BGRA8)
    capture.backImg.fill(Argb.White)
    if text
    {
        let form = testAddText(capture, 48, 40, 144, 80)
        form.text = "Theme"
        capture.selection.add(0)
    }

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

// The task row and command entrance in the shipped frame, at the minimum width and 125% scale.
#[Swag.TestTag("golden")]
#test
{
    for dark in [true, false]
    {
        var host: Gui.Testing.HeadlessHost
        let main = testSetupEditorSurface(&host, dark, text: false, caption: true, dpiScale: 1.25)
        defer discard catch main.appearanceButton.setAppearanceLanguage(Gui.ReferenceLanguage)
        expect main.appearanceButton.setAppearanceLanguage(dark ? Gui.ReferenceLanguage : "fr")
        main.updateState()
        host.finishAnimations()
        var image = host.render(&host.surfaceWnd)
        Pixel.Testing.assertImageGolden(&image, dark ? "tasks.frame.encre" : "tasks.frame.fr.papier")
    }
}

// Frequent actions fit at the minimum width in both languages, and Library works by pointer.
#test
{
    var host: Gui.Testing.HeadlessHost
    let main = testSetupEditorSurface(&host, dark: true, text: false)
    defer discard catch main.appearanceButton.setAppearanceLanguage(Gui.ReferenceLanguage)
    for language in [Gui.ReferenceLanguage, "fr"]
    {
        expect main.appearanceButton.setAppearanceLanguage(language)
        main.updateState()
        host.finishAnimations()
        main.applyLayout()
        Swag.assert(main.taskBar.children.count == 4)
        var right = 0'f32
        for child in main.taskBar.children
        {
            Swag.assert(child.position.x >= right)
            Swag.assert(child.position.width >= Math.floor(child.itf.measureContent({}).x))
            Swag.assert(child.position.right() <= main.taskBar.clientRect().right())
            right = child.position.right()
        }
    }

    host.click(main.taskBar.children[1].surfaceRect().center())
    host.pump()
    Swag.assert(main.libraryMode)
}

// The named command door shares the caption with the native window buttons.
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

    // Every command the old menus held is a lens entry, which `>` lists; at rest the lens offers
    // the context only.
    main.lens.open(">")
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

        // The mini-bar stands clear of the dock and of the inspector, and never straddles the top
        // edge of the capture.
        let bar  = main.miniBar.surfaceRect()
        let view = main.editWnd.editView
        let edge = view.localToSurface(Math.Point{0, view.getCaptureRect().y - view.scrollPos.y}).y
        Swag.assert(bar.x >= main.dock.surfaceRect().right())
        Swag.assert(bar.right() <= main.inspector.surfaceRect().x)
        Swag.assert(bar.bottom() <= edge or bar.y >= edge)

        // The presets are those of the selection, a text, whatever the tool in hand.
        Swag.assert(main.editMode == .Shape and main.quickWnd.currentStyle == &main.quickWnd.qsText)
        Swag.assert(not main.recentBar.isLocallyVisible())

        var image = host.render(main)
        Pixel.Testing.assertImageGolden(&image, dark ? "surface" : "surface.paper")
    }
}

// The selection's overflow button opens the real attached menu in both palettes.
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

        let button = assume cast(*IconButton, unwrap main.miniBar.items.back().wnd)
        var captured: bool
        host.app.sigFrame += func|host = &host, main, dark, captured = &captured|(_)
        {
            if captured[] do
                return
            Swag.assert(host.capturedPopupMenu() != null)
            var image = host.render(main)
            Pixel.Testing.assertImageGolden(&image, dark ? "edit.selection-menu" : "edit.selection-menu.paper")
            Swag.assert(host.dismissPopupMenu())
            captured[] = true
        }

        host.clickWnd(button)
        Swag.assert(captured)
    }
}

// An overflow command reaches the editor and participates in its ordinary undo history.
#[Swag.TestTag("capture.interaction")]
#test
{
    var host: Gui.Testing.HeadlessHost
    let main = testSetupEditorSurface(&host, dark: true)
    defer
    {
        main.libWnd.requestClose()
        host.shutdown()
        g_Main = null
    }

    let capture = unwrap main.getCapture()
    host.clickPopupMenuItemWhenShown(ActionCopyPaste.Duplicate)
    host.clickWnd(unwrap main.miniBar.items.back().wnd)
    host.pump()
    Swag.assert(capture.forms.count == 2 and capture.selection.count == 1)
    main.editWnd.editView.setFocus()
    host.keyPress(.Z, .Control)
    Swag.assert(capture.forms.count == 1)
}

// Changing pages keeps the hidden editor's property controls and avoids a page-sized fade.
#[Swag.TestTag("capture.interaction")]
#test
{
    var host: Gui.Testing.HeadlessHost
    let main = testSetupEditorSurface(&host, dark: true)
    defer
    {
        main.libWnd.requestClose()
        host.shutdown()
        g_Main = null
    }

    let controls = main.propWnd.topLayout.children[0]
    let text     = assume cast(*FormText, (unwrap main.getCapture()).forms[0])
    g_Library.loaded = true
    main.swapLibraryMode()
    Swag.assert(main.libraryMode and main.libWnd.presentationOpacity == 1)
    Swag.assert(main.propWnd.topLayout.children[0] == controls)
    text.fontSize = 36
    main.swapLibraryMode()
    Swag.assert(not main.libraryMode and main.editArea.presentationOpacity == 1)
    var fontSize: *PropertiesItem?
    for item in main.propWnd.grid.items where item!.typeValue.name == #nameof(FormText.fontSize) do
        fontSize = item
    Swag.assert(fontSize != null and fontSize.sliderBox.value() == 36)
    host.finishAnimations()
    Swag.assert(main.editArea.presentationOffset == Math.Point{})
}

// Enter applies a typed size through both editors; Escape keeps the document unchanged.
#[Swag.TestTag("capture.interaction")]
#test
{
    var host: Gui.Testing.HeadlessHost
    let main = testSetupEditorSurface(&host, dark: true)
    defer
    {
        main.libWnd.requestClose()
        host.shutdown()
        g_Main = null
    }

    let capture = unwrap main.getCapture()
    let text    = assume cast(*FormText, capture.forms[0])
    var size: *EditBox?
    for item in main.miniBar.items
    {
        if item.wnd is EditBox as edit do
            size = edit
    }

    Swag.assert(size != null)
    size.setFocus()
    size.setText("72")
    host.keyPress(.Return)
    Swag.assert(text.fontSize == 72)
    host.runFrames(1)

    size.setFocus()
    size.setText("999999")
    host.keyPress(.Return)
    Swag.assert(text.fontSize == 72)

    discard host.render(main)
    var fontSize: *PropertiesItem?
    for item in main.propWnd.grid.items where item!.typeValue.name == #nameof(FormText.fontSize) do
        fontSize = item
    Swag.assert(fontSize != null)
    scope
    {
        let edit = fontSize.sliderBox.edit
        edit.setFocus()
        edit.setText("36")
        host.keyPress(.Return)
        Swag.assert(Math.abs(text.fontSize - 36) < 0.01)
        Swag.assert(size.text() == "36" and size.isValid())
        var edited = host.render(main)
        capture.invalidateAllFormCaches()
        var fresh = host.render(main)
        Pixel.Testing.assertImagesNear(&fresh, &edited, "surface.typed-size", {maxChannelDelta: 2})
        edit.setFocus()
        edit.setText("24")
        host.keyPress(.Escape)
        Swag.assert(Math.abs(text.fontSize - 36) < 0.01)
    }

    host.keyPress(.Z, .Control)
    host.runFrames(1)
    Swag.assert(text.fontSize == 72 and size.text() == "72")
    host.keyPress(.Y, .Control)
    host.runFrames(1)
    Swag.assert(text.fontSize == 36 and size.text() == "36")
    size.setFocus()
    size.setText("80")
    main.updateMiniBar()
    Swag.assert(text.fontSize == 36 and size.text() == "80")
    host.keyPress(.Escape)
    Swag.assert(text.fontSize == 36 and size.text() == "36")
}

// Choosing a font names the same family in the document, inspector and mini-bar.
#[Swag.TestTag("capture.interaction")]
#test
{
    var host: Gui.Testing.HeadlessHost
    let main = testSetupEditorSurface(&host, dark: true)
    defer
    {
        main.libWnd.requestClose()
        host.shutdown()
        g_Main = null
    }

    let text = assume cast(*FormText, (unwrap main.getCapture()).forms[0])
    var face: *ComboBox?
    for item in main.miniBar.items
    {
        if item.wnd is ComboBox as combo do
            face = combo
    }

    Swag.assert(face != null)
    discard host.render(main)
    host.pump()
    var font: *PropertiesItem?
    for item in main.propWnd.grid.items where item!.typeValue.name == #nameof(FormText.fontName) do
        font = item
    Swag.assert(font != null and font.comboBox.items.count > 2)
    let first: String = font.comboBox.items[2]!.name.raw
    font.comboBox.setSelectedIndex(2)
    Swag.assert(text.fontName == first)
    Swag.assert(face.selectedItem()!.name.raw == first)

    let last: String = font.comboBox.items.back()!.name.raw
    font.comboBox.setSelectedIndex(cast(u32, font.comboBox.items.count - 1))
    Swag.assert(text.fontName == last and face.selectedItem()!.name.raw == last)
    main.editWnd.editView.setFocus()
    host.keyPress(.Z, .Control)
    host.runFrames(1)
    Swag.assert(text.fontName == first and face.selectedItem()!.name.raw == first)
    host.keyPress(.Y, .Control)
    host.runFrames(1)
    Swag.assert(text.fontName == last and face.selectedItem()!.name.raw == last)

    face.setSelectedIndex(0)
    host.runFrames(1)
    Swag.assert(text.fontName.isEmpty() and face.selectedIndex == 0)
    for item in main.propWnd.grid.items where item!.typeValue.name == #nameof(FormText.fontName) do
        Swag.assert(item.comboBox.selectedIndex == 0)
}

// The ground around the picture moves the window while a tool that draws is in hand: the
// picture, its edges, a form off the picture and what floats over the view keep their clicks,
// and the selection tool keeps the ground for its lasso.
#test
{
    var host: Gui.Testing.HeadlessHost
    let main = testSetupEditorSurface(&host, dark: true, text: false)
    defer
    {
        main.libWnd.requestClose()
        host.shutdown()
        g_Main = null
    }

    let view    = main.editWnd.editView
    let capture = unwrap main.getCapture()
    main.editMode = .Shape
    Swag.assert(host.surfaceWnd.groundHitTest != null)

    // The picture is placed by its first paint.
    discard host.render(main)

    let picture = capture.paintRect
    let origin  = view.surfaceRect()
    let middle  = Math.Point{origin.x + picture.horzCenter() - view.scrollPos.x, origin.y + picture.vertCenter() - view.scrollPos.y}
    let ground  = Math.Point{middle.x + picture.width * 0.5 + 40, middle.y}
    let edge    = Math.Point{middle.x + picture.width * 0.5 + 4, middle.y}
    Swag.assert(view.isWindowGround(ground))
    Swag.assert(not view.isWindowGround(middle))
    Swag.assert(not view.isWindowGround(edge))
    Swag.assert(not view.isWindowGround(main.dock.surfaceRect().center()))
    Swag.assert(not view.isWindowGround(main.inspector.surfaceRect().center()))

    // A form standing off the picture is work, not ground.
    let zoom = picture.width / capture.width
    discard testAddShape(capture, capture.width + 30 / zoom, capture.height * 0.5 - 10 / zoom, 20 / zoom, 20 / zoom)
    Swag.assert(not view.isWindowGround(ground))

    main.editMode = .Selection
    Swag.assert(not view.isWindowGround(Math.Point{ground.x, ground.y + 60}))
}

// The window is named after the capture on screen, by the name the library gives it, and after
// the application in the library.
#test
{
    var host: Gui.Testing.HeadlessHost
    let main = testSetupEditorSurface(&host, dark: true, text: false)
    defer
    {
        main.libWnd.requestClose()
        host.shutdown()
        g_Main = null
    }

    let capture = unwrap main.getCapture()
    capture.title = "Password"
    main.updateState()
    Swag.assert(host.surfaceWnd.name.raw == "Password")

    capture.title.clear()
    capture.sourceApplication = "Notepad"
    main.updateState()
    Swag.assert(host.surfaceWnd.name.raw == "Notepad")

    testEmptyTrash()
    g_Library.loaded = true
    main.swapLibraryMode()
    Swag.assert(host.surfaceWnd.name.raw == ProductName)
}

// Selects the forms `indices` of the capture the editor shows, lays the window out and renders it
// to `golden`; `whole` renders the surface with what floats over the view, such as a popover.
func testAssertEditGolden(host: *Gui.Testing.HeadlessHost, main: *MainWnd, indices: const [..] u64, golden: string, whole = false)
{
    let capture = unwrap main.getCapture()
    capture.selection.clear()
    for i in indices do
        capture.selection.add(i)
    capture.selectionHasChanged()
    main.applyLayout()
    host.finishAnimations()

    var image = whole ? host.render(&host.surfaceWnd) : host.render(main)
    Pixel.Testing.assertImageGolden(&image, golden)
}

// Collects the colour swatches of the head of the inspector, in display order.
func testCollectSwatches(wnd: *Wnd, result: *Array'(*IconButton))
{
    for child in wnd.children
    {
        if child is IconButton as button where button.flags.has(.Popup) do
            result.add(button)
        testCollectSwatches(child, result)
    }
}

// An arrow: the inspector with its line ends as glyph rows in both palettes.
#[Swag.TestTag("golden")]
#test
{
    for dark in [true, false]
    {
        var host: Gui.Testing.HeadlessHost
        let main = testSetupEditorSurface(&host, dark, text: false)
        defer
        {
            main.libWnd.requestClose()
            host.shutdown()
            g_Main = null
        }

        with let arrow = testAddArrow(unwrap main.getCapture(), 60, 190, 300, 70)
        {
            .borderColor = ColorRed
            .borderSize  = 6
            .endCap      = .ArrowAnchor
        }

        testAssertEditGolden(&host, main, [0], dark ? "edit.arrow" : "edit.arrow.paper")
    }
}

// Several objects: their common settings, the alignment, the order and the layers, in Encre.
#[Swag.TestTag("golden")]
#test
{
    var host: Gui.Testing.HeadlessHost
    let main = testSetupEditorSurface(&host, dark: true, text: false)
    defer
    {
        main.libWnd.requestClose()
        host.shutdown()
        g_Main = null
    }

    let capture = unwrap main.getCapture()
    discard testAddShape(capture, 30, 40, 150, 100)
    discard testAddShape(capture, 210, 40, 150, 100)
    let text = testAddText(capture, 90, 160, 200, 50)
    text.text = "Cards"
    testAssertEditGolden(&host, main, [0, 1, 2], "edit.multi")

    // Shapes and a text have no preset in common: the row of presets leaves. The head counts
    // each kind, one or several.
    Swag.assert(not main.quickWnd.isVisible())
    Swag.assert(main.inspector.title == "2 ellipses · 1 text")

    Swag.assert(MainWnd.countWords("% étape|% étapes", 1) == "1 étape" and MainWnd.countWords("% étape|% étapes", 3) == "3 étapes")

    // The layers list every object, the selected ones chosen; a row chooses its object alone.
    Swag.assert(capture.selection.count == 3)

    // A third kind is named too when the words fit before the actions of the head.
    discard testAddArrow(capture, 20, 200, 120, 220)
    capture.selection.add(3)
    capture.selectionHasChanged()
    main.updateState()
    let kinds = MainWnd.describeKinds(capture)
    Swag.assert(kinds == "2 ellipses · 1 text · 1 arrow")
    Swag.assert(main.inspector.title == (main.titleFits(kinds) ? kinds.toString() : "4 objects"))
}

// A step marker: its shapes and its number on the mini-bar, in Encre.
#[Swag.TestTag("golden")]
#test
{
    var host: Gui.Testing.HeadlessHost
    let main = testSetupEditorSurface(&host, dark: true, text: false)
    defer
    {
        main.libWnd.requestClose()
        host.shutdown()
        g_Main = null
    }

    let capture = unwrap main.getCapture()
    discard testAddStep(capture, 40, 40, 40, 40)
    discard testAddStep(capture, 300, 40, 40, 40)
    let third = testAddStep(capture, 160, 140, 40, 40)
    third.index = 3
    testAssertEditGolden(&host, main, [2], "edit.step")

    // The number on the mini-bar is the number of the selected marker.
    var found = false
    for item in main.miniBar.items
    {
        if item.wnd is Stepper as stepper
        {
            Swag.assert(stepper.value == 3)
            found = true
        }
    }

    Swag.assert(found)
}

// A mask: its kinds as a list with their glyphs, the pixelation chosen, in Encre.
#[Swag.TestTag("golden")]
#test
{
    var host: Gui.Testing.HeadlessHost
    let main = testSetupEditorSurface(&host, dark: true, text: false)
    defer
    {
        main.libWnd.requestClose()
        host.shutdown()
        g_Main = null
    }

    let mask = testAddImage(unwrap main.getCapture(), 60, 80, 280, 40)
    mask.kind = .Pixelate
    testAssertEditGolden(&host, main, [0], "edit.mask")
}

// The colour popover opened from the inspector: the recent colours, the palette, the exact value
// and the opacity, in Papier.
#[Swag.TestTag("golden")]
#test
{
    var host: Gui.Testing.HeadlessHost
    let main = testSetupEditorSurface(&host, dark: false, text: false)
    defer
    {
        main.libWnd.requestClose()
        host.shutdown()
        g_Main = null
    }

    let capture = unwrap main.getCapture()
    discard testAddShape(capture, 60, 60, 220, 110)
    main.recentColors.add(Color.fromArgb(0xFFE5484D))
    main.recentColors.add(Color.fromArgb(0xFFF59E0B))
    capture.selection.add(0)
    capture.selectionHasChanged()
    main.applyLayout()
    host.finishAnimations()

    var swatches: Array'(*IconButton)
    testCollectSwatches(main.propWnd.topLayout, &swatches)
    Swag.assert(not swatches.isEmpty())
    swatches[0].sigPopupRequested.call(swatches[0])
    host.finishAnimations()

    var image = host.render(&host.surfaceWnd)
    Pixel.Testing.assertImageGolden(&image, "edit.color.paper")
    swatches[0].hidePopup()
}

// Builds the in-place editor over a quiet desktop of the size of the host, with the zone grabbed
// at 300, 160, 440 by 240 and an arrow drawn on it, in `dark` or light.
func testSetupInPlace(host: *Gui.Testing.HeadlessHost, dark: bool)->*InPlaceEditWnd
{
    let main = testSetupSurfaceMain(host)
    if dark do
        host.theme.setDark()
    else do
        host.theme.setLight()
    host.theme.metrics.surfaceWnd_ShadowSize   = 0
    host.theme.metrics.surfaceWnd_CornerRadius = 0
    host.notify(.ThemeChanged)

    var desktop = Image.create(1024, 640, .BGRA8)
    desktop.fillGradient(Color.fromArgb(0xFF2A3350), Color.fromArgb(0xFF3A3346), Color.fromArgb(0xFF30293A), Color.fromArgb(0xFF5A3A2C))
    g_DesktopX, g_DesktopY = 0
    g_ScreenWidth          = 1024
    g_ScreenHeight         = 640
    g_StartGrabX           = 300
    g_StartGrabY           = 160
    g_EndGrabX             = 740
    g_EndGrabY             = 400

    with let capture = Memory.new'Capture()
    {
        .width          = 440
        .height         = 240
        .backImg        = desktop
        .backImagePos.x = -300
        .backImagePos.y = -160
        .inPlaceEdit    = true
    }

    with let arrow = testAddArrow(capture, 60, 190, 300, 70)
    {
        .borderColor = ColorRed
        .borderSize  = 6
        .endCap      = .ArrowAnchor
    }

    let editor = InPlaceEditWnd.create(capture, main, &host.surfaceWnd)
    editor.setPosition(host.surfaceWnd.clientRect())
    editor.applyLayout()
    host.runFrames(1)
    host.finishAnimations()
    return editor
}

// Editing in place, right after a capture: the desktop dimmed, the zone in full light with its
// edge and its size, the one bar under it, and the keys at the foot, in Encre and in Papier.
#[Swag.TestTag("golden")]
#test
{
    for dark in [true, false]
    {
        var host: Gui.Testing.HeadlessHost
        let editor = testSetupInPlace(&host, dark)
        defer
        {
            g_Main?.libWnd.requestClose()
            host.shutdown()
            g_Main = null
        }

        // One bar: the ten tools, the colour, the three destinations, Copy and the cross.
        Swag.assert(editor.bar.isLocallyVisible())
        Swag.assert(editor.bar.position.y >= editor.editWnd.editView.getCaptureRect().bottom())
        var image = host.render(editor)
        Pixel.Testing.assertImageGolden(&image, dark ? "inplace" : "inplace.paper")
    }
}

// The in-place bar follows capture bounds at either edge and after the host is resized.
#[Swag.TestTag("capture.interaction")]
#test
{
    var host: Gui.Testing.HeadlessHost
    let editor = testSetupInPlace(&host, dark: true)
    defer
    {
        g_Main?.libWnd.requestClose()
        host.shutdown()
        g_Main = null
    }

    let capture = unwrap editor.capture
    let zones: [3] Math.Rectangle = [{12, 12, 200, 100}, {812, 500, 200, 128}, {0, 0, 1024, 640}]
    for zone in zones
    {
        capture.backImagePos = {-zone.x, -zone.y}
        capture.width        = cast(s32, zone.width)
        capture.height       = cast(s32, zone.height)
        host.runFrames(1)
        let bar = editor.bar.position
        Swag.assert(bar.x >= 12 and bar.right() <= 1012)
        Swag.assert(bar.y >= 12 and bar.bottom() <= 628)
        if zone.height < 640 do
            Swag.assert(bar.bottom() <= zone.y or bar.y >= zone.bottom())
    }

    editor.resize(800, 600)
    host.runFrames(1)
    Swag.assert(editor.bar.position.right() <= 788 and editor.bar.position.bottom() <= 588)

    // A virtual desktop can extend past the captured monitor. Keep its bar on that
    // monitor even when centring on the capture would cross the display boundary.
    editor.barRoom       = {0, 0, 700, 600}
    capture.width, capture.height = 100
    capture.backImagePos = {-580, -180}
    host.runFrames(1)
    Swag.assert(editor.bar.position.right() <= 688)
}

// A callout whose words are typed in place: the field over its body, the hint of the tail, in
// Encre.
#[Swag.TestTag("golden")]
#test
{
    var host: Gui.Testing.HeadlessHost
    let main = testSetupEditorSurface(&host, dark: true, text: false)
    defer
    {
        main.libWnd.requestClose()
        host.shutdown()
        g_Main = null
    }

    let capture      = unwrap main.getCapture()
    with let callout = testAddCallout(capture, 60, 120, 220, 64)
    {
        .text      = "New panel"
        .backColor = ColorRed
        .tailX     = 180
        .tailY     = 60
    }

    capture.selection.add(0)
    capture.selectionHasChanged()
    main.applyLayout()
    main.editWnd.editView.beginTextEdit(callout)
    host.finishAnimations()
    Swag.assert(main.editWnd.editView.isEditingText() and callout.editingText)

    var image = host.render(main)
    Pixel.Testing.assertImageGolden(&image, "edit.callout")

    // Ending keeps the words as one step of the history.
    main.editWnd.editView.textLines[0].setText("New panels")
    main.editWnd.editView.endTextEdit()
    Swag.assert(callout.text == "New panels" and not callout.editingText)
    capture.undo()
    Swag.assert(callout.text == "New panel")
}

// A turned text of two lines set against the left edge, its words typed in place: the text
// stands level, each line a field against the left edge, in its face, its size and its ink, in
// Encre and in Papier.
#[Swag.TestTag("golden")]
#test
{
    for dark in [true, false]
    {
        var host: Gui.Testing.HeadlessHost
        let main = testSetupEditorSurface(&host, dark: dark, text: false)
        defer
        {
            main.libWnd.requestClose()
            host.shutdown()
            g_Main = null
        }

        let capture   = unwrap main.getCapture()
        with let text = testAddText(capture, 60, 50, 260, 130)
        {
            .text      = "Release\nnotes"
            .fontSize  = 40
            .backColor = ColorRed
            .alignHorz = .LeftTop
            .rotate    = 20
        }

        capture.selection.add(0)
        capture.selectionHasChanged()
        main.applyLayout()
        main.editWnd.editView.beginTextEdit(text)
        host.finishAnimations()
        Swag.assert(main.editWnd.editView.textLines.count == 2 and Math.isZeroEpsilon(text.rotate))

        var image = host.render(main)
        Pixel.Testing.assertImageGolden(&image, dark ? "edit.text" : "edit.text.paper")
        main.editWnd.editView.endTextEdit(keep: false)
    }
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
            .capture!.width = 1280
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

// The Library lens paints a selected rating with the theme's filled star glyph.
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

    let capture = testAddLibraryItem(main.libWnd.view, "rating.scc", 1000, 22)
    capture.capture!.rating = 3
    main.libWnd.view.selModel.select(0)
    main.libWnd.view.focusItem = 0
    main.lens.open()
    var ratingRow = Swag.U64.Max
    var steps = 0'u64
    for row, index in main.lens.rows
    {
        if row.entry == Lens.InlineRow and row.section.label == appStrings().act_Rating
        {
            ratingRow = index
            break
        }
        if row.entry == Lens.InlineRow or row.entry < row.section.entries.count do
            steps += 1
    }
    Swag.assert(ratingRow != Swag.U64.Max)
    for steps do
        host.keyPress(.Down)
    Swag.assert(main.lens.chosen == ratingRow)
    host.finishAnimations()

    var rating: *Lens.Section?
    for section in main.lens.results.sections where section and section.label == appStrings().act_Rating do
        rating = section
    Swag.assert(rating and rating.entries[3].paint != null)

    var image = host.render(main)
    Pixel.Testing.assertImageGolden(&image, "library.lens.rating")
    main.lens.close()
    host.finishAnimations()
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

// Starts typing the words of form `index` of the editor's capture, the way a double click does.
func testBeginInlineText(host: *Gui.Testing.HeadlessHost, main: *MainWnd, index: u64)->*EditView
{
    let view    = main.editWnd.editView
    let capture = unwrap main.getCapture()
    capture.selection.clear()
    capture.selection.add(index)
    capture.selectionHasChanged()
    view.beginTextEdit(capture.forms[index])
    host.pump()
    return view
}

// A text, not only a callout, has its words typed in place: Enter breaks the line, Ctrl+Enter
// keeps the words as one step of the history, Escape lets them go.
#test
{
    var host: Gui.Testing.HeadlessHost
    let main = testSetupEditorSurface(&host, dark: true)
    defer
    {
        main.libWnd.requestClose()
        host.shutdown()
        g_Main = null
    }

    let capture = unwrap main.getCapture()
    let text    = assume cast(*FormText, capture.forms[0])
    var view    = testBeginInlineText(&host, main, 0)
    Swag.assert(view.isEditingText() and text.editingText)
    Swag.assert(view.textLines.count == 1 and view.inlineText() == "Theme")

    // Enter breaks the line at the caret, which stands after the words.
    let first = view.textLines[0]
    Swag.assert(view.textLineKey(first, .Return, .None))
    Swag.assert(view.isEditingText() and view.textLines.count == 2)
    view.textLines[1].setText("Notes")
    Swag.assert(view.inlineText() == "Theme\nNotes")

    // Ctrl+Enter keeps them, as one step of the history.
    Swag.assert(view.textLineKey(view.textLines[1], .Return, .Control))
    Swag.assert(not view.isEditingText() and not text.editingText)
    Swag.assert(text.text == "Theme\nNotes")
    capture.undo()
    Swag.assert(text.text == "Theme")
    capture.redo()
    Swag.assert(text.text == "Theme\nNotes")

    // Escape lets the words go: nothing changes, nothing is added to the history.
    view = testBeginInlineText(&host, main, 0)
    view.textLines[0].setText("Gone")
    Swag.assert(view.textLineKey(view.textLines[0], .Escape, .None))
    Swag.assert(not view.isEditingText() and text.text == "Theme\nNotes")
    capture.undo()
    Swag.assert(text.text == "Theme")
    capture.redo()

    // Backspace at the start of a line joins it to the line above.
    view = testBeginInlineText(&host, main, 0)
    let second = view.textLines[1]
    second.setSelection(0, 0)
    Swag.assert(view.textLineKey(second, .Back, .None))
    Swag.assert(view.textLines.count == 1 and view.inlineText() == "ThemeNotes")

    // Selecting another form keeps the words, like a click elsewhere.
    capture.selection.clear()
    capture.selectionHasChanged()
    Swag.assert(not view.isEditingText() and text.text == "ThemeNotes")
}

// The label of a step is typed in place too, and Enter keeps it.
#test
{
    var host: Gui.Testing.HeadlessHost
    let main = testSetupEditorSurface(&host, dark: true, text: false)
    defer
    {
        main.libWnd.requestClose()
        host.shutdown()
        g_Main = null
    }

    let capture = unwrap main.getCapture()
    let step    = testAddStep(capture, 60, 60, 48, 48)
    step.index = 3

    let view = testBeginInlineText(&host, main, 0)
    Swag.assert(view.isEditingText() and step.editingText and view.inlineText() == "3")
    view.textLines[0].setText("7")
    Swag.assert(view.textLineKey(view.textLines[0], .Return, .None))
    Swag.assert(not view.isEditingText() and step.index == 7)
    capture.undo()
    Swag.assert(step.index == 3)

    // A step that counts in letters takes a letter.
    step.typeIndex = .LetterUp
    discard testBeginInlineText(&host, main, 0)
    Swag.assert(view.inlineText() == "C")
    view.textLines[0].setText("e")
    view.endTextEdit()
    Swag.assert(step.index == 5)
}

// A rotated form straightens while its words are typed, over a quick change of state, and turns
// back to its angle when they are kept or let go.
#test
{
    var host: Gui.Testing.HeadlessHost
    let main = testSetupEditorSurface(&host, dark: true)
    defer
    {
        main.libWnd.requestClose()
        host.shutdown()
        g_Main = null
    }

    host.setReducedMotion(false)
    let capture = unwrap main.getCapture()
    let text    = assume cast(*FormText, capture.forms[0])
    text.rotate = 30

    // Halfway through, the form is turning; at the end it stands level.
    let view  = testBeginInlineText(&host, main, 0)
    let quick = main.themeMetrics().motion_QuickSeconds
    host.advanceAnimations(quick * 0.5)
    Swag.assert(text.rotate > 0 and text.rotate < 30)
    host.finishAnimations()
    Swag.assert(Math.isZeroEpsilon(text.rotate))

    // Kept or let go, it turns back to its angle.
    view.endTextEdit(keep: false)
    host.advanceAnimations(quick * 0.5)
    Swag.assert(text.rotate > 0 and text.rotate < 30)
    host.finishAnimations()
    Swag.assert(Math.abs(text.rotate - 30) < 0.01)

    discard testBeginInlineText(&host, main, 0)
    host.finishAnimations()
    view.textLines[0].setText("Turned")
    view.endTextEdit()
    host.finishAnimations()
    Swag.assert(Math.abs(text.rotate - 30) < 0.01 and text.text == "Turned")
}

// The fields stand where the alignment of the form puts its words: against the left edge, about
// the centre, against the right edge.
#test
{
    var host: Gui.Testing.HeadlessHost
    let main = testSetupEditorSurface(&host, dark: true)
    defer
    {
        main.libWnd.requestClose()
        host.shutdown()
        g_Main = null
    }

    let capture = unwrap main.getCapture()
    let text    = assume cast(*FormText, capture.forms[0])
    let view    = main.editWnd.editView
    text.fontSize = 20

    var lefts:  [3] f32
    var rights: [3] f32
    for align, i in [FormTextAlign.LeftTop, FormTextAlign.Center, FormTextAlign.RightBottom]
    {
        text.alignHorz = align
        discard testBeginInlineText(&host, main, 0)
        lefts[i]  = view.textLines[0].position.x
        rights[i] = view.textLines[0].position.right()
        view.endTextEdit(keep: false)
    }

    let place = view.getCaptureRect()
    var rect  = view.textSpec.rect * view.zoom
    rect.offset(place.x - view.scrollPos.x, place.y - view.scrollPos.y)
    let words = Painter.measureStringSnapped(text.text, unwrap view.textFont.regular)
    Swag.assert(Math.abs(lefts[0] - rect.x) <= 1)
    Swag.assert(Math.abs(lefts[1] + words * 0.5 - rect.horzCenter()) <= 1)
    Swag.assert(Math.abs(lefts[2] + words - rect.right()) <= 1)
    Swag.assert(rights[0] - lefts[0] == rights[2] - lefts[2])
}

// The quick styles of every tool, one row each as the inspector shows the row of the tool in
// hand: each preset a small picture of the shape it draws, in its own colours, on the raised
// ground, the preset in force ringed in Arc, then the cell that keeps a new one; in Encre and
// in Papier.
#[Swag.TestTag("golden")]
#test
{
    for dark in [true, false]
    {
        var host: Gui.Testing.HeadlessHost
        let main = testSetupEditorSurface(&host, dark: dark, text: false)
        defer
        {
            main.libWnd.requestClose()
            host.shutdown()
            g_Main = null
        }

        // Two columns of tools, as the picture lays them out.
        const Modes      = [EditMode.Shape, EditMode.Arrow, EditMode.Highlight, EditMode.Text, EditMode.Callout, EditMode.Step, EditMode.Image]
        const Second     = 3
        const LabelWidth = 96.0
        const Pad        = 24.0
        let metrics    = main.themeMetrics()
        let strip      = 6 * QuickChipWidth
        with let panel = Wnd.create'Wnd(main, null, {0, 0, 1024, 640})
        {
            .backgroundStyle = .Window
        }

        var x = Pad
        var y = Pad
        for mode, index in Modes
        {
            if index == Second
            {
                x += LabelWidth + strip + 2 * Pad
                y = Pad
            }

            main.editMode = mode
            let quick = QuickWnd.create(panel, main)
            quick.setDefault()
            quick.setPosition(Math.Rectangle{x + LabelWidth, y, strip, QuickChipHeight})
            quick.updateQuickStyles(forceRebuild: true)
            Swag.assert(quick.layout.children.count > 1)
            Label.create(panel, MainWnd.editModeName(mode), Math.Rectangle{x, y, LabelWidth, QuickChipHeight}, flags: .SecondaryText)
            y += quick.position.height + metrics.inspector_RowGap
        }

        host.finishAnimations()
        var image = host.render(panel)
        Pixel.Testing.assertImageGolden(&image, dark ? "presets" : "presets.paper")
    }
}

// Capture, library and output actions stay at the door, including with no recent captures and
// while an annotation is selected. Selection actions follow these stable groups.
#test
{
    var host: Gui.Testing.HeadlessHost
    let main = testSetupEditorSurface(&host, dark: true)
    defer
    {
        main.libWnd.requestClose()
        host.shutdown()
        g_Main = null
    }

    let capture = unwrap main.getCapture()

    for selected in [false, true]
    {
        capture.selection.clear()
        if selected do
            capture.selection.add(0)
        main.updateState()
        main.lens.open()
        let sections = &main.lens.results.sections
        Swag.assert(sections[0]!.entries.count == 4)
        Swag.assert(sections[0]!.entries[0].id == ActionCapture.Area)
        Swag.assert(sections[0]!.entries[1].id == ActionCapture.LastArea)
        Swag.assert(sections[0]!.entries[2].id == ActionFile.OpenImage)
        Swag.assert(sections[0]!.entries[3].id == ActionGlobal.ShowLibrary)
        Swag.assert(sections[1]!.entries.count == 2)
        Swag.assert(sections[1]!.entries[0].id == ActionFile.SaveAsImage)
        Swag.assert(sections[1]!.entries[1].id == ActionCopyPaste.CopyAsImage)
        if selected do
            Swag.assert(not sections[2]!.entries.isEmpty())
        main.lens.close()
    }
}

// The lens as a reader meets it in the editor, with its stable capture and output actions.
#[Swag.TestTag("golden")]
#test
{
    var host: Gui.Testing.HeadlessHost
    let main = testSetupEditorSurface(&host, dark: true)
    defer
    {
        main.libWnd.requestClose()
        host.shutdown()
        g_Main = null
    }

    for query, index in ["", "arr"]
    {
        main.lens.open(query)
        host.finishAnimations()
        var image = host.render(main)
        Pixel.Testing.assertImageGolden(&image, index == 0 ? "showcase.lens.empty" : "showcase.lens.query")
        main.lens.close()
        host.finishAnimations()
    }
}

// The text mini-bar sets how the lines stand in the box: three glyphs across it, three down it,
// one of each group checked; a glyph down the box leaves the glyphs across it as they are.
#test
{
    var host: Gui.Testing.HeadlessHost
    let main = testSetupEditorSurface(&host, dark: true)
    defer
    {
        main.libWnd.requestClose()
        host.shutdown()
        g_Main = null
    }

    let capture = unwrap main.getCapture()
    let text    = assume cast(*FormText, capture.forms[0])
    capture.selectionHasChanged()
    main.updateMiniBar()

    var across, down: Array'(*IconButton)
    for item in main.miniBar.items
    {
        if item.wnd is IconButton as button where button.flags.has(.Radio)
        {
            if alignIsVertical(button.userData) do
                down.add(button)
            else do
                across.add(button)
        }
    }

    Swag.assert(across.count == 3 and down.count == 3)
    host.clickWnd(down[2])
    Swag.assert(text.alignVert == .RightBottom and text.alignHorz == .Center)
    Swag.assert(down[2].isChecked and not down[1].isChecked and across[1].isChecked)
}

// The keys of the editor: the arrows nudge the selection a pixel, ten with Shift; Delete deletes,
// Ctrl D duplicates, Ctrl G groups, ] and [ bring forward and back, Escape lets the selection go;
// with a selection, the hint line teaches them.
#test
{
    var host: Gui.Testing.HeadlessHost
    let main = testSetupEditorSurface(&host, dark: true)
    defer
    {
        main.libWnd.requestClose()
        host.shutdown()
        g_Main = null
    }

    Swag.assert(main.keyShortcut(.None, .Left) == ActionMoveSel.Left1)
    Swag.assert(main.keyShortcut(.Shift, .Left) == ActionMoveSel.Left)
    Swag.assert(main.keyShortcut(.None, .Delete) == ActionSelection.DeleteSelection)
    Swag.assert(main.keyShortcut(.Control, .D) == ActionCopyPaste.Duplicate)
    Swag.assert(main.keyShortcut(.Control, .G) == ActionGroup.Group)
    Swag.assert(main.keyShortcut(.None, .Oem6) == ActionAlign.MoveForward)
    Swag.assert(main.keyShortcut(.None, .Oem4) == ActionAlign.MoveBackward)
    Swag.assert(main.keyShortcut(.Control, .Oem6) == ActionAlign.SendToFront)
    Swag.assert(main.keyShortcut(.None, .Escape) == ActionSelection.DeSelectAll)
    Swag.assert(main.keyShortcutName(ActionCopyPaste.Duplicate) == "Ctrl D")

    // Every tool answers its letter, grouped or not.
    Swag.assert(main.keyShortcut(.None, .V) == ActionToolMode.Selection)
    Swag.assert(main.keyShortcut(.None, .L) == ActionToolMode.Line)
    Swag.assert(main.keyShortcut(.None, .X) == ActionToolMode.PixSel)
    Swag.assert(Input.formatKeyShortcut(.Control, .Oem6) == "Ctrl ]")

    // Tab walks the inspector from its quick styles down to its settings, where the arrows go
    // from row to row, and the mini-bar along its controls, in the order the eye reads them.
    let rows = Gui.FocusOrder.collect(main.inspector).stops
    Swag.assert(rows.count > 1 and rows.back() == main.propWnd.grid)
    for i in 1 until rows.count do
        Swag.assert(rows[i].surfaceRect().y >= rows[i - 1].surfaceRect().y)
    let bar = Gui.FocusOrder.collect(main.miniBar).stops
    Swag.assert(bar.count > 1)
    for i in 1 until bar.count do
        Swag.assert(bar[i].surfaceRect().x > bar[i - 1].surfaceRect().x)

    let capture = unwrap main.getCapture()
    let text    = assume cast(*FormText, capture.forms[0])
    let x       = text.x
    main.sendCommandEvent(ActionMoveSel.Right1)
    Swag.assert(text.x == x + 1)
    main.sendCommandEvent(ActionMoveSel.Right)
    Swag.assert(text.x == x + 1 + NudgeFar)

    main.fillHintLine()
    var taught = 0
    for hint in main.hintLine.hints where hint.text == appStrings().hint_Nudge or
                                          hint.text == appStrings().hint_Duplicate or
                                          hint.text == appStrings().hint_TypeWords do
        taught += 1
    Swag.assert(taught == 3)

    main.sendCommandEvent(ActionSelection.DeSelectAll)
    main.fillHintLine()
    for hint in main.hintLine.hints do
        Swag.assert(hint.text != appStrings().hint_Nudge)
}

// One selected object is named by the tool that draws it: a pixel selection and a highlighter
// stroke are not called a shape and a drawing.
#test
{
    var host: Gui.Testing.HeadlessHost
    let main = testSetupEditorSurface(&host, dark: true, text: false)
    defer
    {
        main.libWnd.requestClose()
        host.shutdown()
        g_Main = null
    }

    let capture = unwrap main.getCapture()
    discard testAddShape(capture, 20, 20, 80, 60, .PixSel)
    capture.selection.add(0)
    capture.selectionHasChanged()
    main.updateState()
    Swag.assert(main.inspector.title == appStrings().act_PixSel)
}

// Common task vocabulary reaches the real command in either shipped language.
#test
{
    var host: Gui.Testing.HeadlessHost
    let window = testSetupEditorSurface(&host, true)
    defer
    {
        window.libWnd.requestClose()
        host.shutdown()
        g_Main = null
    }

    defer discard catch g_App.setLanguage(ReferenceLanguage)
    for french in [false, true]
    {
        expect g_App.setLanguage(french ? "fr" : ReferenceLanguage)
        host.notify(.LanguageChanged)
        window.lens.open(french ? "copie ecran" : "screenshot")
        Swag.assert(window.lens.chosenEntry()!.id == ActionCapture.Area)
        window.lens.close()
        window.lens.open(french ? "historique" : "history")
        Swag.assert(window.lens.chosenEntry()!.id == ActionGlobal.ShowLibrary)
        window.lens.close()
        window.lens.open(french ? "exporter image" : "export image")
        Swag.assert(window.lens.chosenEntry()!.id == ActionFile.SaveAsImage)
        window.lens.close()
    }
}
