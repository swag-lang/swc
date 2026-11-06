#global if #command == Swag.CompilerCommand.Test
#global private

using Core.Serialization
using Swag, Core

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
        Swag.require(menu != null)
        Swag.require(not button.icon.isValid())
        Swag.require(menu.themeMetrics().menuPopup_IconSize == themeRowIconSize(main.themeMetrics()))
        var image = host.render(main)
        Pixel.Testing.assertImageGolden(&image, golden)
        let menuDismissed = host.dismissPopupMenu()
        Swag.require(menuDismissed)
        captured[] = true
    }

    button.sigPressed.call(cast(*Button, button))
    Swag.require(captured)
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
            Swag.require(sheet.activateRow(link))
            host.finishAnimations()
        }

        var image = host.render(main)
        Pixel.Testing.assertImageGolden(&image, golden)
        sheet.close()
        captured[] = true
    }

    button.sigPressed.call(cast(*Button, button))
    host.app.sigFrame.clear()
    Swag.require(captured)
    host.pump()
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

// Names of the captures of the library golden.
const LibraryGoldenTitles = ["Side panel", "Error bubble", "Swag lexer", "Dark explorer", "Password"]

// The task row and command entrance in the shipped frame, at the minimum width and 125% scale.
#[Swag.TestTag("golden")]
#test
{
    let dark = false
    var host: Gui.Testing.HeadlessHost
    let main = testSetupEditorSurface(&host, dark, text: false, caption: true, dpiScale: 1.25)
    defer discard catch main.appearanceButton.setAppearanceLanguage(Gui.ReferenceLanguage)
    expect main.appearanceButton.setAppearanceLanguage(dark ? Gui.ReferenceLanguage : "fr")
    main.updateState()
    host.finishAnimations()
    var image = host.render(&host.surfaceWnd)
    Pixel.Testing.assertImageGolden(&image, dark ? "tasks.frame.encre" : "tasks.frame.fr.papier")
}

// The caption glyph opens the generated application menu beside the mark in Encre.
#[Swag.TestTag("golden")]
#test
{
    var host: Gui.Testing.HeadlessHost
    let main = testSetupEditorSurface(&host, dark: true, caption: true)
    defer
    {
        main.libWnd.requestClose()
        host.shutdown()
        g_Main = null
    }

    var captured: bool
    host.app.sigFrame += func|host = &host, captured = &captured|(_)
    {
        if captured[] do
            return
        let menu = host.capturedPopupMenu()
        Swag.require(menu and menu.items.count > 0)
        host.finishAnimations()
        var image = host.render(&host.surfaceWnd)
        Pixel.Testing.assertImageGolden(&image, "appmenu.root.encre")
        Swag.require(host.dismissPopupMenu())
        captured[] = true
    }

    main.menuLauncher.sigPressed.call(cast(*Button, main.menuLauncher))
    host.app.sigFrame.clear()
    Swag.require(captured)
    host.pump()
}

// Common capture actions stay one click from the root; the long settings get separate branches.
#[Swag.TestTag("golden")]
#test
{
    var host: Gui.Testing.HeadlessHost
    let main = testSetupEditorSurface(&host, dark: true, caption: true)
    defer
    {
        main.libWnd.requestClose()
        host.shutdown()
        g_Main = null
    }

    var captured: bool
    host.app.sigFrame += func|host = &host, captured = &captured|(_)
    {
        if captured[] do
            return
        Swag.require(host.openPopupSubMenu(appStrings().ui_MenuCapture))
        host.finishAnimations()
        var image = host.render(&host.surfaceWnd)
        Pixel.Testing.assertImageGolden(&image, "appmenu.capture.encre")
        Swag.require(host.dismissPopupMenu())
        captured[] = true
    }

    main.menuLauncher.sigPressed.call(cast(*Button, main.menuLauncher))
    host.app.sigFrame.clear()
    Swag.require(captured)
    host.pump()
}

