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
    Swag.require(host.app.dirtyTheme == revision and languageChanges == 0)

    main.editorOptions.theme    = .Light
    main.editorOptions.language = .French
    main.setTheme()
    main.setLanguage()
    languageChanges = 0
    let changedRevision = host.app.dirtyTheme
    restore(main, unwrap buffer.toSlice())
    Swag.require(host.app.dirtyTheme == changedRevision + 1 and languageChanges == 1)
    Swag.require(main.appearanceButton.appearanceTheme == .Dark)
    Swag.require(Application.language() == "en")
}

// Builds the shipped window on the surface root, including every application pane.
internal func testSetupSurfaceMain(host: *Gui.Testing.HeadlessHost, caption = false, dpiScale = 1'f32)->*MainWnd
{
    testUseScratchLibrary()
    host.setup(1024, 640, dpiScale)
    host.bindApplication(&g_App)
    registerAppStrings(&g_App.resources)
    registerAppStrings(&host.app.resources)
    if caption do
        host.surface.updateFlags(Gui.SurfaceFlags.StandardWindow)

    var monitors: Array'Env.Monitor
    let monitor = Math.Rectangle{0, 0, 1440, 900}
    monitors.add({bounds: monitor, workArea: monitor, scaleFactor: 1,
                  physicalBounds: monitor, physicalWorkArea: monitor})
    with let main = MainWnd.create(&host.surfaceWnd, &monitors)
    {
        .setPosition(host.surfaceWnd.paddedClientRect())
        .applyLayout()
    }

    return main
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

// The recent strip keeps its view controls beside the thumbnails and returns the editor's
// bottom readings to the resized work area whenever its height changes.
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

    let editorHeight = main.editArea.position.height
    Swag.require(main.keyShortcut(.CtrlShift, .H) == ActionView.Recent)
    Swag.require(not main.recentBar.isLocallyVisible())
    Swag.require(not main.editArea.wndFlags.has(.ClipChildren))

    host.shortcut(Input.Key.H, Input.KeyModifiers.Control | .Shift)
    host.finishAnimations()
    Swag.require(main.showRecent and main.recentBar.isLocallyVisible())
    Swag.require(main.editArea.position.height < editorHeight)
    Swag.require(main.recentBar.position.height == main.bottomHeight())
    Swag.require(main.sizeReading.surfaceRect().bottom() <= main.editArea.surfaceRect().bottom())
    Swag.require(main.zoomReading.surfaceRect().bottom() <= main.editArea.surfaceRect().bottom())

    host.clickWnd(main.recentSmall)
    Swag.require(main.bottomSize == .Small and main.recentSmall.isChecked)
    Swag.require(not main.recentMedium.isChecked and not main.recentBig.isChecked)
    host.clickWnd(main.recentMedium)
    Swag.require(main.bottomSize == .Medium and main.recentMedium.isChecked)
    host.clickWnd(main.recentBig)
    Swag.require(main.bottomSize == .Big and main.recentBig.isChecked)
    Swag.require(main.recentBar.position.height == main.bottomHeight())

    host.shortcut(Input.Key.H, Input.KeyModifiers.Control | .Shift)
    host.finishAnimations()
    Swag.require(not main.showRecent and not main.recentBar.isLocallyVisible())
    Swag.require(main.editArea.position.height == editorHeight)
    Swag.require(main.sizeReading.surfaceRect().bottom() <= main.editArea.surfaceRect().bottom())
    Swag.require(main.zoomReading.surfaceRect().bottom() <= main.editArea.surfaceRect().bottom())
}

// The selection tool only opens the inspector when an object has properties to inspect.
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
    main.editMode = .Selection
    main.updateState()
    Swag.require(not main.inspector.isLocallyVisible())
    Swag.require(not main.quickWnd.isVisible())

    discard testAddShape(capture, 20, 20, 80, 60)
    capture.selection.add(0)
    capture.selectionHasChanged()
    Swag.require(main.inspector.isLocallyVisible())
    Swag.require(main.inspector.title == appStrings().act_Shape)

    // The fixed style row and the property viewport balance against the inspector frame.
    // The scrollbar occupies only the extra room on the right of that viewport.
    let frame = main.inspector.surfaceRect()
    let quick = main.quickWnd.surfaceRect()
    let view = main.propWnd.grid.scrollWnd.view.surfaceRect()
    let pad = main.inspector.themeMetrics().scrollBar_HitSize + main.inspector.themeMetrics().scrollBar_EdgeInset
    Swag.require(Math.abs((quick.x - frame.x) - (frame.right() - quick.right())) <= 2)
    Swag.require(Math.abs((view.x + cast(f32, GridRowInset) - frame.x) - (frame.right() - view.right())) <= 2)
    Swag.require(Math.abs(view.x + cast(f32, GridRowInset) - frame.x - pad) <= 2)

    capture.selection.clear()
    capture.selectionHasChanged()
    Swag.require(not main.inspector.isLocallyVisible())

    main.editMode = .Arrow
    main.updateState()
    Swag.require(main.inspector.isLocallyVisible())
    Swag.require(main.inspector.title == appStrings().act_Arrow)
}

