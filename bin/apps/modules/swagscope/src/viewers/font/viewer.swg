#global internal
#global namespace Viewers.Typeface

using Core, Pixel, Gui, TrueType

// Offers the glyph surface for an sfnt font with TrueType outlines, whatever it is called.
//
// The version number of such a font is `1.0` written as a fixed-point number, which is why the
// signature is four bytes rather than four letters. `ttcf` opens a collection of them, and `true`
// is what an older Apple font writes in the same place. The probe leaves the `OTTO` signature of
// CFF-flavoured OpenType fonts unclaimed, although the shared font engine can load them.
private func pluginProbe(content: Viewer.ProbeContent)->bool
{
    if content.startsWith("ttcf") or content.startsWith("true") do
        return true
    return content.head.count >= 4 and
           content.head[0] == 0 and
           content.head[1] == 1 and
           content.head[2] == 0 and
           content.head[3] == 0
}

// Describes the font viewer to the host.
func viewerPlugin()->Viewer.Plugin
{
    with var result: retval
    {
        .key          = "font"
        .staticName   = "Font"
        .attach       = &registerTexts
        .iconAtlas    = viewerIcons()
        .iconIndex    = cast(s32, ViewerIcons.Font)
        .create       = &createViewer
        .probe        = &pluginProbe
        .smokeFixture = "segoeui.ttf"
        .addSelectors(".ttf;.ttc")
    }

    return result
}

private const CommandWidth = 456.0

// What loading a font file produces: its bytes, the face and typeface built on them, and the
// details line.
#[Swag.NoCopy]
struct ViewerContent
{
    bytes:    Array'u8
    face:     *Face?
    typeFace: *TypeFace?
    details:  String
}

impl ViewerContent
{
    mtd opDrop()
    {
        .face?.destroy()
    }
}

// Loads a font file for the viewer: its first face, a type face cached under the path and content
// checksum, and the details line, which counts the faces of a collection.
private func loadViewerContent(fileName: string)->ViewerContent fail
{
    var result: retval
    result.bytes = try File.readAllBytes(fileName)
    let faceCount = try Face.countFaces(result.bytes.toSlice())
    result.face = try Face.load(result.bytes.toSlice())

    let cacheKey = Format.toString("%|scope-font|%{X08}", fileName, Hash.Crc32.compute(result.bytes.toSlice()))
    result.typeFace = try TypeFace.create(cacheKey, result.bytes.toSlice())
    let style = result.face.styleName.isEmpty() ? texts().ui_Regular : result.face.styleName.toString()
    if faceCount == 1 do
        result.details = Format.toString(texts().ui_DetailsSingle, result.face.familyName, style, result.face.glyphCount, result.face.unitsPerEm)
    else do
        result.details = Format.toString(texts().ui_DetailsCollection, result.face.familyName, style, result.face.glyphCount, result.face.unitsPerEm, faceCount)
    return result
}

// The font viewer: a specimen of the face, a sample field, and the glyph pages browsed from the
// command bar.
struct Panel
{
    using wnd: Wnd

    late
    {
        commands:       *Wnd
        sampleEdit:     *EditBox
        previousButton: *IconButton
        nextButton:     *IconButton
        pageLabel:      *IconButton
        document:       *DocumentView
    }

    details:       String
    sampleDefault: String
    load:          Viewer.BackgroundLoad'ViewerContent
    services:      Viewer.HostServices
    failureReason: String
}

private impl Panel
{
    mtd refreshPageCommands()
    {
        .previousButton.enable(not .document.history.isEmpty())
        .nextButton.enable(.document.hasNext)
        .pageLabel.setText(Format.toString("U+%{X04}–U+%{X04}", .document.pageStart, .document.pageEnd))
    }

    mtd retranslate()
    {
        let replaceSample = .sampleEdit.text() == .sampleDefault.toString()
        .sampleDefault = texts().ui_DefaultSample
        if replaceSample do
            .sampleEdit.setText(.sampleDefault)

        .sampleEdit.setPlaceholder(texts().ui_SamplePlaceholder)
        .previousButton.toolTip = texts().ui_PreviousPage
        .nextButton.toolTip     = texts().ui_NextPage
        if not .load.isPending() do
            .document.invalidate()
    }