// A nested capture choice stays within the window in Papier and keeps each menu level legible.
#[Swag.TestTag("golden")]
#test
{
    var host: Gui.Testing.HeadlessHost
    let main = testSetupEditorSurface(&host, dark: false, caption: true)
    defer
    {
        main.libWnd.requestClose()
        host.shutdown()
        g_Main = null
    }

    var captured: bool
    host.app.sigFrame += func|host = &host, captured = &captured|(_)
    {
        if captured[] do
            return
        Swag.require(host.openPopupSubMenu(appStrings().ui_MenuCapture))
        Swag.require(host.openPopupSubMenu(appStrings().act_DelayBefore))
        host.finishAnimations()
        var image = host.render(&host.surfaceWnd)
        Pixel.Testing.assertImageGolden(&image, "appmenu.delay.papier")
        Swag.require(host.clickPopupMenuItem(ActionCaptureDelay.Delay0))
        captured[] = true
    }

    main.menuLauncher.sigPressed.call(cast(*Button, main.menuLauncher))
    host.app.sigFrame.clear()
    Swag.require(captured)
    host.pump()
}

// Image operations use direct rows with one section break, without another popup level.
#[Swag.TestTag("golden")]
#test
{
    var host: Gui.Testing.HeadlessHost
    let main = testSetupEditorSurface(&host, dark: false, caption: true)
    defer
    {
        main.libWnd.requestClose()
        host.shutdown()
        g_Main = null
    }

    var captured: bool
    host.app.sigFrame += func|host = &host, captured = &captured|(_)
    {
        if captured[] do
            return
        Swag.require(host.openPopupSubMenu(appStrings().ui_MenuImage))
        host.finishAnimations()
        var image = host.render(&host.surfaceWnd)
        Pixel.Testing.assertImageGolden(&image, "appmenu.image.papier")
        Swag.require(host.dismissPopupMenu())
        captured[] = true
    }

    main.menuLauncher.sigPressed.call(cast(*Button, main.menuLauncher))
    host.app.sigFrame.clear()
    Swag.require(captured)
    host.pump()
}

// The View family holds the current surface and zoom actions without old recent-strip sizes.
#[Swag.TestTag("golden")]
#test
{
    var host: Gui.Testing.HeadlessHost
    let main = testSetupEditorSurface(&host, dark: true, caption: true)
    defer
    {
        main.libWnd.requestClose()
        host.shutdown()
        g_Main = null
    }

    var captured: bool
    host.app.sigFrame += func|host = &host, captured = &captured|(_)
    {
        if captured[] do
            return
        Swag.require(host.openPopupSubMenu(appStrings().ui_MenuView))
        host.finishAnimations()
        var image = host.render(&host.surfaceWnd)
        Pixel.Testing.assertImageGolden(&image, "appmenu.view.encre")
        Swag.require(host.dismissPopupMenu())
        captured[] = true
    }

    main.menuLauncher.sigPressed.call(cast(*Button, main.menuLauncher))
    host.app.sigFrame.clear()
    Swag.require(captured)
    host.pump()
}

// The shared application menu offers each theme directly as an exclusive choice.
#[Swag.TestTag("golden")]
#test
{
    var host: Gui.Testing.HeadlessHost
    let main = testSetupEditorSurface(&host, dark: true, caption: true)
    defer
    {
        main.libWnd.requestClose()
        host.shutdown()
        g_Main = null
    }

    var captured: bool
    host.app.sigFrame += func|host = &host, captured = &captured|(_)
    {
        if captured[] do
            return
        Swag.require(host.openPopupSubMenu(Gui.strings().lens_Application))
        Swag.require(host.openPopupSubMenu(Gui.strings().appearance_Theme))
        host.finishAnimations()
        var image = host.render(&host.surfaceWnd)
        Pixel.Testing.assertImageGolden(&image, "appmenu.theme.encre")
        Swag.require(host.dismissPopupMenu())
        captured[] = true
    }

    main.menuLauncher.sigPressed.call(cast(*Button, main.menuLauncher))
    host.app.sigFrame.clear()
    Swag.require(captured)
    host.pump()
}

