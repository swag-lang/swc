#global internal
#global namespace Viewers.PdfDocument

using Core, Pixel, Gui

// Offers the page surface for a document that carries the PDF header, whatever it is called.
private func pluginProbe(content: Viewer.ProbeContent)->bool => content.startsWith("%PDF-")

// Describes the PDF viewer to the host.
func viewerPlugin()->Viewer.Plugin
{
    with var result: #returntype
    {
        .key          = "pdf"
        .staticName   = "PDF"
        .attach       = &registerTexts
        .iconAtlas    = viewerIcons()
        .iconIndex    = cast(s32, ViewerIcons.Pdf)
        .create       = &createViewer
        .probe        = &pluginProbe
        .smokeFixture = "viewer.pdf"
        .addSelectors(".pdf")
    }

    return result
}

private const PageWidth = 76.0

private func infoWidth(metrics: const *ThemeMetrics)->f32 => 2 * themeActionButtonSize(metrics) + PageWidth + Viewer.ZoomSlotWidth + 16

// Keeps the page controls and zoom selector in one fixed-width run. Their authored cells are
// wider than their current text and icons, so measuring each child by its contents would let the
// host shrink the group until the left- and right-docked controls overlap.
private struct InfoControls
{
    using wnd: Wnd
}

private impl IWnd for InfoControls
{
    mtd impl measureContent(_: Math.Point)->Math.Point => .preferredSize
}

// What the details line says about a document: its length, the size of its first page, and the
// title and author it declares.
struct DocumentFacts
{
    pageCount: u64
    pageSize:  Math.Point     // In points, or zero when the first page has no readable box.
    title:     String
    author:    String
}

// What opening a PDF produces: the reader, its first page, its outline, and its facts.
struct ViewerContent
{
    reader:  Pdf.Reader
    page:    Pdf.Page
    facts:   DocumentFacts
    outline: Array'Pdf.OutlineEntry
}

private func loadViewerContent(fileName: string)->ViewerContent fail
{
    var result: #returntype
    result.reader  = #move try Pdf.Reader.open(fileName)
    result.outline = result.reader.loadOutline()
    if not result.reader.pageCount() do
        fail Errors.InvalidFormatError{texts().err_NoPage}
    result.page = #move try result.reader.loadPage(0)

    let metadata = result.reader.metadata()
    with result.facts
    {
        .pageCount = result.reader.pageCount()
        .pageSize  = catch result.reader.pageSize(0)
        .title     = String.from(Latin1.trim(metadata.title.toString()))
        .author    = String.from(Latin1.trim(metadata.author.toString()))
    }

    return result
}

// Names a page size the way a reader asks for paper: a standard format in either orientation,
// or its millimetres otherwise.
func paperText(size: Math.Point)->String
{
    let papers: [6] { name: string, width: f32, height: f32 } = [
        {name: "A3",      width: 842, height: 1191},
        {name: "A4",      width: 595, height: 842},
        {name: "A5",      width: 420, height: 595},
        {name: "Letter",  width: 612, height: 792},
        {name: "Legal",   width: 612, height: 1008},
        {name: "Tabloid", width: 792, height: 1224}]

    let shortSide = Math.min(size.x, size.y)
    let longSide  = Math.max(size.x, size.y)
    for paper in papers where Math.abs(shortSide - paper.width) <= 3 and Math.abs(longSide - paper.height) <= 3 do
        return String.from(paper.name)

    const MillimetresPerPoint = 25.4'f32 / 72
    return Format.toString("% × % mm", cast(u32, Math.round(size.x * MillimetresPerPoint)), cast(u32, Math.round(size.y * MillimetresPerPoint)))
}