// Frequent actions stand in the top strip at the minimum width, in both languages and at a
// display scale: capture and the library after the command menu, the output before the window
// buttons, each control whole, and the title kept clear of both groups. Library works by
// pointer, and the library leaves the output of the picture out.
#test
{
    var host: Gui.Testing.HeadlessHost
    let main = testSetupEditorSurface(&host, dark: true, text: false, caption: true, dpiScale: 1.25)
    defer discard catch main.appearanceButton.setAppearanceLanguage(Gui.ReferenceLanguage)
    let strip = host.theme.metrics.wnd_StripHeight
    for language in [Gui.ReferenceLanguage, "fr"]
    {
        expect main.appearanceButton.setAppearanceLanguage(language)
        main.updateState()
        host.finishAnimations()
        main.applyLayout()

        let leading  = main.taskStrip.leading
        let trailing = main.taskStrip.trailing
        Swag.require(leading.children.count == 3 and trailing.children.count == 2)
        Swag.require(leading.children[0].name == appStrings().act_CaptureArea)
        Swag.require(not main.taskStrip.shortcutPanel.isLocallyVisible())
        Swag.require(not main.taskStrip.frozenPanel.isLocallyVisible())
        Swag.require(trailing.children[0].name == appStrings().act_SaveImage)
        Swag.require(trailing.children[1] == main.taskStrip.copyButton)
        Swag.require(main.taskStrip.copyButton.name == appStrings().act_CopyImage)
        Swag.require(main.taskStrip.copyButton.form == .Strong)

        // Both groups stand on the middle line of the strip, after the menu glyph and before
        // the window buttons, and leave the title its room between them.
        let room         = host.surfaceWnd.captionRoomRect()
        let leadingRect  = testRectInFrame(&host.surfaceWnd, leading)
        let trailingRect = testRectInFrame(&host.surfaceWnd, trailing)
        for rect in [leadingRect, trailingRect]
        {
            Swag.require(rect.y >= 0 and rect.bottom() <= strip)
            Swag.require(Math.abs(rect.vertCenter() - strip * 0.5) <= 1)
        }

        Swag.require(leadingRect.x >= main.menuLauncher.position.right())
        Swag.require(trailingRect.right() <= room.right() + 0.5)
        let title = host.surfaceWnd.captionContentRect()
        Swag.require(title.x >= leadingRect.right())
        Swag.require(title.right() <= trailingRect.x)
        Swag.require(title.width > 0)

        for bar in [leading, trailing]
        {
            var right = 0'f32
            for child in bar.children
            {
                Swag.require(child.isLocallyVisible())
                Swag.require(child.position.x >= right - host.theme.metrics.wnd_CaptionActionGap)
                Swag.require(child.position.width >= Math.floor(child.itf.measureContent({}).x))
                Swag.require(child.position.right() <= bar.clientRect().right() + 0.5)
                right = child.position.right()
            }
        }
    }

    host.clickWnd(main.taskStrip.leading.children[2])
    host.pump()
    Swag.require(main.libraryMode)
    Swag.require(not main.taskStrip.trailing.isLocallyVisible())
    Swag.require(host.surfaceWnd.captionContentRect().right() > host.surfaceWnd.captionRoomRect().right() - host.theme.metrics.wnd_CaptionMarginTitle - 0.5)
}

// The task controls send their commands to the window, and the copy is the editor's one primary
// action: it copies the finished picture, not the selection.
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

    var copies: u32
    main.hookOnEvent = func|copies = &copies|(_, evt)->bool
    {
        if evt is CommandEvent as cmd where cmd.id == ActionCopyPaste.CopyAsImage
        {
            copies[] += 1
            return true
        }

        return false
    }

    host.clickWnd(main.taskStrip.copyButton)
    host.pump()
    Swag.require(copies == 1)
    Swag.require(not main.taskStrip.copyButton.hasFocus())
}

// Returns where `wnd` stands in the local coordinates of the window frame.
func testRectInFrame(frame: *Gui.SurfaceWnd, wnd: *Gui.Wnd)->Math.Rectangle
{
    var result = wnd.surfaceRect()
    let origin = frame.surfaceRect()
    result.x -= origin.x
    result.y -= origin.y
    return result
}

// The editor starts without focus; a first key cannot activate a task-bar action.
#test
{
    var host: Gui.Testing.HeadlessHost
    let main = testSetupSurfaceMain(&host)
    defer
    {
        host.shutdown()
        g_Main = null
    }

    host.recordCommands()
    Swag.require(main.focusedWindow() == null)
    for bar in [main.taskStrip.leading, main.taskStrip.trailing]
    {
        for button in bar.children
        {
            Swag.require(button.focusPolicy == .None)
            Swag.require(not button.hasFocus())
        }
    }

    host.keyPress(.Space)
    Swag.require(host.commandCount == 0)
    Swag.require(not main.editWnd.editView.hasFocus())
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

    Swag.require(not main.appearanceButton.isLocallyVisible())

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

        // The lens names a command in full when it has a longer name than its control shows.
        let title = state.updatedFields.has(.LongName) and not state.longName.isEmpty() ? state.longName : state.name
        Swag.require(titles.contains(title), title)
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
    host.click({300, 300}, Input.MouseButton.Right)
    host.pump()
    Swag.require(capture.forms.count == 2 and capture.selection.count == 1)
    main.editWnd.editView.setFocus()
    host.keyPress(.Z, .Control)
    Swag.require(capture.forms.count == 1)
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
    Swag.require(main.libraryMode and main.libWnd.presentationOpacity == 1)
    Swag.require(not main.libWnd.view.hasFocus())
    Swag.require(main.propWnd.topLayout.children[0] == controls)
    text.fontSize = 36
    main.swapLibraryMode()
    Swag.require(not main.libraryMode and main.editArea.presentationOpacity == 1)
    Swag.require(not main.editWnd.editView.hasFocus())
    var fontSize: *PropertiesItem?
    for item in main.propWnd.grid.items where item!.typeValue.name == #nameof(FormText.fontSize) do
        fontSize = item
    Swag.require(fontSize != null and fontSize.sliderBox.value() == 36)
    host.finishAnimations()
    Swag.require(main.editArea.presentationOffset == Math.Point{})
}