// The language submenu lists the system choice and every registered language in Papier.
#[Swag.TestTag("golden")]
#test
{
    var host: Gui.Testing.HeadlessHost
    let main = testSetupEditorSurface(&host, dark: false, caption: true)
    defer
    {
        main.libWnd.requestClose()
        host.shutdown()
        g_Main = null
    }

    var captured: bool
    host.app.sigFrame += func|host = &host, captured = &captured|(_)
    {
        if captured[] do
            return
        Swag.require(host.openPopupSubMenu(Gui.strings().lens_Application))
        Swag.require(host.openPopupSubMenu(Gui.strings().appearance_Language))
        host.finishAnimations()
        var image = host.render(&host.surfaceWnd)
        Pixel.Testing.assertImageGolden(&image, "appmenu.language.papier")
        Swag.require(host.dismissPopupMenu())
        captured[] = true
    }

    main.menuLauncher.sigPressed.call(cast(*Button, main.menuLauncher))
    host.app.sigFrame.clear()
    Swag.require(captured)
    host.pump()
}

// Right-clicking a selection opens the editor's contextual actions in Encre.
#[Swag.TestTag("golden")]
#test
{
    let dark = true
    var host: Gui.Testing.HeadlessHost
    let main = testSetupEditorSurface(&host, dark)
    defer
    {
        main.libWnd.requestClose()
        host.shutdown()
        g_Main = null
    }

    var captured: bool
    host.app.sigFrame += func|host = &host, main, captured = &captured|(_)
    {
        if captured[] do
            return
        Swag.require(host.capturedPopupMenu() != null)
        var image = host.render(main)
        Pixel.Testing.assertImageGolden(&image, "edit.context-menu")
        Swag.require(host.dismissPopupMenu())
        captured[] = true
    }

    host.click({300, 300}, Input.MouseButton.Right)
    Swag.require(captured)
}

// Font size opens in the same widget-backed choice popup as the face, in Encre.
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

    let button = unwrap main.miniBarFontSize
    host.clickWnd(button)
    let popup = unwrap main.textChoicePopover
    Swag.require(popup.list.lineCount() == TextChoiceSizes.count)
    host.finishAnimations()
    var image = host.render(main)
    Pixel.Testing.assertImageGolden(&image, "edit.text-size-menu")
    button.hidePopup()
}

// The font choice has the same attached list and a real search field above it, in Papier.
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

    let button = unwrap main.miniBarFontFace
    host.clickWnd(button)
    let popup  = unwrap main.textChoicePopover
    let filter = unwrap popup.filter
    Swag.require(popup.list.scrollWnd.scrollSize.y > popup.list.position.height)
    filter.setText(main.theme().res.defaultTypeFaceR.familyName())
    Swag.require(popup.list.lineCount() > 0 and filter.hasFocus())
    host.finishAnimations()
    var image = host.render(main)
    Pixel.Testing.assertImageGolden(&image, "edit.font-choice.paper")
    button.hidePopup()
}

// The selection tool leaves the canvas clear until an object is chosen, in Encre.
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

    main.editMode = .Selection
    main.updateState()
    Swag.require(not main.inspector.isLocallyVisible())
    var image = host.render(main)
    Pixel.Testing.assertImageGolden(&image, "edit.selection.empty")
}

// An arrow: the inspector with its line ends as glyph rows in Papier.
#[Swag.TestTag("golden")]
#test
{
    let dark = false
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
    Swag.require(not main.quickWnd.isVisible())
    Swag.require(main.inspector.title == "2 ellipses · 1 text")

    Swag.require(MainWnd.countWords("% étape|% étapes", 1) == "1 étape" and MainWnd.countWords("% étape|% étapes", 3) == "3 étapes")

    // The layers list every object, the selected ones chosen; a row chooses its object alone.
    Swag.require(capture.selection.count == 3)

    // A third kind is named too when the words fit before the actions of the head.
    discard testAddArrow(capture, 20, 200, 120, 220)
    capture.selection.add(3)
    capture.selectionHasChanged()
    main.updateState()
    let kinds = MainWnd.describeKinds(capture)
    Swag.require(kinds == "2 ellipses · 1 text · 1 arrow")
    Swag.require(main.inspector.title == (main.titleFits(kinds) ? kinds.toString() : "4 objects"))
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
            Swag.require(stepper.value == 3)
            found = true
        }
    }

    Swag.require(found)
}