// Builds the details line of a document in the active language.
func detailsText(facts: const *DocumentFacts)->String
{
    var result: #returntype = "PDF"
    result += " · "
    if facts.pageCount == 1 do
        result += texts().ui_OnePage
    else do
        result += Format.toString(texts().ui_Pages, facts.pageCount)
    if facts.pageSize.x > 0 and facts.pageSize.y > 0
    {
        result += " · "
        result += paperText(facts.pageSize)
    }

    if not facts.title.isEmpty()
    {
        result += " · "
        result += facts.title
    }

    if not facts.author.isEmpty()
    {
        result += " · "
        result += facts.author
    }

    return result
}

// The PDF viewer: the page view, its page and zoom controls, and the document outline.
struct Panel
{
    using wnd:     Wnd
    details:       String
    facts:         DocumentFacts
    services:      Viewer.HostServices
    load:          Viewer.BackgroundLoad'ViewerContent
    failureReason: String
    outline:       *DocumentOutline?
    bookmarks:     Array'Pdf.OutlineEntry
    margin:        *OutlineMargin?
    marginParts:   Array'u64     // Indices of the bookmarks the margin lists.

    late
    {
        info:           *Wnd
        pdfView:        *PdfView
        previousButton: *IconButton
        nextButton:     *IconButton
        pageLabel:      *IconButton
        zoomLabel:      *IconButton
    }
}

private impl IWnd for Panel
{
    mtd impl onNotifyEvent(evt: *NotifyEvent)
    {
        if evt.kind == .LanguageChanged
        {
            if .margin
            {
                .margin.label = texts().ui_Contents
                .margin.invalidate()
            }

            .previousButton.toolTip = texts().ui_Previous
            .nextButton.toolTip     = texts().ui_Next
            .pageLabel.toolTip      = texts().ui_GoToPage
            .zoomLabel.toolTip      = texts().ui_ZoomMenu
            if .facts.pageCount
            {
                .details = detailsText(&.facts)
                .services.showDetails(me, .details)
            }
        }

        .wnd.IWnd.onNotifyEvent(evt)
    }

    mtd impl onTaskEvent(evt: *TaskEvent)
    {
        if not .load.claim(evt)
        {
            evt.accepted = false
            return
        }

        var content: ViewerContent
        .failureReason = .load.finish(&content)
        if not .failureReason.isEmpty()
        {
            .services.failed(me, .failureReason)
            return
        }

        .pdfView.exchangeDocument(&content.reader, &content.page)
        .bookmarks = #move content.outline
        if .outline
        {
            .outline.clear()
            for entry, index in .bookmarks do
                .outline.add(entry.title, entry.level, index)
            .outline.refresh()
        }

        .facts   = #move content.facts
        .details = detailsText(&.facts)
        .applyLayout()
        .fillMargin()
        .refreshNavigation()
        .setInitialFocus(.pdfView)
        .services.showDetails(me, .details)
        .services.loadingChanged(me)
    }

    mtd impl onResizeEvent(_: *ResizeEvent)
    {
        .placeMargin()
    }

    mtd impl onKeyEvent(evt: *KeyEvent)
    {
        if evt.kind != .Pressed
        {
            evt.accepted = false
            return
        }

        switch evt.key
        {
        case .Add, .OemPlus:                        .pdfView.zoomIn()
        case .Subtract, .OemMinus:                  .pdfView.zoomOut()
        case .D0 where evt.modifiers.has(.Control): .pdfView.actualSize()
        case .F where evt.modifiers == .None:       .pdfView.zoomToFit()
        case .W where evt.modifiers == .None:       .pdfView.zoomToFitWidth()
        default: evt.accepted = false
        }
    }
}

private impl Panel
{
    internal mtd retire()->bool
    {
        return .load.retire()
    }