// A preset changes text size from the mini-bar; exact sizes stay editable in the inspector.
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
    let size    = unwrap main.miniBarFontSize
    host.clickWnd(size)
    let sizePopup = unwrap main.textChoicePopover
    Swag.require(sizePopup.kind == .Size and sizePopup.list.lineCount() == TextChoiceSizes.count)
    sizePopup.list.selectLine(6)
    Swag.require(text.fontSize == 72)
    host.runFrames(1)
    Swag.require(size.text() == "72")

    discard host.render(main)
    var fontSize: *PropertiesItem?
    for item in main.propWnd.grid.items where item!.typeValue.name == #nameof(FormText.fontSize) do
        fontSize = item
    Swag.require(fontSize != null)
    scope
    {
        let edit = fontSize.sliderBox.edit
        edit.setFocus()
        edit.setText("36")
        host.keyPress(.Return)
        Swag.require(Math.abs(text.fontSize - 36) < 0.01)
        Swag.require(size.text() == "36")
        var edited = host.render(main)
        capture.invalidateAllFormCaches()
        var fresh = host.render(main)
        Pixel.Testing.assertImagesNear(&fresh, &edited, "surface.typed-size", {maxChannelDelta: 2})
        edit.setFocus()
        edit.setText("24")
        host.keyPress(.Escape)
        Swag.require(Math.abs(text.fontSize - 36) < 0.01)
    }

    host.keyPress(.Z, .Control)
    host.runFrames(1)
    Swag.require(text.fontSize == 72 and size.text() == "72")
    host.keyPress(.Y, .Control)
    host.runFrames(1)
    Swag.require(text.fontSize == 36 and size.text() == "36")
}

// A callout uses the same size menu and writes its own property type.
#[Swag.TestTag("capture.interaction")]
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
    let callout = testAddCallout(capture, 50, 50, 200, 70)
    capture.selection.add(0)
    capture.selectionHasChanged()
    main.updateState()

    let size = unwrap main.miniBarFontSize
    host.clickWnd(size)
    let popup = unwrap main.textChoicePopover
    popup.list.selectLine(7)
    host.runFrames(1)
    Swag.require(callout.fontSize == 96 and size.text() == "96")
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
    let face = unwrap main.miniBarFontFace
    let size = unwrap main.miniBarFontSize
    Swag.require(face.position.height == size.position.height and face.arrowPosition == size.arrowPosition)
    discard host.render(main)
    host.pump()
    var font: *PropertiesItem?
    for item in main.propWnd.grid.items where item!.typeValue.name == #nameof(FormText.fontName) do
        font = item
    Swag.require(font != null and font.comboBox.items.count > 2)
    let first: String = font.comboBox.items[2]!.name.raw
    font.comboBox.setSelectedIndex(2)
    Swag.require(text.fontName == first)
    Swag.require(face.text() == first.toString())

    let last: String = font.comboBox.items.back()!.name.raw
    font.comboBox.setSelectedIndex(cast(u32, font.comboBox.items.count - 1))
    Swag.require(text.fontName == last and face.text() == last.toString())
    main.editWnd.editView.setFocus()
    host.keyPress(.Z, .Control)
    host.runFrames(1)
    Swag.require(text.fontName == first and face.text() == first.toString())
    host.keyPress(.Y, .Control)
    host.runFrames(1)
    Swag.require(text.fontName == last and face.text() == last.toString())

    host.clickWnd(face)
    let popup      = unwrap main.textChoicePopover
    let filter     = unwrap popup.filter
    let fullHeight = (unwrap popup.parent).position.height
    filter.setText("__missing_font__")
    Swag.require(popup.list.lineCount() == 0)
    Swag.require(popup.parent.position.height < fullHeight)
    filter.setText(main.theme().res.defaultTypeFaceR.familyName())
    Swag.require(popup.list.lineCount() > 0)
    host.keyPress(.Down)
    Swag.require(popup.list.hasFocus())
    host.keyPress(.Return)
    host.runFrames(1)
    Swag.require(text.fontName.isEmpty() and face.text() == main.theme().res.defaultTypeFaceR.familyName())
    Swag.require(main.textChoicePopover == null)
    for item in main.propWnd.grid.items where item!.typeValue.name == #nameof(FormText.fontName) do
        Swag.require(item.comboBox.selectedIndex == 0)
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
    Swag.require(host.surfaceWnd.groundHitTest != null)

    // The picture is placed by its first paint.
    discard host.render(main)

    let picture = capture.paintRect
    let origin  = view.surfaceRect()
    let middle  = Math.Point{origin.x + picture.horzCenter() - view.scrollPos.x, origin.y + picture.vertCenter() - view.scrollPos.y}
    let ground  = Math.Point{middle.x + picture.width * 0.5 + 40, middle.y}
    let edge    = Math.Point{middle.x + picture.width * 0.5 + 4, middle.y}
    Swag.require(view.isWindowGround(ground))
    Swag.require(not view.isWindowGround(middle))
    Swag.require(not view.isWindowGround(edge))
    Swag.require(not view.isWindowGround(main.dock.surfaceRect().center()))
    Swag.require(not view.isWindowGround(main.inspector.surfaceRect().center()))

    // A form standing off the picture is work, not ground.
    let zoom = picture.width / capture.width
    discard testAddShape(capture, capture.width + 30 / zoom, capture.height * 0.5 - 10 / zoom, 20 / zoom, 20 / zoom)
    Swag.require(not view.isWindowGround(ground))

    main.editMode = .Selection
    Swag.require(not view.isWindowGround(Math.Point{ground.x, ground.y + 60}))
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
    Swag.require(host.surfaceWnd.name.raw == "Password")

    capture.title.clear()
    capture.sourceApplication = "Notepad"
    main.updateState()
    Swag.require(host.surfaceWnd.name.raw == "Notepad")

    testEmptyTrash()
    g_Library.loaded = true
    main.swapLibraryMode()
    Swag.require(host.surfaceWnd.name.raw == ProductName)
}

