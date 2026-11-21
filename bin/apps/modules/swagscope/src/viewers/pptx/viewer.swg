#global internal
#global namespace Viewers.Pptx

using Core, Gui

private const ThumbnailCount     = 5'u64
private const ThumbnailRailWidth = 156's32

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
        .addSelectors(".pptx")
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
    thumbnails:       Array'(*HtmlView)
    thumbnailTiles:   Array'(*Wnd)
    thumbnailButtons: Array'(*PushButton)
    thumbnailStart:   u64

    late
    {
        status:           *Label
        previousButton:   *IconButton
        nextButton:       *IconButton
        slideLabel:       *Label
        outline:          *DocumentOutline
        thumbnailHeading: *Label
    }
}

private impl IWnd for Panel
{
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

        var headings: Array'DocumentHeading
        for page, index in .presentation.slides
        {
            let title = page.title.isEmpty() ? Format.toString(texts().ui_Slide, index + 1) : page.title
            headings.add(DocumentHeading{title, 1, index})
        }

        .outline.publish(headings.toSlice())
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
            .thumbnailHeading.setText(texts().ui_Thumbnails)
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
        .previousButton.enable(.slide < count and .slide > 0)
        .nextButton.enable(.slide < count and .slide + 1 < count)
        .slideLabel.setText(Viewer.pageText(.slide, count))
        .previousButton.toolTip = texts().ui_Previous
        .nextButton.toolTip     = texts().ui_Next
        if .slide >= count do
            return
        var detail = Format.toString(texts().ui_CurrentSlide, .slide + 1, count)
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
        for row, position in .outline.rows where cast(u64, row.userData0) == index + 1
        {
            .outline.list.selectLine(cast(u32, position))
            break
        }

        .refreshThumbnails()
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
        let roomWidth  = Math.max(area.width - ThumbnailRailWidth - 2 * inset, 1)
        let roomHeight = Math.max(area.height - top - inset, 1)
        var bounds     = Math.Rectangle{ThumbnailRailWidth + inset, top, roomWidth, roomHeight}
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
        entries.add(texts().ui_Previous, .ChevronLeft, func|view = me|() { view.turn(-1) }, disabled: .slide == 0 or .slide >= .presentation.slides.count, defaultKey: {modifiers: .Control, key: .PageUp}, bindId: "scope.pptx.previous")
        entries.add(texts().ui_Next, .ChevronRight, func|view = me|() { view.turn(1) }, disabled: .slide >= .presentation.slides.count or .slide + 1 >= .presentation.slides.count, defaultKey: {modifiers: .Control, key: .PageDown}, bindId: "scope.pptx.next")
        entries.add(texts().ui_ShowSlides, .File, func|view = me|() { view.setTextMode(false) }, checked: not .textMode and not .notesMode, bindId: "scope.pptx.showSlides")
        entries.add(texts().ui_ReadText, .Wrap, func|view = me|() { view.setTextMode(true) }, checked: .textMode, bindId: "scope.pptx.readText")
        entries.add(texts().ui_ReadNotes, .Wrap, func|view = me|() { view.showNotes() }, checked: .notesMode, bindId: "scope.pptx.readNotes")
    }

    mtd createThumbnailRail()
    {
        with let rail = Wnd.create'Wnd(me, {0, 0, ThumbnailRailWidth, 0})
        {
            .dockStyle       = .Left
            .backgroundStyle = .View
            .preferredSize.x = ThumbnailRailWidth
        }

        with .thumbnailHeading = Label.create(rail, texts().ui_Thumbnails, {0, 0, ThumbnailRailWidth, 28})
        {
            .dockStyle = .Top
            .setTextAlignment(.Center, .OpticalCenter)
        }

        with let scroll = Wnd.create'ScrollWnd(rail, "", {})
        {
            .dockStyle = .Center
            .updateFlags(.TransparentBars | .DisableHorizontal)
            .setFrameFlags(remove: .Borders)
        }

        with let content = scroll.createView'Wnd()
        {
            .preferredSize.y = cast(s32, ThumbnailCount) * 112
        }

        scroll.setScrollSize(ThumbnailRailWidth - 4, cast(f32, ThumbnailCount) * 112)
        for slot in 0 until ThumbnailCount
        {
            with let tile = Wnd.create'Wnd(content, {0, 0, ThumbnailRailWidth - 8, 112})
            {
                .dockStyle       = .Top
                .backgroundStyle = .View
                .margin          = {4, 3, 4, 2}
            }

            with let button = PushButton.create(tile, "", {0, 0, ThumbnailRailWidth - 16, 28})
            {
                .dockStyle  = .Bottom
                .sigPressed += func|view = me, slot|(_)
                {
                    let index = view.thumbnailStart + slot
                    if index < view.presentation.slides.count do
                        view.showSlide(index)
                }
            }

            .thumbnailTiles.add(tile)
            .thumbnailButtons.add(button)
        }
    }

    mtd refreshThumbnails()
    {
        if .thumbnailTiles.isEmpty() or .presentation.slides.isEmpty() do
            return
        var first = .slide > 2 ? .slide - 2 : 0
        if .presentation.slides.count > ThumbnailCount do
            first = Math.min(first, .presentation.slides.count - ThumbnailCount)
        .thumbnailStart = first
        for offset in 0 until ThumbnailCount
        {
            let index  = first + offset
            let button = .thumbnailButtons[offset]
            if index >= .presentation.slides.count
            {
                button.setText("")
                button.enable(false)
                if offset < .thumbnails.count
                {
                    .thumbnails[offset].hide()
                    .thumbnails[offset].destroy()
                }

                continue
            }

            let label = Format.toString(texts().ui_Slide, index + 1)
            button.setText(index == .slide ? Format.toString("▶ %", label) : label)
            button.enable(true)
            if offset < .thumbnails.count
            {
                .thumbnails[offset].hide()
                .thumbnails[offset].destroy()
            }

            var style = HtmlStyle.theme()
            style.followTheme = false
            with let preview = HtmlView.createText(.thumbnailTiles[offset],
                                                   .presentation.slides[index].canvasHtml(.presentation.width, .presentation.height),
                                                   style)
            {
                .dockStyle       = .Top
                .backgroundStyle = .View
                .preferredSize.y = 80
            }

            if offset < .thumbnails.count do
                .thumbnails[offset] = preview
            else do
                .thumbnails.add(preview)
        }
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
        result.createThumbnailRail()
        with result.previousButton = Viewer.createPageStep(controls, -1)
        {
            .sigPressed += func|view = result|(_) { view.turn(-1) }
        }

        result.slideLabel = Viewer.createPageLabel(controls)
        with result.nextButton = Viewer.createPageStep(controls, 1)
        {
            .sigPressed += func|view = result|(_) { view.turn(1) }
        }

        with result.status = Label.create(result, texts().ui_Preparing, {}, null, .WordWrap)
        {
            .dockStyle       = .Center
            .backgroundStyle = .View
            .setTextAlignment(.Center, .Center)
        }

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
    createPresentationViewer(host, &Presentation.load)
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
    view.outline.sigSelected += func|view|(_, index) { view.showSlide(index) }
    host.setLensSource(func|view|(entries) { view.describeLens(entries) })
    view.load.start(host.fileName(), loader, view)
    host.setLifecycle(Viewer.loadLifecycle(view))
}