// A mask over varied screenshot pixels: its pixelation, edge, and kind choices in Encre.
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
    capture.backImg.fillGradient(Color.fromArgb(0xFFF2E9DF), Color.fromArgb(0xFF4E79B4), Color.fromArgb(0xFFD5745A), Color.fromArgb(0xFF2A436D))
    capture.backImg.visitPixels()
    {
        if x >= 80 and x < 320 and y >= 98 and y < 146 and x % 28 < 18 and y % 16 < 6 do
            cast(*u32, pix)[] = Color.fromArgb(0xFF233049).argb
    }

    let mask = testAddImage(capture, 60, 80, 280, 40)
    mask.kind = .Pixelate
    testAssertEditGolden(&host, main, [0], "edit.mask")

    // The overflow keeps the last image styles reachable without a stranded second row.
    let more = unwrap main.quickWnd.moreButton
    Swag.require(more.isLocallyVisible())
    main.quickWnd.openAllPresets(more)
    host.finishAnimations()
    var image = host.render(&host.surfaceWnd)
    Pixel.Testing.assertImageGolden(&image, "edit.mask.presets")
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
    Swag.require(not swatches.isEmpty())
    swatches[0].sigPopupRequested.call(swatches[0])
    host.finishAnimations()

    var image = host.render(&host.surfaceWnd)
    Pixel.Testing.assertImageGolden(&image, "edit.color.paper")
    swatches[0].hidePopup()
}

// Editing in place, right after a capture: the desktop dimmed, the zone in full light with its
// edge and its size, the one bar under it, and the keys at the foot, in Encre.
#[Swag.TestTag("golden")]
#test
{
    let dark   = true
    var host: Gui.Testing.HeadlessHost
    let editor = testSetupInPlace(&host, dark)
    defer
    {
        g_Main?.libWnd.requestClose()
        host.shutdown()
        g_Main = null
    }

    // One bar: the ten tools, the colour, the three destinations, Copy and the cross.
    Swag.require(editor.bar.isLocallyVisible())
    Swag.require(editor.bar.position.y >= editor.editWnd.editView.getCaptureRect().bottom())
    var image = host.render(editor)
    Pixel.Testing.assertImageGolden(&image, dark ? "inplace" : "inplace.paper")
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
    Swag.require(main.editWnd.editView.isEditingText() and callout.editingText)

    var image = host.render(main)
    Pixel.Testing.assertImageGolden(&image, "edit.callout")

    // Ending keeps the words as one step of the history.
    main.editWnd.editView.textLines[0].setText("New panels")
    main.editWnd.editView.endTextEdit()
    Swag.require(callout.text == "New panels" and not callout.editingText)
    capture.undo()
    Swag.require(callout.text == "New panel")
}

// A turned text of two lines set against the left edge, its words typed in place: the text
// stands level, each line a field against the left edge, in its face, its size and its ink, in
// Papier.
#[Swag.TestTag("golden")]
#test
{
    let dark = false
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
    Swag.require(main.editWnd.editView.textLines.count == 2 and Math.isZeroEpsilon(text.rotate))

    var image = host.render(main)
    Pixel.Testing.assertImageGolden(&image, dark ? "edit.text" : "edit.text.paper")

    let scroll = main.propWnd.grid.scrollWnd
    scroll.setScrollPos(0, scroll.scrollSize.y)
    host.finishAnimations()
    Swag.require(scroll.scrollPosition().y > 0)
    image = host.render(main)
    Pixel.Testing.assertImageGolden(&image, "edit.text.scrolled.paper")
    main.editWnd.editView.endTextEdit(keep: false)
}

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
    lib.view.hotItem = 2
    lib.refreshAutomaticFilters(force: true)
    main.applyLayout()

    // The page stands on the ground of the window, its header clear of the strip.
    Swag.require(main.libWnd.backgroundStyle == .Window)
    Swag.require(main.libWnd.captureHost.backgroundStyle == .Transparent)
    Swag.require(main.libWnd.header.surfaceRect().y >= main.libWnd.surfaceRect().y + main.libWnd.stripInset())

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
    var steps     = 0'u64
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

    Swag.require(ratingRow != Swag.U64.Max)
    for steps do
        host.keyPress(.Down)
    Swag.require(main.lens.chosen == ratingRow)
    host.finishAnimations()

    var rating: *Lens.Section?
    for section in main.lens.results.sections where section and section.label == appStrings().act_Rating do
        rating = section
    Swag.require(rating and rating.entries[3].paint != null)

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