// Builds the in-place editor over a quiet desktop of the size of the host, with the zone grabbed
// at 300, 160, 440 by 240 and an arrow drawn on it, in `dark` or light.
internal func testSetupInPlace(host: *Gui.Testing.HeadlessHost, dark: bool)->*InPlaceEditWnd
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
    g_CaptureMedia         = .Picture

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
        Swag.require(bar.x >= 12 and bar.right() <= 1012)
        Swag.require(bar.y >= 12 and bar.bottom() <= 628)
        if zone.height < 640 do
            Swag.require(bar.bottom() <= zone.y or bar.y >= zone.bottom())
    }

    editor.resize(1000, 600)
    host.runFrames(1)
    Swag.require(editor.bar.position.right() <= 988 and editor.bar.position.bottom() <= 588)

    // A virtual desktop can extend past the captured monitor. Keep its bar on that
    // monitor even when centring on the capture would cross the display boundary.
    editor.barRoom       = {0, 0, 900, 600}
    capture.width, capture.height = 100
    capture.backImagePos = {-580, -180}
    host.runFrames(1)
    Swag.require(editor.bar.position.right() <= 888)
}

// Something that must not leave the screen is hidden in place, before the copy: the bar has a
// pixelate tool, and a drag with it lays a pixelation over the zone.
#[Swag.TestTag("capture.interaction")]
#test
{
    var host: Gui.Testing.HeadlessHost
    let editor = testSetupInPlace(&host, dark: false)
    defer
    {
        g_Main?.libWnd.requestClose()
        host.shutdown()
        g_Main = null
    }

    var pixelate: *Gui.IconButton?
    for item in editor.bar.items
    {
        if item.wnd is Gui.IconButton as button where button.flags.has(.Radio) and enumFromUserData'InPlaceEditMode(button.userData) == .Pixelate do
            pixelate = button
    }

    let button = unwrap pixelate
    Swag.require(button.toolTip == appStrings().tip_InpPixelate)
    host.clickWnd(button)
    host.pump()
    Swag.require(editor.editMode == .Pixelate and button.isChecked)
    Swag.require(editor.newMain.editMode == .Image and editor.newMain.mdlFormImage.kind == .Pixelate)

    let capture = unwrap editor.capture
    let count   = capture.forms.count
    let view    = editor.editWnd.editView
    let zone    = view.getCaptureRect()
    var start   = view.localToSurface(Math.Point{zone.x + 40 - view.scrollPos.x, zone.y + 40 - view.scrollPos.y})
    var end     = view.localToSurface(Math.Point{zone.x + 160 - view.scrollPos.x, zone.y + 90 - view.scrollPos.y})
    let surface = unwrap view.surface
    surface.surfaceToScreen(&start)
    surface.surfaceToScreen(&end)
    host.drag(start, end)
    Swag.require(capture.forms.count == count + 1)
    let made = capture.forms.back()
    Swag.require(made is FormImage)
    Swag.require((assume cast(*FormImage, made)).kind == .Pixelate)
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
        Swag.require(rendered.isValid())
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
    Swag.require(view.isEditingText() and text.editingText)
    Swag.require(view.textLines.count == 1 and view.inlineText() == "Theme")

    // Enter breaks the line at the caret, which stands after the words.
    let first = view.textLines[0]
    Swag.require(view.textLineKey(first, .Return, .None))
    Swag.require(view.isEditingText() and view.textLines.count == 2)
    view.textLines[1].setText("Notes")
    Swag.require(view.inlineText() == "Theme\nNotes")

    // Ctrl+Enter keeps them, as one step of the history.
    Swag.require(view.textLineKey(view.textLines[1], .Return, .Control))
    Swag.require(not view.isEditingText() and not text.editingText)
    Swag.require(text.text == "Theme\nNotes")
    capture.undo()
    Swag.require(text.text == "Theme")
    capture.redo()
    Swag.require(text.text == "Theme\nNotes")

    // Escape lets the words go: nothing changes, nothing is added to the history.
    view = testBeginInlineText(&host, main, 0)
    view.textLines[0].setText("Gone")
    Swag.require(view.textLineKey(view.textLines[0], .Escape, .None))
    Swag.require(not view.isEditingText() and text.text == "Theme\nNotes")
    capture.undo()
    Swag.require(text.text == "Theme")
    capture.redo()

    // Backspace at the start of a line joins it to the line above.
    view = testBeginInlineText(&host, main, 0)
    let second = view.textLines[1]
    second.setSelection(0, 0)
    Swag.require(view.textLineKey(second, .Back, .None))
    Swag.require(view.textLines.count == 1 and view.inlineText() == "ThemeNotes")

    // Selecting another form keeps the words, like a click elsewhere.
    capture.selection.clear()
    capture.selectionHasChanged()
    Swag.require(not view.isEditingText() and text.text == "ThemeNotes")
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
    Swag.require(view.isEditingText() and step.editingText and view.inlineText() == "3")
    view.textLines[0].setText("7")
    Swag.require(view.textLineKey(view.textLines[0], .Return, .None))
    Swag.require(not view.isEditingText() and step.index == 7)
    capture.undo()
    Swag.require(step.index == 3)

    // A step that counts in letters takes a letter.
    step.typeIndex = .LetterUp
    discard testBeginInlineText(&host, main, 0)
    Swag.require(view.inlineText() == "C")
    view.textLines[0].setText("e")
    view.endTextEdit()
    Swag.require(step.index == 5)
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
    Swag.require(text.rotate > 0 and text.rotate < 30)
    host.finishAnimations()
    Swag.require(Math.isZeroEpsilon(text.rotate))

    // Kept or let go, it turns back to its angle.
    view.endTextEdit(keep: false)
    host.advanceAnimations(quick * 0.5)
    Swag.require(text.rotate > 0 and text.rotate < 30)
    host.finishAnimations()
    Swag.require(Math.abs(text.rotate - 30) < 0.01)

    discard testBeginInlineText(&host, main, 0)
    host.finishAnimations()
    view.textLines[0].setText("Turned")
    view.endTextEdit()
    host.finishAnimations()
    Swag.require(Math.abs(text.rotate - 30) < 0.01 and text.text == "Turned")
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
    Swag.require(Math.abs(lefts[0] - rect.x) <= 1)
    Swag.require(Math.abs(lefts[1] + words * 0.5 - rect.horzCenter()) <= 1)
    Swag.require(Math.abs(lefts[2] + words - rect.right()) <= 1)
    Swag.require(rights[0] - lefts[0] == rights[2] - lefts[2])
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
        Swag.require(sections[0]!.entries.count == 5)
        Swag.require(sections[0]!.entries[0].id == ActionCapture.Area)
        Swag.require(sections[0]!.entries[1].id == ActionCapture.Record)
        Swag.require(sections[0]!.entries[2].id == ActionCapture.LastArea)
        Swag.require(sections[0]!.entries[3].id == ActionFile.OpenImage)
        Swag.require(sections[0]!.entries[4].id == ActionGlobal.ShowLibrary)
        Swag.require(sections[1]!.entries.count == 2)
        Swag.require(sections[1]!.entries[0].id == ActionFile.SaveAsImage)
        Swag.require(sections[1]!.entries[1].id == ActionCopyPaste.CopyAsImage)
        if selected do
            Swag.require(not sections[2]!.entries.isEmpty())
        main.lens.close()
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

    Swag.require(across.count == 3 and down.count == 3)
    host.clickWnd(down[2])
    Swag.require(text.alignVert == .RightBottom and text.alignHorz == .Center)
    Swag.require(down[2].isChecked and not down[1].isChecked and across[1].isChecked)
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

    Swag.require(main.keyShortcut(.None, .Left) == ActionMoveSel.Left1)
    Swag.require(main.keyShortcut(.Shift, .Left) == ActionMoveSel.Left)
    Swag.require(main.keyShortcut(.None, .Delete) == ActionSelection.DeleteSelection)
    Swag.require(main.keyShortcut(.Control, .D) == ActionCopyPaste.Duplicate)
    Swag.require(main.keyShortcut(.Control, .G) == ActionGroup.Group)
    Swag.require(main.keyShortcut(.None, .Oem6) == ActionAlign.MoveForward)
    Swag.require(main.keyShortcut(.None, .Oem4) == ActionAlign.MoveBackward)
    Swag.require(main.keyShortcut(.Control, .Oem6) == ActionAlign.SendToFront)
    Swag.require(main.keyShortcut(.None, .Escape) == ActionSelection.DeSelectAll)
    Swag.require(main.keyShortcutName(ActionCopyPaste.Duplicate) == "Ctrl D")

    // Every tool answers its letter, grouped or not.
    Swag.require(main.keyShortcut(.None, .V) == ActionToolMode.Selection)
    Swag.require(main.keyShortcut(.None, .L) == ActionToolMode.Line)
    Swag.require(main.keyShortcut(.None, .X) == ActionToolMode.PixSel)
    Swag.require(Input.formatKeyShortcut(.Control, .Oem6) == "Ctrl ]")

    // Tab walks the inspector from its quick styles down to its settings, where the arrows go
    // from row to row, and the mini-bar along its controls, in the order the eye reads them.
    let rows = Gui.FocusOrder.collect(main.inspector).stops
    Swag.require(rows.count > 1 and rows.back() == main.propWnd.grid)
    for i in 1 until rows.count do
        Swag.require(rows[i].surfaceRect().y >= rows[i - 1].surfaceRect().y)
    let bar = Gui.FocusOrder.collect(main.miniBar).stops
    Swag.require(bar.count > 1)
    for i in 1 until bar.count do
        Swag.require(bar[i].surfaceRect().x > bar[i - 1].surfaceRect().x)

    let capture = unwrap main.getCapture()
    let text    = assume cast(*FormText, capture.forms[0])
    let x       = text.x
    main.sendCommandEvent(ActionMoveSel.Right1)
    Swag.require(text.x == x + 1)
    main.sendCommandEvent(ActionMoveSel.Right)
    Swag.require(text.x == x + 1 + NudgeFar)

    main.fillHintLine()
    var taught = 0
    for hint in main.hintLine.hints where hint.text == appStrings().hint_Nudge or
                                          hint.text == appStrings().hint_Duplicate or
                                          hint.text == appStrings().hint_TypeWords do
        taught += 1
    Swag.require(taught == 3)

    main.sendCommandEvent(ActionSelection.DeSelectAll)
    main.fillHintLine()
    for hint in main.hintLine.hints do
        Swag.require(hint.text != appStrings().hint_Nudge)
}

