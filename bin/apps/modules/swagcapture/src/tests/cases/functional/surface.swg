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

    with let main = MainWnd.create(&host.surfaceWnd)
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

    capture.selection.clear()
    capture.selectionHasChanged()
    Swag.require(not main.inspector.isLocallyVisible())

    main.editMode = .Arrow
    main.updateState()
    Swag.require(main.inspector.isLocallyVisible())
    Swag.require(main.inspector.title == appStrings().act_Arrow)
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
        Swag.require(main.taskBar.children.count == 5)
        Swag.require(main.taskBar.children[0].name == appStrings().act_CaptureArea)
        Swag.require(main.taskBar.children[0].position.width > 100)
        Swag.require(main.taskBar.children[0].isLocallyVisible())
        var right = 0'f32
        for child in main.taskBar.children
        {
            Swag.require(child.position.x >= right)
            Swag.require(child.position.width >= Math.floor(child.itf.measureContent({}).x))
            Swag.require(child.position.right() <= main.taskBar.clientRect().right())
            right = child.position.right()
        }
    }

    host.click(main.taskBar.children[2].surfaceRect().center())
    host.pump()
    Swag.require(main.libraryMode)
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
    for button in main.taskBar.children
    {
        Swag.require(button.focusPolicy == .None)
        Swag.require(not button.hasFocus())
    }
    Swag.require(main.captureChoice.focusPolicy == .None and not main.captureChoice.hasFocus())

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
        Swag.require(titles.contains(state.name), state.name)
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
    let size = unwrap main.miniBarFontSize
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
    let popup  = unwrap main.textChoicePopover
    let filter = unwrap popup.filter
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

    editor.resize(800, 600)
    host.runFrames(1)
    Swag.require(editor.bar.position.right() <= 788 and editor.bar.position.bottom() <= 588)

    // A virtual desktop can extend past the captured monitor. Keep its bar on that
    // monitor even when centring on the capture would cross the display boundary.
    editor.barRoom       = {0, 0, 700, 600}
    capture.width, capture.height = 100
    capture.backImagePos = {-580, -180}
    host.runFrames(1)
    Swag.require(editor.bar.position.right() <= 688)
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
        Swag.require(sections[0]!.entries.count == 4)
        Swag.require(sections[0]!.entries[0].id == ActionCapture.Area)
        Swag.require(sections[0]!.entries[1].id == ActionCapture.LastArea)
        Swag.require(sections[0]!.entries[2].id == ActionFile.OpenImage)
        Swag.require(sections[0]!.entries[3].id == ActionGlobal.ShowLibrary)
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