    // Appends the matches of the pages whose text the view has extracted so far, and reports
    // whether the whole document has been searched.
    mtd collectMatches(text: string, options: Viewer.SearchOptions, progress: *u64, result: *Array'Viewer.SearchMatch)->bool
    {
        with var pdfOptions: PdfTextSearchOptions
        {
            .comparison        = options.matchCase ? .Latin1 : .Latin1NoCase
            .wholeWord         = options.wholeWord
            .regularExpression = options.regularExpression
        }

        var matches: Array'PdfTextMatch
        let complete = .pdfView.collectTextMatches(text, pdfOptions, progress, &matches)
        for match in matches do
            result.add(Viewer.SearchMatch{match.pageIndex, 0, match.byteOffset, match.byteLength})
        return complete
    }

    mtd revealMatch(match: Viewer.SearchMatch, _: string)->bool => .pdfView.revealTextMatch(PdfTextMatch{match.major, match.offset, match.length})

    mtd searchBounds(match: Viewer.SearchMatch, result: *Math.Rectangle)->bool => .pdfView.textMatchRect(PdfTextMatch{match.major, match.offset, match.length}, result)

    // Lists the parts of the first two levels of the outline in the left margin.
    internal mtd fillMargin()
    {
        if .margin == null do
            return
        .marginParts.clear()
        .margin.titles.clear()
        for entry, index in .bookmarks where entry.level <= 2 and entry.pageIndex != Swag.U64.Max
        {
            .marginParts.add(index)
            .margin.titles.add(entry.title)
        }

        .placeMargin()
    }

    // Stands the outline in the margin left of the page, the part being read on its Arc rule, when
    // the margin has the room.
    internal mtd placeMargin()
    {
        if .margin == null do
            return
        var active = Swag.U64.Max
        for index, row in .marginParts where .bookmarks[index].pageIndex <= .pdfView.pageIndex do
            active = row
        .margin.setActive(active)

        const Inset = 24.0
        let column = .pdfView.pageColumn()
        .margin.place(Inset, Inset, column.x - 2 * Inset)
    }

    mtd refreshNavigation()
    {
        .previousButton.enable(.pdfView.pageIndex > 0)
        .nextButton.enable(.pdfView.pageIndex + 1 < .pdfView.pageCount())
        .pageLabel.setText(Format.toString("% / %", .pdfView.pageIndex + 1, .pdfView.pageCount()))
        .placeMargin()
    }

    mtd refreshZoom()
    {
        .zoomLabel.setText(Format.toString("% %", cast(u32, Math.round(.pdfView.effectiveZoom() * 100)), "%"))
        .placeMargin()
    }

    internal mtd goToTypedPage(text: string)->bool
    {
        var parseErrorOutcome: Swag.Error
        var parsed: #decltype(expect StrConv.parseU64(text))
        catch { parsed = try StrConv.parseU64(text) } as parseErrorOutcome
        let parseError = parseErrorOutcome.value()
        if parseError != null or
           parsed.eat != text.count or
           parsed.ovf or
           not parsed.value or
           parsed.value > .pdfView.pageCount() do
            return false
        .pdfView.showPage(parsed.value - 1)
        return true
    }

    // Gives the lens the pages and the zoom of the document.
    mtd describeLens(entries: *Viewer.LensEntries)
    {
        let strings = texts()
        entries.add(strings.ui_Previous, func|view = me|() { view.pdfView.previousPage() })
        entries.add(strings.ui_Next, func|view = me|() { view.pdfView.nextPage() })
        entries.add(strings.ui_GoToPage, func|view = me|() { view.promptGoToPage() })
        entries.add(strings.ui_ZoomIn, func|view = me|() { view.pdfView.zoomIn() }, shortcut: Input.formatKeyShortcut(.None, .Add))
        entries.add(strings.ui_ZoomOut, func|view = me|() { view.pdfView.zoomOut() }, shortcut: Input.formatKeyShortcut(.None, .Subtract))
        entries.add(strings.ui_Fit, func|view = me|() { view.pdfView.zoomToFit() }, checked: .pdfView.zoomMode == .FitPage, shortcut: Input.formatKeyShortcut(.None, .F))
        entries.add(strings.ui_FitWidth, func|view = me|() { view.pdfView.zoomToFitWidth() }, checked: .pdfView.zoomMode == .FitWidth, shortcut: Input.formatKeyShortcut(.None, .W))
        entries.add(appStrings().cmd_ZoomMenu, func|view = me|() { view.showZoomMenu() })
    }

    mtd promptGoToPage()
    {
        if not .surface or not .pdfView.pageCount() do
            return
        var options: EditDlgOptions
        options.title   = texts().ui_GoToPage
        options.message = Format.toString(texts().ui_PageRange, .pdfView.pageCount()).toString()
        options.text    = Format.toString("%", .pdfView.pageIndex + 1).toString()
        let dialog = EditDlg.createSingleLine(.surface, options)
        if dialog.doModal() != Dialog.BtnOk do
            return
        let typed = dialog.text()
        discard .goToTypedPage(typed)
    }

    // Offers the zoom presets, fit to page or width, and the continuous or single-page layout, with
    // the current fit and layout checked.
    mtd showZoomMenu()
    {
        let menu = MenuCtrl.createPopup(me, owner: me)
        menu.addItem("50%", "scope.pdf.zoom50")
        menu.addItem(texts().ui_Actual, "scope.pdf.zoomActual", .theme().icon(.ActualSize, themeRowIconSize(.themeMetrics())))
        menu.addItem("125%", "scope.pdf.zoom125")
        menu.addItem("150%", "scope.pdf.zoom150")
        menu.addItem("200%", "scope.pdf.zoom200")
        menu.addSeparator()
        menu.addItem(texts().ui_Fit, "scope.pdf.zoomFit", .theme().icon(.FitView, themeRowIconSize(.themeMetrics())), rightName: "F", checked: .pdfView.zoomMode == .FitPage)
        menu.addItem(texts().ui_FitWidth, "scope.pdf.zoomFitWidth", rightName: "W", checked: .pdfView.zoomMode == .FitWidth)
        menu.addSeparator()
        menu.addItem(texts().ui_Continuous, "scope.pdf.layoutContinuous", checked: .pdfView.pageLayout == .Continuous)
        menu.addItem(texts().ui_SinglePage, "scope.pdf.layoutSingle", checked: .pdfView.pageLayout == .Single)
        switch menu.doModal(.zoomLabel, autoDestroy: true) orelse ""
        {
        case "scope.pdf.zoom50":           .pdfView.setZoom(0.5)
        case "scope.pdf.zoomActual":       .pdfView.actualSize()
        case "scope.pdf.zoom125":          .pdfView.setZoom(1.25)
        case "scope.pdf.zoom150":          .pdfView.setZoom(1.5)
        case "scope.pdf.zoom200":          .pdfView.setZoom(2)
        case "scope.pdf.zoomFit":          .pdfView.zoomToFit()
        case "scope.pdf.zoomFitWidth":     .pdfView.zoomToFitWidth()
        case "scope.pdf.layoutContinuous": .pdfView.setPageLayout(.Continuous)
        case "scope.pdf.layoutSingle":     .pdfView.setPageLayout(.Single)
        }
    }

    // Creates the page view of `fileName`, with its page and zoom controls in `info`, and starts
    // opening the document in the background.
    func create(contentParent, info: *Wnd, fileName: string, services: Viewer.HostServices = {})->*Panel
    {
        with let result = Wnd.create'Panel(contentParent, "scope.pdf")
        {
            .backgroundStyle = .View
            .services        = services
            .info            = info
        }

        result.createPageControls()
        result.createZoomControl()
        result.createPageView()

        // The outline stands in the margin beside the page; choosing a part shows it.
        with result.margin = OutlineMargin.create(result, "scope.pdf.margin")
        {
            .label     = texts().ui_Contents
            .sigChosen += func|view = result|(_, row)
            {
                if row < view.marginParts.count
                {
                    let entry = &view.bookmarks[view.marginParts[row]]
                    view.pdfView.showPosition(entry.pageIndex, entry.position)
                }
            }
        }

        result.applyLayout()
        result.refreshZoom()
        result.load.start(fileName, &loadViewerContent, result)
        return result
    }

    // Creates the previous-page, page-number, and next-page controls at the start of the information group.
    mtd createPageControls()
    {
        let actionSize = themeActionButtonSize(.themeMetrics())
        with .previousButton = Viewer.createActionButton(.info, .ChevronLeft)
        {
            .dockStyle       = .Left
            .preferredSize.x = actionSize
            .toolTip         = texts().ui_Previous
            .sigPressed      += func|view = me|(_) { view.pdfView.previousPage() }
        }

        with .pageLabel = IconButton.create(.info, {}, {0, 0, PageWidth, 32}, "scope.pdf.page", .CenterContent)
        {
            .dockStyle       = .Left
            .preferredSize.x = PageWidth
            .margin.x        = 8
            .toolTip         = texts().ui_GoToPage
            .setForm(.Rectangle)
            .style.setFont(me.theme().createDefaultFontFs(11), .Regular)
            .sigPressed += func|view = me|(_) { view.promptGoToPage() }
        }

        with .nextButton = Viewer.createActionButton(.info, .ChevronRight)
        {
            .dockStyle       = .Left
            .preferredSize.x = actionSize
            .toolTip         = texts().ui_Next
            .sigPressed      += func|view = me|(_) { view.pdfView.nextPage() }
        }
    }

    // Creates the zoom menu button at the end of the information group.
    mtd createZoomControl()
    {
        with .zoomLabel = Viewer.createZoomButton(.info, "scope.pdf.zoom", texts().ui_ZoomMenu)
        {
            .dockStyle       = .Right
            .preferredSize.x = Viewer.ZoomButtonWidth
            .margin          = {Viewer.ZoomButtonInset + 8, 0, Viewer.ZoomButtonInset, 0}
            .sigPressed      += func|view = me|(_) { view.showZoomMenu() }
        }
    }

    // Creates the page view and keeps the controls in step with its page and zoom.
    mtd createPageView()
    {
        with .pdfView = PdfView.create(me)
        {
            .dockStyle      = .Center
            .sigPageChanged += func|view = me|(_)
            {
                view.refreshNavigation()
            }

            .sigZoomChanged += func|view = me|(_)
            {
                view.refreshZoom()
            }

            .sigRenderError += func|view = me|(_, message)
            {
                view.services.failed(view, message)
            }
        }
    }
}

// Creates the integrated PDF view.
func createViewer(host: Viewer.Host)
{
    let services  = host.services()
    let infoWidth = infoWidth(host.contentParent().themeMetrics())

    with let info = Wnd.create'InfoControls(host.createInfoGroup(infoWidth), Math.Rectangle{0, 0, infoWidth, 36})
    {
        .dockStyle       = .Left
        .backgroundStyle = .Transparent
        .preferredSize.x = infoWidth
    }

    let view = Panel.create(host.contentParent(), info, host.fileName(), services)
    host.attachView(view)
    view.outline = DocumentOutline.create(host)
    view.outline.sigSelected += func|view|(_, index)
    {
        if index < view.bookmarks.count
        {
            let entry = &view.bookmarks[index]
            view.pdfView.showPosition(entry.pageIndex, entry.position)
        }
    }

    // PDF text lives compressed inside the file, so the viewer extracts every page's text and
    // hands the host stable logical matches for counting and bidirectional navigation, a page at
    // a time as the extraction progresses on its worker.

    with var search: Viewer.SearchApi
    {
        .collectMatches = func|view|(text, options, progress, matches)->bool => view.collectMatches(text, options, progress, matches)
        .revealMatch    = func|view|(match, text)->bool => view.revealMatch(match, text)
        .matchBounds    = func|view|(match, bounds)->bool => view.searchBounds(match, bounds)
        .clear          = func|view|() => view.pdfView.clearSelection()
    }

    host.setSearch(search)
    host.setLensSource(func|view|(entries) { view.describeLens(entries) })

    host.setLifecycle(Viewer.loadLifecycle(view))
}