// The size and zoom readings open the existing image and camera commands.
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

    Swag.require(main.sizeReading.text() == "400 × 240")
    Swag.require(main.zoomReading.text() == "100 %")
    Swag.require(main.sizeReading.arrowPosition == .RightUpward)
    Swag.require(main.zoomReading.arrowPosition == .RightUpward)

    // The zoom menu runs the existing fit command and refreshes the displayed percentage.
    main.editWnd.editView.setZoom(0.5)
    Swag.require(main.zoomReading.text() == "50 %")
    host.clickPopupMenuItemWhenShown(ActionZoom.ZoomFit)
    host.clickWnd(main.zoomReading)
    Swag.require(main.editWnd.editView.zoom > 0.5)

    // Choosing Resize Image from the size menu reaches its dialog; cancel keeps the canvas.
    host.clickPopupMenuItemWhenShown(ActionImage.ResizeImage)
    host.thenClickModalButton(Dialog.BtnCancel)
    host.clickWnd(main.sizeReading)
    Swag.require(main.getCapture()!.width == 400 and main.getCapture()!.height == 240)
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
    Swag.require(main.inspector.title == appStrings().act_PixSel)
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
        Swag.require(window.lens.chosenEntry()!.id == ActionCapture.Area)
        window.lens.close()
        window.lens.open(french ? "historique" : "history")
        Swag.require(window.lens.chosenEntry()!.id == ActionGlobal.ShowLibrary)
        window.lens.close()
        window.lens.open(french ? "exporter image" : "export image")
        Swag.require(window.lens.chosenEntry()!.id == ActionFile.SaveAsImage)
        window.lens.close()
    }
}

