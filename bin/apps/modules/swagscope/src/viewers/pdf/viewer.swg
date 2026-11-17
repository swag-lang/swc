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
        .thumbnail    = &loadThumbnail
        .probe        = &pluginProbe
        .smokeFixture = "viewer.pdf"
        .addSelectors(".pdf")
    }

    return result
}

// Rasterizes the first page through the PDF viewer's own page engine.
private func loadThumbnail(fileName: string, maxSide: u32)->Image fail
{
    var reader = try Pdf.Reader.open(fileName)
    if not reader.pageCount() do
        fail Errors.InvalidFormatError{texts().err_NoPage}
    var page    = try reader.loadPage(0)
    let largest = Math.max(page.width, page.height, 1)
    let side    = Math.max(maxSide, 1'u32)
    return try page.render({scale: cast(f32, side) / largest,
                            maxDimension: cast(s32, side),
                            maxPixels: cast(u64, side) * side})
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
    labels:  Array'String     // Page labels the document gives, or empty when it gives none.
}

private func loadViewerContent(fileName: string)->ViewerContent fail
{
    var result: #returntype
    result.reader  = #move try Pdf.Reader.open(fileName)
    result.outline = result.reader.loadOutline()
    result.labels  = result.reader.loadPageLabels()
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
    pageLabels:    Array'String     // Labels the document gives its pages, one per page, or empty.
    history:       Viewer.History'PdfReadingPosition

    late
    {
        commands:       *Wnd
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
            .previousButton.toolTip = appStrings().ui_PreviousPage
            .nextButton.toolTip     = appStrings().ui_NextPage
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
        .history.clear()
        .bookmarks  = #move content.outline
        .pageLabels = #move content.labels
        .publishBookmarks()

        .facts   = #move content.facts
        .details = detailsText(&.facts)
        .applyLayout()
        .refreshNavigation()
        .services.showDetails(me, .details)
        .services.loadingChanged(me)
    }

    mtd impl onKeyEvent(evt: *KeyEvent)
    {
        if evt.kind != .Pressed
        {
            evt.accepted = false
            return
        }

        if .handleHistoryKey(evt) do
            return

        switch evt.key
        {
        case .Add, .OemPlus where evt.modifiers == .Control:       .pdfView.zoomIn()
        case .Subtract, .OemMinus where evt.modifiers == .Control: .pdfView.zoomOut()
        case .D0 where evt.modifiers == .Control:                  .pdfView.actualSize()
        case .F where evt.modifiers == .None:                      .pdfView.zoomToFit()
        case .W where evt.modifiers == .None:                      .pdfView.zoomToFitWidth()
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

    // Says which pages carry text: every one, none, or how many are pictures without it, then how
    // many could not be read.
    mtd textLayerText(pictures, unreadable: u64)->String
    {
        let pages = .pdfView.pageCount()
        var result: String
        if pictures == pages do
            result = String.from(texts().ui_TextLayerNone)
        elif pictures do
            result = Format.toString(texts().ui_TextLayerSome, pictures, pages)
        elif not unreadable do
            result = String.from(texts().ui_TextLayerAll)
        if unreadable
        {
            if not result.isEmpty() do
                result += " · "
            if unreadable == 1 do
                result += texts().ui_TextLayerOneUnreadable
            else do
                result += Format.toString(texts().ui_TextLayerUnreadable, unreadable)
        }

        return result
    }

    // Says why a complete search found nothing when pages hold no searchable words: pictures of
    // pages without a text layer, which reading cannot tell from text, and pages whose text could
    // not be read. A document whose every page has text leaves the plain answer.
    mtd explainSearch()->String
    {
        var result: String
        let coverage = .pdfView.textCoverage()
        if not coverage.complete do
            return result

        let pages = .pdfView.pageCount()
        if coverage.pictures == pages do
            result = texts().ui_NoTextLayer
        elif coverage.pictures == 1 do
            result = Format.toString(texts().ui_OneNoText, pages)
        elif coverage.pictures do
            result = Format.toString(texts().ui_SomeNoText, coverage.pictures, pages)
        if coverage.unreadable
        {
            if not result.isEmpty() do
                result += " · "
            if coverage.unreadable == 1 do
                result += texts().ui_OneUnreadable
            else do
                result += Format.toString(texts().ui_Unreadable, coverage.unreadable)
        }

        return result
    }

    mtd searchBounds(match: Viewer.SearchMatch, result: *Math.Rectangle)->bool => .pdfView.textMatchRect(PdfTextMatch{match.major, match.offset, match.length}, result)

    mtd refreshNavigation()
    {
        .previousButton.enable(.pdfView.pageIndex > 0)
        .nextButton.enable(.pdfView.pageIndex + 1 < .pdfView.pageCount())
        .pageLabel.setText(.pageReadout())
    }

    // Returns the size the pages are shown at, in percent of the size they would print at, as the
    // zoom readout shows it. A page's 100 % is its actual size, as a picture's is its own pixels.
    internal mtd zoomPercent()->u32 => cast(u32, Math.round(.pdfView.effectiveZoom() / PdfView.ActualSizeZoom * 100))

    mtd refreshZoom()
    {
        .zoomLabel.setText(Viewer.zoomText(.zoomPercent()))
    }

    // Shows the pages at `percent` of their actual size.
    internal mtd setZoomPercent(percent: u32)
    {
        .pdfView.setZoom(PdfView.ActualSizeZoom * cast(f32, percent) / 100)
    }

    // Returns the label the document gives page `index`, or an empty string when it is only its
    // position: no labels, or a label that is the page number itself.
    internal mtd pageLabelOf(index: u64)->string
    {
        if index >= .pageLabels.count do
            return ""
        let label = .pageLabels[index].toString()
        return label == Format.toString("%", index + 1).toString() ? "" : label
    }

    // Returns the page readout: the position among the pages, after the page's own label when the
    // document gives one and it fits the readout, as `iv (4/120)`.
    internal mtd pageReadout()->String
    {
        const LabelledLimit = 13'u64
        let position = Format.toString("%/%", Math.min(.pdfView.pageIndex + 1, .pdfView.pageCount()), .pdfView.pageCount())
        let label    = .pageLabelOf(.pdfView.pageIndex)
        if label.count and label.count + position.length + 3 <= LabelledLimit do
            return Format.toString("% (%)", label, position)
        return Viewer.pageText(.pdfView.pageIndex, .pdfView.pageCount())
    }

    // Moves to the page `text` names: its position, counted from one, or else the label the
    // document gives it, compared without case.
    internal mtd goToTypedPage(text: string)->bool
    {
        let index = .typedPageIndex(text)
        if index == Swag.U64.Max do
            return false
        .history.visit(.pdfView.readingPosition())
        .pdfView.showPage(index)
        return true
    }

    // Returns the index of the page `text` names, its position counted from one or else the label
    // the document gives it, compared without case; `U64.Max` when it names none.
    internal mtd typedPageIndex(text: string)->u64
    {
        let typed = Latin1.trim(text)
        for label, index in .pageLabels where typed.count and
                                              not Latin1.isDigit(typed[0]) and
                                              Utf8.compare(label.toString(), typed, .Latin1NoCase) == 0 do
            return index

        var parseErrorOutcome: Swag.Error
        var parsed: #decltype(expect StrConv.parseU64(typed))
        catch { parsed = try StrConv.parseU64(typed) } as parseErrorOutcome
        let parseError = parseErrorOutcome.value()
        if parseError != null or
           parsed.eat != typed.count or
           parsed.ovf or
           not parsed.value or
           parsed.value > .pdfView.pageCount() do
            return Swag.U64.Max
        return parsed.value - 1
    }

    // Lists the bookmarks in the outline, each addressed by its index, so the outline can filter
    // them and find them again.
    mtd publishBookmarks()
    {
        if not .outline do
            return
        var headings: Array'DocumentHeading
        for entry, index in .bookmarks do
            headings.add(DocumentHeading{entry.title, entry.level, index})
        .outline.publish(headings.toSlice())
    }

    // Marks in the outline the bookmark being read: the last one at or before the point standing
    // at the top of the view. At the end of the document a later bookmark cannot rise to the top,
    // so one the reader chose there stays marked.
    internal mtd followReading()
    {
        if not .outline do
            return
        let place = .pdfView.readingPosition()
        if not place.isValid() do
            return

        // A bookmark's point is brought to the top of the view within a rounding of the scroll.
        const Slack = 1.0
        var reading = Swag.U64.Max
        for entry, index in .bookmarks where entry.pageIndex < place.pageIndex or
                                             (entry.pageIndex == place.pageIndex and entry.position.y <= place.point.y + Slack) do
            reading = index
        if reading == Swag.U64.Max do
            return

        .outline.markReading(reading, atEnd: .pdfView.readingProgress() >= 1)
    }

    // Shows the place a bookmark names, remembering the one the reader leaves. A bookmark that
    // only groups others, or whose destination the document does not resolve, moves nothing.
    internal mtd showBookmark(index: u64)
    {
        if index >= .bookmarks.count do
            return
        let entry = &.bookmarks[index]
        if entry.pageIndex >= .pdfView.pageCount() do
            return
        .history.visit(.pdfView.readingPosition())
        .pdfView.showPosition(entry.pageIndex, entry.position)
    }

    // Returns to the place the last jump left, at the zoom it was read at.
    internal mtd goBack()
    {
        if .history.canGoBack() do
            discard .pdfView.restoreReadingPosition(.history.back(.pdfView.readingPosition()))
    }

    // Undoes the last return.
    internal mtd goForward()
    {
        if .history.canGoForward() do
            discard .pdfView.restoreReadingPosition(.history.forward(.pdfView.readingPosition()))
    }

    mtd handleHistoryKey(evt: const *KeyEvent)->bool
    {
        let direction = Viewer.historyKeyDirection(evt)
        if direction < 0 do
            .goBack()
        elif direction > 0 do
            .goForward()
        return direction != 0
    }

    // Gives the lens the pages and the zoom of the document.
    internal mtd describeLens(entries: *Viewer.LensEntries)
    {
        // `:` and a page, by its position or its label, go to that page.
        if entries.results.prefix == .Line
        {
            let index = .typedPageIndex(entries.query.toString())
            if index == Swag.U64.Max do
                return
            let label = .pageLabelOf(index)
            let named = label.count ? Format.toString("% (%)", label, index + 1) : Format.toString("%", index + 1)
            let entry = entries.add(Format.toString(appStrings().lens_GoToPage, named), .GoTo, func|view = me, index|()
            {
                view.history.visit(view.pdfView.readingPosition())
                view.pdfView.showPage(index)
            })

            // The row leads with the page's position, as the other numbered jump rows do: a label
            // with its position would not fit the narrow column before the title.
            if entry do
                entry.lead = Format.toString("%", index + 1)
            return
        }

        let strings = texts()
        entries.add(strings.ui_Previous, .ChevronLeft, func|view = me|() { view.pdfView.previousPage() }, disabled: not .previousButton.isEnabled(), shortcut: Input.formatKeyShortcut(.Control, .PageUp))
        entries.add(strings.ui_Next, .ChevronRight, func|view = me|() { view.pdfView.nextPage() }, disabled: not .nextButton.isEnabled(), shortcut: Input.formatKeyShortcut(.Control, .PageDown))
        entries.add(strings.ui_GoToPage, .GoTo, func|view = me|() { view.promptGoToPage() })
        entries.add(strings.ui_Back, .ChevronLeft, func|view = me|() { view.goBack() }, disabled: not .history.canGoBack(), shortcut: Input.formatKeyShortcut(.Alt, .Left))
        entries.add(strings.ui_Forward, .ChevronRight, func|view = me|() { view.goForward() }, disabled: not .history.canGoForward(), shortcut: Input.formatKeyShortcut(.Alt, .Right))

        // The page view zooms by factors, far past the shared bounds, so only actual size, the
        // 100 % of the readout, is the shared row; it reads as chosen while the pages show at it.
        // The steps read as unavailable at the page view's own limits.
        entries.add(appStrings().cmd_ZoomIn, .ZoomIn, func|view = me|() { view.pdfView.zoomIn() }, disabled: not .pdfView.canZoomIn(), shortcut: Input.formatKeyShortcut(.Control, .OemPlus))
        entries.add(appStrings().cmd_ZoomOut, .ZoomOut, func|view = me|() { view.pdfView.zoomOut() }, disabled: not .pdfView.canZoomOut(), shortcut: Input.formatKeyShortcut(.Control, .OemMinus))
        entries.addZoom(.Reset, .zoomPercent(), func|view = me|() { view.pdfView.actualSize() })
        entries.add(strings.ui_Fit, .FitView, func|view = me|() { view.pdfView.zoomToFit() }, checked: .pdfView.zoomMode == .FitPage, shortcut: Input.formatKeyShortcut(.None, .F))
        entries.add(strings.ui_FitWidth, .FitWidth, func|view = me|() { view.pdfView.zoomToFitWidth() }, checked: .pdfView.zoomMode == .FitWidth, shortcut: Input.formatKeyShortcut(.None, .W))
        entries.add(appStrings().cmd_ZoomMenu, .ZoomIn, func|view = me|() { view.showZoomMenu() })

        // The commands of the page's context menu, so none of them needs a right click.
        entries.add(strings.ui_CopyText, .Copy, func|view = me|() { discard view.pdfView.copySelection() }, disabled: not .pdfView.hasSelection(), shortcut: Input.formatKeyShortcut(.Control, .C))
        entries.add(strings.ui_SelectPage, .SelectAll, func|view = me|() { view.pdfView.selectAll() }, disabled: not .pdfView.pageCount(), shortcut: Input.formatKeyShortcut(.Control, .A))
    }

    mtd promptGoToPage()
    {
        if not .surface or not .pdfView.pageCount() do
            return
        var options: EditDlgOptions
        options.title   = texts().ui_GoToPage
        options.message = Format.toString(texts().ui_PageRange, .pdfView.pageCount()).toString()
        options.text    = Format.toString("%", .pdfView.pageIndex + 1).toString()
        let label = .pageLabelOf(.pdfView.pageIndex)
        if label.count
        {
            options.message = Format.toString(texts().ui_PageRangeLabels, .pdfView.pageCount(), label).toString()
            options.text    = label
        }

        let dialog = EditDlg.createSingleLine(.surface, options)
        if dialog.doModal() != Dialog.BtnOk do
            return
        let typed = dialog.text()
        discard .goToTypedPage(typed)
    }

    // Offers the zoom presets, fit to page or width, and the continuous or single-page layout, with
    // the level in use, the fit and the layout checked.
    mtd showZoomMenu()
    {
        let menu    = MenuCtrl.createPopup(me, owner: me)
        let percent = .zoomPercent()
        menu.addItem("50 %", "scope.pdf.zoom50", .theme().icon(.ZoomOut, themeRowIconSize(.themeMetrics())), checked: percent == 50)
        menu.addItem("100 %", "scope.pdf.zoomActual", .theme().icon(.ActualSize, themeRowIconSize(.themeMetrics())), checked: percent == 100)
        menu.addItem("125 %", "scope.pdf.zoom125", .theme().icon(.ZoomIn, themeRowIconSize(.themeMetrics())), checked: percent == 125)
        menu.addItem("150 %", "scope.pdf.zoom150", .theme().icon(.ZoomIn, themeRowIconSize(.themeMetrics())), checked: percent == 150)
        menu.addItem("200 %", "scope.pdf.zoom200", .theme().icon(.ZoomIn, themeRowIconSize(.themeMetrics())), checked: percent == 200)
        menu.addSeparator()
        menu.addItem(texts().ui_Fit, "scope.pdf.zoomFit", .theme().icon(.FitView, themeRowIconSize(.themeMetrics())), rightName: "F", checked: .pdfView.zoomMode == .FitPage)
        menu.addItem(texts().ui_FitWidth, "scope.pdf.zoomFitWidth", .theme().icon(.FitWidth, themeRowIconSize(.themeMetrics())), rightName: "W", checked: .pdfView.zoomMode == .FitWidth)
        menu.addSeparator()
        menu.addItem(texts().ui_Continuous, "scope.pdf.layoutContinuous", .theme().icon(.Outline, themeRowIconSize(.themeMetrics())), checked: .pdfView.pageLayout == .Continuous)
        menu.addItem(texts().ui_SinglePage, "scope.pdf.layoutSingle", .theme().icon(.File, themeRowIconSize(.themeMetrics())), checked: .pdfView.pageLayout == .Single)
        switch menu.doModal(.zoomLabel, autoDestroy: true) orelse ""
        {
        case "scope.pdf.zoom50":           .setZoomPercent(50)
        case "scope.pdf.zoomActual":       .pdfView.actualSize()
        case "scope.pdf.zoom125":          .setZoomPercent(125)
        case "scope.pdf.zoom150":          .setZoomPercent(150)
        case "scope.pdf.zoom200":          .setZoomPercent(200)
        case "scope.pdf.zoomFit":          .pdfView.zoomToFit()
        case "scope.pdf.zoomFitWidth":     .pdfView.zoomToFitWidth()
        case "scope.pdf.layoutContinuous": .pdfView.setPageLayout(.Continuous)
        case "scope.pdf.layoutSingle":     .pdfView.setPageLayout(.Single)
        }
    }

    // Creates the page view of `fileName`, with pagination in `commands` and zoom in `info`, and starts
    // opening the document in the background.
    func create(contentParent, info, commands: *Wnd, fileName: string, services: Viewer.HostServices = {})->*Panel
    {
        with let result = Wnd.create'Panel(contentParent, "scope.pdf")
        {
            .backgroundStyle = .View
            .services        = services
            .info            = info
            .commands        = commands
        }

        result.createPageControls()
        result.createZoomControl()
        result.createPageView()
        result.hookOnChildEvent = func|view = result|(_, evt)->bool
        {
            if evt is KeyEvent as key
            {
                if view.handleHistoryKey(key) do
                    return true
                let direction = Viewer.pageKeyDirection(key)
                if direction < 0 do
                    view.pdfView.previousPage()
                elif direction > 0 do
                    view.pdfView.nextPage()
                return direction != 0
            }

            return false
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
        with .previousButton = Viewer.createPageStep(.commands, -1)
        {
            .dockStyle       = .Left
            .preferredSize.x = actionSize
            .toolTip         = texts().ui_Previous
            .sigPressed      += func|view = me|(_) { view.pdfView.previousPage() }
        }

        with .pageLabel = Viewer.createPageReadout(.commands, "scope.pdf.page", texts().ui_GoToPage)
        {
            .sigPressed += func|view = me|(_) { view.promptGoToPage() }
        }

        with .nextButton = Viewer.createPageStep(.commands, 1)
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
            .margin          = {Viewer.ZoomButtonInset, 0, Viewer.ZoomButtonInset, 0}
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

            // The text layer of every page is known; the information sheet can state it.
            .sigTextExtracted += func|view = me|(_)
            {
                view.services.informationChanged(view)
            }

            .sigZoomChanged += func|view = me|(_)
            {
                view.refreshZoom()
            }

            // Only an open outline follows the reading as it moves; a closed one catches up as it opens.
            .sigScrolled += func|view = me|(_)
            {
                view.outline?.followOpenReading()
            }

            .sigRenderError += func|view = me|(_, message)
            {
                view.services.failed(view, message)
            }
        }
    }
}

// Creates the integrated PDF view.
impl Panel
{
    // Describes the document in the information sheet: its pages and their size, then its title,
    // author and bookmarks when it records them.
    mtd describeInformation(sheet: *InfoSheet)
    {
        if not .facts.pageCount do
            return
        var data: MediaInfoData
        let pages = .facts.pageCount == 1 ? String.from(texts().ui_OnePage) : Format.toString(texts().ui_Pages, .facts.pageCount)
        data.addFigure(.Pages, pages)
        if .facts.pageSize.x > 0 and .facts.pageSize.y > 0 do
            data.addFigure(.Dimensions, paperText(.facts.pageSize))
        data.add(.Document, group: true)
        if not .facts.title.isEmpty() do
            data.add(.Title, .facts.title)
        if not .facts.author.isEmpty() do
            data.add(.Author, .facts.author)
        if .bookmarks.count do
            data.add(.Bookmarks, Format.toString("%", .bookmarks.count))

        // Whether the pages carry text is known once the text the search reads has been
        // extracted, which the sheet starts and then waits for.
        .pdfView.extractText()
        let coverage = .pdfView.textCoverage()
        if coverage.complete do
            data.add(.TextLayer, .textLayerText(coverage.pictures, coverage.unreadable))
        data.describe(sheet)
    }
}

func createViewer(host: Viewer.Host)
{
    let services = host.services()
    let info     = host.createInfoGroup(Viewer.ZoomSlotWidth)
    let commands = host.createCommandGroup(Viewer.pageControlWidth(host.contentParent().themeMetrics()))
    let view     = Panel.create(host.contentParent(), info, commands, host.fileName(), services)
    host.attachView(view)
    view.outline             = DocumentOutline.create(host)
    view.outline.sigSelected += func|view|(_, index) { view.showBookmark(index) }
    view.outline.follow      = func|view|() { view.followReading() }

    // PDF text lives compressed inside the file, so the viewer extracts every page's text and
    // hands the host stable logical matches for counting and bidirectional navigation, a page at
    // a time as the extraction progresses on its worker.

    with var search: Viewer.SearchApi
    {
        .collectMatches = func|view|(text, options, progress, matches)->bool => view.collectMatches(text, options, progress, matches)
        .revealMatch    = func|view|(match, text)->bool => view.revealMatch(match, text)
        .matchBounds    = func|view|(match, bounds)->bool => view.searchBounds(match, bounds)
        .clear          = func|view|() => view.pdfView.clearSelection()
        .explainSearch  = func|view|(_)->String => view.explainSearch()
    }

    host.setSearch(search)
    host.setLensSource(func|view|(entries) { view.describeLens(entries) })
    host.setInformation(func|view|(sheet) { view.describeInformation(sheet) })

    host.setLifecycle(Viewer.loadLifecycle(view))
}
