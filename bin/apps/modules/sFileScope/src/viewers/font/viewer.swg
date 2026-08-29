#global internal

using Core, Pixel, Gui, TrueType

private const FontCommandWidth = 456.0

#[Swag.NoCopy]
struct FontViewerContent
{
    bytes:    Array'u8
    face:     #null *Face
    typeFace: #null *TypeFace
    details:  String
}

impl FontViewerContent
{
    mtd opDrop()
    {
        if .face do
            .face!.destroy()
    }
}

private func loadFontViewerContent(fileName: string)->FontViewerContent fail
{
    var result: retval
    result.bytes = try File.readAllBytes(fileName)
    let faceCount = try Face.countFaces(result.bytes.toSlice())
    result.face = (try Face.load(result.bytes.toSlice()))!

    let cacheKey = Format.toString("%|filescope-font|%{X08}", fileName, Hash.Crc32.compute(result.bytes.toSlice()))
    result.typeFace = try TypeFace.create(cacheKey.toString(), result.bytes.toSlice())
    let style = result.face!.styleName.isEmpty() ? fontStrings().ui_Regular : result.face!.styleName.toString()
    if faceCount == 1 do
        result.details = Format.toString(fontStrings().ui_DetailsSingle, result.face!.familyName, style, result.face!.glyphCount, result.face!.unitsPerEm)
    else do
        result.details = Format.toString(fontStrings().ui_DetailsCollection, result.face!.familyName, style, result.face!.glyphCount, result.face!.unitsPerEm, faceCount)
    return #move result
}

internal struct FontViewer
{
    using wnd: Wnd

    #[Swag.Late]
    {
        commands:       *Wnd
        sampleEdit:     *EditBox
        previousButton: *IconButton
        nextButton:     *IconButton
        pageLabel:      *Label
        document:       *FontDocumentView
    }

    details:              String
    sampleDefault:        String
    load:                 ViewerBackgroundLoad'FontViewerContent
    loadTimer:            #null *Timer
    reportFailure:        #null ViewerReportFailure
    reportDetails:        #null ViewerReportDetails
    reportLoadingChanged: #null ViewerReportLoadingChanged
    failureReason:        String
}

private impl FontViewer
{
    mtd refreshPageCommands()
    {
        .previousButton.enable(.document.history.count != 0)
        .nextButton.enable(.document.hasNext)
        let range = Format.toString("U+%{X04}–U+%{X04}", .document.pageStart, .document.pageEnd)
        .pageLabel.setText(range.toString())
    }

    mtd retranslate()
    {
        let replaceSample = .sampleEdit.text() == .sampleDefault.toString()
        .sampleDefault = fontStrings().ui_DefaultSample
        if replaceSample do
            .sampleEdit.setText(.sampleDefault.toString())

        .sampleEdit.setPlaceholder(fontStrings().ui_SamplePlaceholder)
        .previousButton.toolTip = fontStrings().ui_PreviousPage
        .nextButton.toolTip     = fontStrings().ui_NextPage
        if !.loadTimer do
            .document.invalidate()
    }
}

private impl IWnd for FontViewer
{
    mtd impl onTimerEvent(evt: *TimerEvent)
    {
        if evt.timer != .loadTimer
        {
            evt.accepted = false
            return
        }

        if !.load.isDone() do
            return

        .removeTimer(evt.timer)
        .loadTimer = null
        var content: FontViewerContent
        .failureReason = .load.finish(&content)
        if !.failureReason.isEmpty()
        {
            if .reportFailure do
                .reportFailure!(me, .failureReason.toString())
            return
        }

        .document    = FontDocumentView.create(me, content.face!, content.typeFace!, #move content.bytes, .sampleEdit)
        content.face = null
        .details     = #move content.details
        .refreshPageCommands()
        .applyLayout()
        .setInitialFocus(.document)
        if .reportDetails do
            .reportDetails!(me, .details.toString())
        if .reportLoadingChanged do
            .reportLoadingChanged!(me)
    }

    mtd impl onNotifyEvent(evt: *NotifyEvent)
    {
        if evt.kind == .LanguageChanged do
            .retranslate()
        else do
            evt.accepted = false
    }
}

internal impl FontViewer
{
    mtd retire()->bool
    {
        if !.load.retire() do
            return false
        if .loadTimer
        {
            .removeTimer(.loadTimer!)
            .loadTimer = null
        }

        return true
    }

    func create(contentParent, commands: *Wnd, fileName: string, reportFailure: #null ViewerReportFailure, reportDetails: #null ViewerReportDetails, reportLoadingChanged: #null ViewerReportLoadingChanged)->*FontViewer
    {
        registerFontStrings(contentParent.app())
        let result = Wnd.create'FontViewer(contentParent, "sFileScope.font")
        result.backgroundStyle      = .View
        result.reportFailure        = reportFailure
        result.reportDetails        = reportDetails
        result.reportLoadingChanged = reportLoadingChanged

        result.commands = commands

        result.sampleDefault = fontStrings().ui_DefaultSample
        with result.sampleEdit = EditBox.create(result.commands, result.sampleDefault.toString(), {0, 0, 260, 36}, flags: .ClearButton | .ReleaseFocusOnEnterOrEscape)
        {
            .dockStyle = .Left
            .setMaximumLength(128)
            .setPlaceholder(fontStrings().ui_SamplePlaceholder)
            .sigTextChanged += func|view = result|(edit)
            {
                discard edit
                if !view.loadTimer do
                    view.document.invalidate()
            }
        }

        with result.previousButton = IconButton.create(result.commands, result.theme().icon(.ChevronLeft, ViewerGlyphSize), {0, 0, 36, 36})
        {
            .dockStyle  = .Left
            .margin.x   = 8
            .toolTip    = fontStrings().ui_PreviousPage
            .sigPressed += func|view = result|(button)
            {
                discard button
                view.document.previousPage()
                view.refreshPageCommands()
            }
        }

        with result.nextButton = IconButton.create(result.commands, result.theme().icon(.ChevronRight, ViewerGlyphSize), {0, 0, 36, 36})
        {
            .dockStyle  = .Left
            .toolTip    = fontStrings().ui_NextPage
            .sigPressed += func|view = result|(button)
            {
                discard button
                view.document.nextPage()
                view.refreshPageCommands()
            }
        }

        with result.pageLabel = Label.create(result.commands, "", {0, 0, 108, 36}, null, .SecondaryText)
        {
            .dockStyle = .Left
            .margin.x  = 8
            .style.setFont(result.theme().createDefaultFontFS(11), .Regular)
            .setTextAlignment(.Right, .Center)
        }

        result.applyLayout()
        result.load.start(fileName, &loadFontViewerContent)
        result.loadTimer = result.addTimer(ViewerBackgroundPollInterval)
        return result
    }
}

// Creates the integrated TrueType specimen and character-map view.
func createFontViewer(host: FileScope.Host)
{
    registerFontStrings(host.application())
    let services = host.services()
    let view     = FontViewer.create(host.contentParent(), host.createCommandGroup(FontCommandWidth), host.fileName(), services.reportFailure, services.reportDetails, services.reportLoadingChanged)
    host.attachView(view)
    host.setLifecycle({
        isLoading: func(wnd)->bool { return (cast(*FontViewer) wnd).loadTimer != null },
        needsLoadingOverlay: func(wnd)->bool { return (cast(*FontViewer) wnd).loadTimer != null },
        retire: func(wnd)->bool { return (cast(*FontViewer) wnd).retire() }})
}