// The mini-bar changes sides before its upper position enters the opaque caption strip.
#test
{
    var host: Gui.Testing.HeadlessHost
    let main = testSetupEditorSurface(&host, dark: false, text: false, caption: true)
    defer
    {
        main.libWnd.requestClose()
        host.shutdown()
        g_Main = null
    }

    let capture = unwrap main.getCapture()
    let view    = main.editWnd.editView
    view.setZoom(3)
    let place  = view.getCaptureRect()
    let corner = main.editArea.surfaceToLocal(view.localToSurface(Math.Point{place.x - view.scrollPos.x, place.y - view.scrollPos.y}))
    let strip  = main.editArea.stripInset()
    let gap    = main.themeMetrics().miniBar_Distance
    let height = main.miniBar.bodySize().y
    let y      = (strip + gap + height * 0.5 - corner.y) / view.zoom
    discard testAddShape(capture, 60, y, 48, 24)
    capture.selection.add(0)
    capture.selectionHasChanged()
    main.updateState()
    host.finishAnimations()

    let selected = main.selectionSurfaceRect()
    let top      = main.editArea.surfaceToLocal(selected.topLeft()).y
    let bar      = main.miniBar.position
    Swag.require(top > strip and top - gap - height >= gap)
    Swag.require(top - gap - height < strip)
    Swag.require(bar.y >= strip and bar.y >= top + selected.height)
}

// The mini-bar of a form against a side edge of the capture stands within the picture rather
// than across its edge, and the colour it opens hangs from the button that opened it.
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
    discard testAddShape(capture, 0, 100, 24, 24)
    capture.selection.add(0)
    capture.selectionHasChanged()
    main.applyLayout()
    main.updateState()
    host.finishAnimations()

    let view    = main.editWnd.editView
    let place   = view.getCaptureRect()
    let picture = view.localToSurface(Math.Point{place.x - view.scrollPos.x, place.y - view.scrollPos.y})
    let bar     = main.miniBar.surfaceRect()
    Swag.require(main.miniBar.isLocallyVisible())
    Swag.require(bar.x >= picture.x and bar.right() <= picture.x + place.width)

    var swatch: *IconButton?
    for item in main.miniBar.items
    {
        if item.wnd is IconButton as button where button.flags.has(.Popup)
        {
            swatch = button
            break
        }
    }

    let button = unwrap swatch
    button.sigPopupRequested.call(button)
    host.finishAnimations()
    // The popover stands by the button that opened it, without covering it.
    button.hidePopup()
    host.clickWnd(button)
    host.pump()
    host.finishAnimations()
    let popover = unwrap testFindColorPopover(&host.surfaceWnd)
    let frame   = (unwrap popover.parent).surfaceRect()
    let anchor  = button.surfaceRect()
    Swag.require(not frame.intersects(anchor))
    var near = anchor
    near.inflate(16)
    Swag.require(frame.intersects(near))
    button.hidePopup()
}