    // Offers the Unicode blocks the glyph grid can jump to, and shows the first page of the one
    // chosen.
    mtd showRangeMenu()
    {
        with let menu = MenuCtrl.createPopup(me, owner: me)
        {
            .addItem(texts().ui_BasicLatin, "scope.font.range.basic")
            .addItem(texts().ui_Latin1, "scope.font.range.latin1")
            .addItem(texts().ui_Greek, "scope.font.range.greek")
            .addItem(texts().ui_Cyrillic, "scope.font.range.cyrillic")
            .addItem(texts().ui_Symbols, "scope.font.range.symbols")
        }

        switch menu.doModal(.pageLabel, autoDestroy: true) orelse ""
        {
        case "scope.font.range.basic":    .document.goToCharacterPage(0x20)
        case "scope.font.range.latin1":   .document.goToCharacterPage(0xA0)
        case "scope.font.range.greek":    .document.goToCharacterPage(0x370)
        case "scope.font.range.cyrillic": .document.goToCharacterPage(0x400)
        case "scope.font.range.symbols":  .document.goToCharacterPage(0x2000)
        }

        .refreshPageCommands()
    }
}

private impl IWnd for Panel
{
    mtd impl onTimerEvent(evt: *TimerEvent)
    {
        if evt.timer != .load.timer
        {
            evt.accepted = false
            return
        }

        if not .load.poll() do
            return

        var content: ViewerContent
        .failureReason = .load.finish(&content)
        if not .failureReason.isEmpty()
        {
            .services.failed(me, .failureReason)
            return
        }

        .document    = DocumentView.create(me, content.face!, content.typeFace!, #move content.bytes, .sampleEdit)
        content.face = null
        .details     = #move content.details
        .refreshPageCommands()
        .applyLayout()
        .setInitialFocus(.document)
        .services.showDetails(me, .details)
        .services.loadingChanged(me)
    }

    mtd impl onNotifyEvent(evt: *NotifyEvent)
    {
        if evt.kind == .LanguageChanged do
            .retranslate()
        else do
            evt.accepted = false
    }
}

impl Panel
{
    mtd retire()->bool
    {
        return .load.retire()
    }

    // Creates the specimen view of `fileName`, with its sample field and character-page controls
    // in `commands`, and starts loading the font in the background.
    func create(contentParent, commands: *Wnd, fileName: string, services: Viewer.HostServices)->*Panel
    {
        with let result = Wnd.create'Panel(contentParent, "scope.font")
        {
            .backgroundStyle = .View
            .services        = services
            .commands        = commands
            .sampleDefault   = texts().ui_DefaultSample
        }

        result.createCommandBar()

        result.applyLayout()
        result.load.startPolled(result, fileName, &loadViewerContent)
        return result
    }

    // Creates the sample field and the character-page controls in the command group.
    private mtd createCommandBar()
    {
        with .sampleEdit = EditBox.create(.commands, .sampleDefault, {0, 0, 260, 36}, flags: .ClearButton | .ReleaseFocusOnEnterOrEscape)
        {
            .dockStyle = .Left
            .setMaximumLength(128)
            .setPlaceholder(texts().ui_SamplePlaceholder)
            .sigTextChanged += func|view = me|(_)
            {
                if not view.load.isPending() do
                    view.document.invalidate()
            }
        }

        with .previousButton = Viewer.createActionButton(.commands, .ChevronLeft)
        {
            .dockStyle  = .Left
            .margin.x   = 8
            .toolTip    = texts().ui_PreviousPage
            .sigPressed += func|view = me|(_)
            {
                view.document.previousPage()
                view.refreshPageCommands()
            }
        }

        with .nextButton = Viewer.createActionButton(.commands, .ChevronRight)
        {
            .dockStyle  = .Left
            .toolTip    = texts().ui_NextPage
            .sigPressed += func|view = me|(_)
            {
                view.document.nextPage()
                view.refreshPageCommands()
            }
        }

        with .pageLabel = IconButton.create(.commands, {}, {0, 0, 108, 36}, "scope.font.range", .CenterContent)
        {
            .dockStyle = .Left
            .margin.x  = 8
            .toolTip   = texts().ui_CharacterRange
            .setArrowPosition(.RightUpward)
            .setForm(.Rectangle)
            .style.setFont(me.theme().res.fontDefaultFs)
            .sigPressed += func|view = me|(_) { view.showRangeMenu() }
        }
    }
}

// Creates the integrated TrueType specimen and character-map view.
func createViewer(host: Viewer.Host)
{
    let services = host.services()
    let view     = Panel.create(host.contentParent(), host.createCommandGroup(CommandWidth), host.fileName(), services)
    host.attachView(view)

    host.setLifecycle(Viewer.loadLifecycle(view))
}
