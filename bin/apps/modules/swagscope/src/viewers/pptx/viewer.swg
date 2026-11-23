#global internal
#global namespace Viewers.Pptx

using Core, Gui, Pixel

// Offers a presentation's slides before the generic ZIP package structure.
func viewerPlugin()->Viewer.Plugin
{
    with var result: #returntype
    {
        .key          = "pptx"
        .staticName   = "Presentation"
        .resolveName  = func()->string => texts().ui_Name
        .attach       = &registerTexts
        .iconAtlas    = viewerIcons()
        .iconIndex    = cast(s32, ViewerIcons.Pptx)
        .create       = &createViewer
        .smokeFixture = "viewer.pptx"
        .addSelectors(".pptx;.ppsx;.pptm;.ppt;.pps;.pot;.potx;.potm")
    }

    return result
}

// Fits one authored slide to the reading surface; a text mode retains the accessible reading order.
struct Panel
{
    using wnd: Wnd

    presentation:     Presentation
    load:             Viewer.BackgroundLoad'Presentation
    services:         Viewer.HostServices
    view:             *HtmlView?
    slide:            u64 = Swag.U64.Max
    textMode:         bool
    notesMode:        bool
    using navigation: DocumentPageNavigation
    previews:         Array'Layer

    using steps: Viewer.PageSteps

    late
    {
        status:           *Label
        slideLabel:       *IconButton
        outline:          *DocumentOutline
    }
}

private impl IWnd for Panel
{
    mtd impl onDestroyEvent(_: *DestroyEvent) => .clearPreviews()

    mtd impl onThemeEvent(evt: *ThemeEvent)
    {
        .clearPreviews()
        .wnd.IWnd.onThemeEvent(evt)
    }

    mtd impl onTaskEvent(evt: *TaskEvent)
    {
        if not .load.claim(evt)
        {
            evt.accepted = false
            return
        }

        let failure = .load.finish(&.presentation)
        if not failure.isEmpty()
        {
            .services.failed(me, failure)
            return
        }

        var hasTitles = false
        var headings: Array'DocumentHeading
        for page, index in .presentation.slides
        {
            hasTitles = hasTitles or not page.title.isEmpty()
            let title = page.title.isEmpty() ? Format.toString(texts().ui_Slide, index + 1) : page.title
            headings.add(DocumentHeading{title, 1, index})
        }

        // A deck without named slides opens directly to its visual index.
        if not hasTitles do
            headings.clear()
        .outline.publish(headings.toSlice())
        .navigation.pageCount   = .presentation.slides.count
        .navigation.slideAspect = .presentation.width / .presentation.height
        .previews.resize(.presentation.slides.count)
        .setNavigationMode(not hasTitles)
        .showSlide(0)
        .services.loadingChanged(me)
    }

    mtd impl onResizeEvent(_: *ResizeEvent)
    {
        .layoutSlide()
    }

    mtd impl onKeyEvent(evt: *KeyEvent)
    {
        evt.accepted = .handleKey(evt)
    }

    mtd impl onNotifyEvent(evt: *NotifyEvent)
    {
        if evt.kind == .LanguageChanged
        {
            .translateNavigation(texts().ui_Thumbnails, texts().ui_Titles)
            if .notesMode and .slide < .presentation.slides.count do
                .buildSlide()
            else do
                .refreshNavigation()
        }

        .wnd.IWnd.onNotifyEvent(evt)
    }
}

private impl Panel
{
    internal mtd retire()->bool => .load.retire()

    mtd refreshNavigation()
    {
        let count = .presentation.slides.count
        if .steps.updateSteps(.slide, count) do
            .services.chromeChanged(me)
        .previousButton.toolTip = texts().ui_Previous
        .nextButton.toolTip     = texts().ui_Next
        if .slide >= count do
            return
        var detail = String.from(texts().ui_Name)
        if .notesMode do
            detail += Format.toString(" · %", texts().ui_NotesMode)
        elif .textMode do
            detail += Format.toString(" · %", texts().ui_TextMode)
        elif .presentation.slides[.slide].simplified do
            detail += Format.toString(" · %", texts().ui_Simplified)
        .services.showDetails(me, detail)
    }