// Returns the colour popover open under `wnd`, if any.
internal func testFindColorPopover(wnd: *Gui.Wnd)->*ColorPopover?
{
    for child in wnd.children
    {
        if child is ColorPopover as popover do
            return popover
        if let found = testFindColorPopover(child) do
            return found
    }

    return null
}

// The dock shows the tool in hand, whatever the selection holds: a text chosen while the arrow is
// in hand leaves the arrow in its cell, since the next drag draws an arrow; the selection tool
// takes the cell back once it is in hand.
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

    for mode in [EditMode.Arrow, EditMode.Callout, EditMode.Selection]
    {
        main.editMode = mode
        main.updateState()
        let active = unwrap main.dock.activeTool()
        Swag.require(active.id == MainWnd.toolCommand(mode))
        Swag.require(main.inspector.title == appStrings().act_Text)
    }
}

// An empty library says so and offers the first capture beside the sentence, as its primary
// action; its hint line keeps the lens alone, with nothing yet to open, delete or rate. The
// recycle bin, empty as well, is not a place to capture into.
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

    // The page as it stands with nothing in the library, whatever the shared sandbox holds.
    main.swapLibraryMode()
    host.pump()
    let libWnd = main.libWnd
    libWnd.view.stopLoading()
    libWnd.view.items.clear()
    libWnd.view.allItems.clear()
    libWnd.updateEmptyState()
    let button = unwrap libWnd.emptyCapture
    Swag.require(button.isLocallyVisible() and button.form == .Strong)
    Swag.require(button.name == appStrings().act_CaptureArea)
    Swag.require(libWnd.hintLine.hints.count == 1)

    var captures: u32
    main.hookOnEvent = func|captures = &captures|(_, evt)->bool
    {
        if evt is CommandEvent as cmd where cmd.id == ActionCapture.Area
        {
            captures[] += 1
            return true
        }

        return false
    }

    host.clickWnd(button)
    host.pump()
    Swag.require(captures == 1)

    libWnd.trashMode = true
    libWnd.updateEmptyState()
    Swag.require(not button.isLocallyVisible())
}

// An editor without a capture, as at the start of an empty library, keeps its zoom when the
// inspector shows or hides instead of measuring a capture it does not have.
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

    let view = main.editWnd.editView
    Swag.require(view.capture == null)
    view.setZoom(2)
    Swag.require(view.zoom == 2)
}

// The bar of a fresh zone starts with what the zone becomes. Choosing the animation fills it with
// the options of the recording and Record, keeps what was drawn, and Enter then starts the
// recording; Tab gives the picture and its tools back.
#[Swag.TestTag("capture.interaction")]
#test
{
    var host: Gui.Testing.HeadlessHost
    let editor = testSetupInPlace(&host, dark: false)
    defer
    {
        g_CaptureMedia = .Picture
        g_Main?.libWnd.requestClose()
        host.shutdown()
        g_Main = null
    }

    func kinds(editor: *InPlaceEditWnd)->*KindSegments?
    {
        for item in editor.bar.items
        {
            if item.wnd is KindSegments as seg do
                return seg
        }

        return null
    }

    func chips(editor: *InPlaceEditWnd)->u32
    {
        var count = 0'u32
        for item in editor.bar.items where item.wnd is OptionChip do
            count += 1
        return count
    }

    g_CaptureMedia = .Picture
    editor.setMedia(.Picture)
    Swag.require(chips(editor) == 0)
    var markerButton: *IconButton?
    for item in editor.bar.items
    {
        if item.wnd is IconButton as button where button.flags.has(.Radio) and
           enumFromUserData'InPlaceEditMode(button.userData) == .Marker
        {
            markerButton = button
            break
        }
    }
    host.clickWnd(unwrap markerButton)
    Swag.require(editor.editMode == .Marker)
    let forms = editor.capture!.forms.count
    Swag.require(forms > 0)

    // A click on the second kind makes the zone an animation.
    let seg = unwrap kinds(editor)
    var pos = seg.surfaceRect()
    let at  = seg.segmentRect(1)
    var evt = Gui.MouseEvent{kind: .Pressed, button: .Left, surfacePos: {pos.x + at.horzCenter(), pos.y + at.vertCenter()}}
    seg.sendEvent(&evt)
    Swag.require(g_CaptureMedia == .Picture and seg.hot == 1)
    evt.kind = .Released
    evt.surfacePos.x = pos.x - 10
    seg.sendEvent(&evt)
    Swag.require(g_CaptureMedia == .Picture and seg.hot == -1)
    evt.kind = .Pressed
    evt.surfacePos.x = pos.x + at.horzCenter()
    seg.sendEvent(&evt)
    evt.kind = .Released
    seg.sendEvent(&evt)
    host.runFrames(1)
    host.finishAnimations()
    Swag.require(g_CaptureMedia == .Animation)
    Swag.require(chips(editor) == 4)
    Swag.require(editor.editMode == .Select and editor.newMain.editMode == .Selection)
    Swag.require(editor.capture.forms.count == forms)

    // The cursor option changes the capture setting.
    var cursorChip: *OptionChip?
    for item in editor.bar.items
    {
        if item.wnd is OptionChip as chip where not chip.inert
        {
            cursorChip = chip
            break
        }
    }

    let cursor = editor.source.captureOptions.captureCursor
    host.clickWnd(unwrap cursorChip)
    host.pump()
    Swag.require(editor.source.captureOptions.captureCursor != cursor)
    editor.source.captureOptions.captureCursor = cursor

    // The cadence is available at the zone, cycles through the offered rates, and feeds the
    // option used by the next recording.
    var rateChip: *OptionChip?
    for item in editor.bar.items
    {
        if item.wnd is OptionChip as chip where chip.toolTip == appStrings().tip_AimRate
        {
            rateChip = chip
            break
        }
    }
    let rate = editor.source.captureOptions.recordRate
    for 3
    {
        let expected = editor.source.captureOptions.recordRate.next()
        host.clickWnd(unwrap rateChip)
        host.pump()
        Swag.require(editor.source.captureOptions.recordRate == expected)
        Swag.require(rateChip.label == Format.toString(appStrings().ui_AimRate, expected.framesPerSecond()))
    }
    Swag.require(editor.source.captureOptions.recordRate == rate)

    // Tab gives the picture back, with its tools.
    var key = Gui.KeyEvent{kind: .Pressed, key: .Tab}
    editor.sendEvent(&key)
    Swag.require(g_CaptureMedia == .Picture and chips(editor) == 0)
    Swag.require(editor.editMode == .Marker and editor.newMain.editMode == .Draw)

    // In an animation, Enter starts the recording of the zone.
    editor.setMedia(.Animation)
    g_Exit, g_GrabDone = false
    key.key = .Return
    editor.sendEvent(&key)
    Swag.require(g_Exit and g_GrabDone)
}