// The quick styles of every tool with saved presets, as the inspector shows the row of the tool in
// hand: each preset a small picture of the shape it draws, in its own colours, on the raised
// ground, the preset in force ringed in Arc, then the cell that keeps a new one; in Encre.
#[Swag.TestTag("golden")]
#test
{
    let dark = true
    var host: Gui.Testing.HeadlessHost
    let main = testSetupEditorSurface(&host, dark: dark, text: false)
    defer
    {
        main.libWnd.requestClose()
        host.shutdown()
        g_Main = null
    }

    // Two columns of tools, as the picture lays them out.
    const Modes = [EditMode.Shape, EditMode.Arrow, EditMode.Line, EditMode.Polygon, EditMode.Draw, EditMode.Highlight,
                   EditMode.Text, EditMode.Callout, EditMode.Step, EditMode.Image, EditMode.PixSel]
    const Second     = 6
    const LabelWidth = 108.0
    const Pad        = 24.0
    let metrics    = main.themeMetrics()
    let strip      = 6 * QuickChipWidth
    with let panel = Wnd.create'Wnd(main, null, {0, 0, 1024, 640})
    {
        .backgroundStyle = .Window
    }

    var hoverCell: *QuickButton?
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
        Swag.require(quick.layout.children.count > 1)
        if mode == .Shape do
            hoverCell = quick.rowCells()[0]
        Label.create(panel, MainWnd.editModeName(mode), Math.Rectangle{x, y, LabelWidth, QuickChipHeight}, flags: .SecondaryText)
        y += quick.position.height + metrics.inspector_RowGap
        Swag.require(y <= panel.position.height)
    }

    host.finishAnimations()
    var image = host.render(panel)
    Pixel.Testing.assertImageGolden(&image, dark ? "presets" : "presets.paper")

    let cell = unwrap hoverCell
    host.moveMouse(cell.surfaceRect().center())
    host.finishAnimations()
    image = host.render(panel)
    Pixel.Testing.assertImageGolden(&image, dark ? "presets.hover" : "presets.hover.paper")
}

// The shape overflow in Papier shows the light, dark, filled and outlined choices on one
// consistent chip ground, with the same menu geometry as the editor.
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

    main.editMode = .Shape
    main.updateState()
    main.quickWnd.updateQuickStyles(forceRebuild: true)
    let more = unwrap main.quickWnd.moreButton
    Swag.require(more.isLocallyVisible())
    main.quickWnd.openAllPresets(more)
    host.finishAnimations()
    Swag.require((assume cast(*PresetPopover, unwrap main.quickWnd.allPresets)).columns == 4)

    var image = host.render(&host.surfaceWnd)
    Pixel.Testing.assertImageGolden(&image, "edit.shape.presets.paper")
}

// A selected form whose properties are not saved leads the QuickStyle strip, ahead of saved
// presets, with a separate plus that keeps that style. Papier shows the state.
#[Swag.TestTag("golden")]
#test
{
    let dark = false
    var host: Gui.Testing.HeadlessHost
    let main = testSetupEditorSurface(&host, dark: dark, text: false)
    defer
    {
        main.libWnd.requestClose()
        host.shutdown()
        g_Main = null
    }

    let capture = unwrap main.getCapture()
    let shape   = testAddShape(capture, 64, 48, 72, 48)
    shape.borderColor = Argb.Blue
    capture.selection.add(capture.forms.count - 1)
    capture.selectionHasChanged()
    main.quickWnd.updateQuickStyles(forceRebuild: true)
    host.finishAnimations()

    var image = host.render(main)
    Pixel.Testing.assertImageGolden(&image, dark ? "quickstyle.selection.encre" : "quickstyle.selection.paper")
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

// Quiet readings at the bottom of the real editor open upward without joining the window edge.
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

    testAssertLibraryMenuGolden(&host, main, main.sizeReading, "editor.menu.size.paper")
    host.app.sigFrame.clear()
    testAssertLibraryMenuGolden(&host, main, main.zoomReading, "editor.menu.zoom.paper")
}