    internal mtd showSlide(index: u64)
    {
        if index >= .presentation.slides.count or (index == .slide and .view) do
            return
        .slide = index
        .buildSlide()
        .outline.markReading(index)
        .navigation.currentPage = index
        if .gallery.isVisible() do
            .gallery.revealCurrentPage()
    }

    internal mtd turn(direction: s32)
    {
        if .slide >= .presentation.slides.count do
            return
        if direction < 0 and .slide > 0 do
            .showSlide(.slide - 1)
        elif direction > 0 and .slide + 1 < .presentation.slides.count do
            .showSlide(.slide + 1)
    }

    internal mtd setTextMode(enabled: bool)
    {
        if .textMode == enabled and not .notesMode do
            return
        .textMode  = enabled
        .notesMode = false
        if .slide < .presentation.slides.count do
            .buildSlide()
    }

    internal mtd showNotes()
    {
        if .notesMode do
            return
        .notesMode = true
        .textMode  = false
        if .slide < .presentation.slides.count do
            .buildSlide()
    }

    mtd buildSlide()
    {
        .view?.hide()
        .view?.destroy()
        let page  = &.presentation.slides[.slide]
        var source: String
        var style = HtmlStyle.theme()
        if .notesMode
        {
            source = "<html><body><h1>"
            Package.appendHtmlEscaped(&source, page.title.isEmpty() ? Format.toString(texts().ui_Slide, .slide + 1) : page.title)
            source += "</h1>"
            if page.notesHtml.isEmpty()
            {
                source += "<p>"
                Package.appendHtmlEscaped(&source, texts().ui_NoNotes)
                source += "</p>"
            }
            else
            {
                source += page.notesHtml
            }

            source += "</body></html>"
            style.maxContentWidth = 680
            style.bodyFontSize    = 18
        }
        elif .textMode or page.simplified
        {
            source                = "<html><body>"
            source                += page.readingHtml()
            source                += "</body></html>"
            style.maxContentWidth = 680
            style.bodyFontSize    = 18
        }
        else
        {
            source = page.canvasHtml(.presentation.width, .presentation.height)
            style.followTheme = false
        }

        with .view = HtmlView.createText(me, source, style)
        {
            .dockStyle = .None
        }

        .status.hide()
        .layoutSlide()
        .refreshNavigation()
    }

    mtd layoutSlide()
    {
        let view = .view
        if not view or .slide >= .presentation.slides.count do
            return
        let inset      = .themeMetrics().floating_Inset
        let top        = .stripInset() + inset
        let area       = .clientRect()
        let roomWidth  = Math.max(area.width - 2 * inset, 1)
        let roomHeight = Math.max(area.height - top - inset, 1)
        var bounds     = Math.Rectangle{inset, top, roomWidth, roomHeight}
        if not .notesMode and not .textMode and not .presentation.slides[.slide].simplified
        {
            let scale = Math.min(roomWidth / .presentation.width, roomHeight / .presentation.height)
            bounds.width  = Math.round(.presentation.width * scale)
            bounds.height = Math.round(.presentation.height * scale)
            bounds.x      += Math.round((roomWidth - bounds.width) * 0.5)
            bounds.y      += Math.round((roomHeight - bounds.height) * 0.5)
        }

        view.setPosition(bounds, computeLayout: false)
        view.applyLayout()
    }

    mtd handleKey(key: const *KeyEvent)->bool
    {
        if key.kind != .Pressed do
            return false
        let direction = Viewer.pageKeyDirection(key)
        if direction
        {
            .turn(direction)
            return true
        }

        if key.modifiers != .None and key.modifiers != .Control do
            return false
        switch key.key
        {
        case .PageUp:   .turn(-1)
        case .PageDown: .turn(1)
        case .Home where key.modifiers == .Control: .showSlide(0)
        case .End where key.modifiers == .Control and not .presentation.slides.isEmpty(): .showSlide(.presentation.slides.count - 1)
        default:        return false
        }

        return true
    }