// Recording a fresh zone hands what was drawn on it to the animation. The in-place editor still
// receives frames while the recording runs, after its capture has left: it must not reach for it.
#[Swag.TestTag("capture.interaction")]
#test
{
    var host: Gui.Testing.HeadlessHost
    let editor = testSetupInPlace(&host, dark: false)
    defer
    {
        g_CaptureMedia = .Picture
        g_Main?.libWnd.requestClose()
        host.shutdown()
        g_Main = null
    }

    editor.setMedia(.Animation)
    let zone  = unwrap editor.capture
    let forms = zone.forms.count
    Swag.require(forms > 0)

    // As the grab does once Record is chosen: the view lets the zone go, and the zone is recorded.
    editor.editWnd.editView.capture = null
    editor.capture = null
    editor.placeBar()
    testEndRecordingAfter(20, cancel: false)
    let area = Math.Rectangle{-zone.backImagePos.x, -zone.backImagePos.y,
                              cast(f32, zone.width), cast(f32, zone.height)}
    let capture = expect recordZone(editor.source, zone, CaptureTarget.create(desktopToScreenRect(area), 0))
    testEndRecording()

    let result = unwrap capture
    let file   = String.from(result.file)
    defer catch Capture.deleteFiles(file)
    defer Memory.delete(result)

    Swag.require(result.media == .Animation and result.width == 440 and result.height == 240)
    Swag.require(result.forms.count == forms)
    for form in result.forms do
        Swag.require(form.capture == result)
}

// The colour popover of the inspector stays open while the colour changes, by a swatch or by the
// opacity, and a click outside it closes it.
#[Swag.TestTag("capture.interaction")]
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
    capture.selection.add(0)
    capture.selectionHasChanged()
    main.applyLayout()
    host.finishAnimations()

    var swatches: Array'(*IconButton)
    testCollectSwatches(main.propWnd.topLayout, &swatches)
    host.clickWnd(swatches[0])
    host.pump()
    host.finishAnimations()

    var popover = unwrap testFindColorPopover(&host.surfaceWnd)
    var color   = popover.color
    color.a = 128
    popover.apply(color)
    host.runFrames(2)
    Swag.require(testFindColorPopover(&host.surfaceWnd) != null)

    popover = unwrap testFindColorPopover(&host.surfaceWnd)
    host.clickWnd(popover.swatches[5])
    host.runFrames(2)
    Swag.require(testFindColorPopover(&host.surfaceWnd) != null)

    testClickViewCorner(&host, main)
    host.runFrames(2)
    Swag.require(testFindColorPopover(&host.surfaceWnd) == null)
}

// The colour popover of the bar over a selected form closes on a click outside it.
#[Swag.TestTag("capture.interaction")]
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
    capture.selection.add(0)
    capture.selectionHasChanged()
    main.applyLayout()
    main.updateState()
    host.finishAnimations()

    var swatch: *IconButton?
    for item in main.miniBar.items
    {
        if item.wnd is IconButton as button where button.flags.has(.Popup)
        {
            swatch = button
            break
        }
    }

    host.clickWnd(unwrap swatch)
    host.pump()
    host.finishAnimations()
    let popover = unwrap testFindColorPopover(&host.surfaceWnd)
    var color   = popover.color
    color.a = 128
    popover.apply(color)
    host.runFrames(2)
    Swag.require(testFindColorPopover(&host.surfaceWnd) != null)

    testClickViewCorner(&host, main)
    host.runFrames(2)
    Swag.require(testFindColorPopover(&host.surfaceWnd) == null)
}

// Clicks the top left corner of the edit view, away from the popovers and the selection.
internal func testClickViewCorner(host: *Gui.Testing.HeadlessHost, main: *MainWnd)
{
    let view = main.editWnd.editView
    let rect = view.surfaceRect()
    var pt   = Math.Point{rect.x + 8, rect.y + 8}
    view.surface!.surfaceToScreen(&pt)
    host.click(pt)
}