    mtd describeLens(entries: *Viewer.LensEntries)
    {
        .steps.addPageJump(entries, "scope.pptx.goToPage")
        entries.add(texts().ui_Previous, .ChevronLeft, func|view = me|() { view.turn(-1) }, disabled: .slide == 0 or .slide >= .presentation.slides.count, defaultKey: {modifiers: .Control, key: .PageUp}, bindId: "scope.pptx.previous")
        entries.add(texts().ui_Next, .ChevronRight, func|view = me|() { view.turn(1) }, disabled: .slide >= .presentation.slides.count or .slide + 1 >= .presentation.slides.count, defaultKey: {modifiers: .Control, key: .PageDown}, bindId: "scope.pptx.next")
        entries.add(texts().ui_ShowThumbnails, .Grid, func|view = me|() { view.openPages() }, disabled: .presentation.slides.isEmpty(), bindId: "scope.pptx.thumbnails")
        entries.add(texts().ui_ShowSlides, .File, func|view = me|() { view.setTextMode(false) }, checked: not .textMode and not .notesMode, bindId: "scope.pptx.showSlides")
        entries.add(texts().ui_ReadText, .Wrap, func|view = me|() { view.setTextMode(true) }, checked: .textMode, bindId: "scope.pptx.readText")
        entries.add(texts().ui_ReadNotes, .Wrap, func|view = me|() { view.showNotes() }, checked: .notesMode, bindId: "scope.pptx.readNotes")
    }

    func create(host: Viewer.Host)->*Panel
    {
        with let result = Wnd.create'Panel(host.contentParent(), "scope.pptx")
        {
            .backgroundStyle = .View
            .focusPolicy     = .Tab
            .services        = host.services()
        }

        let controls = host.createCommandGroup(Viewer.pageControlWidth(result.themeMetrics()))
        result.slideLabel = result.steps.create(controls, "scope.pptx.page", .Slide,
            func|view = result|(dir) { view.turn(dir) }, func|view = result|(index) { view.showSlide(index) })

        result.status = Viewer.createLoadingLabel(result, texts().ui_Preparing)

        result.hookOnChildEvent = func|result|(_, evt)
        {
            if evt is KeyEvent as key do
                return result.handleKey(key)
            return false
        }

        result.refreshNavigation()
        result.applyLayout()
        return result
    }
}

func createViewer(host: Viewer.Host)
{
    createPresentationViewer(host, &loadPresentationFile)
}

// Reject package families that share PowerPoint's brand and filename patterns but use structures
// the Open XML slide reader cannot decode.
func loadPresentationFile(fileName: string)->Presentation fail
{
    let extension = String.toLower(Path.extension(fileName))
    if extension == ".ppt" or extension == ".pps" do
        fail Errors.UnsupportedFormatError{texts().err_LegacyFormat}
    if extension == ".pot" or extension == ".potx" or extension == ".potm" do
        fail Errors.UnsupportedFormatError{texts().err_TemplateFormat}
    return try Presentation.load(fileName)
}

impl Panel
{
    // Describes the presentation in the information sheet with what its package says of it, read
    // with the slides on the loading worker.
    internal mtd describeInformation(sheet: *InfoSheet)
    {
        var data: MediaInfoData
        .presentation.properties.describe(&data)
        data.describe(sheet)
    }
}

func createPresentationViewer(host: Viewer.Host, loader: func(string)->Presentation fail)
{
    let view = Panel.create(host)
    host.attachView(view)
    host.setInformation(func|view|(sheet) { view.describeInformation(sheet) })
    view.outline = DocumentOutline.create(host)
    view.createSlideNavigation()
    view.outline.sigSelected += func|view|(_, index) { view.showSlide(index) }
    host.setLensSource(func|view|(entries) { view.describeLens(entries) })
    view.load.start(host.fileName(), loader, view)
    host.setLifecycle(Viewer.loadLifecycle(view))
}
