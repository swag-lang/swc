#global internal

using Core, Pixel, Gui

// Offers the page surface for a document that carries the PDF header, whatever it is called.
private func pdfPluginProbe(content: Viewer.ProbeContent)->bool => content.startsWith("%PDF-")

// Describes the PDF viewer to the host.
func pdfViewerPlugin()->Viewer.Plugin
{
    with var result: retval
    {
        .key          = "pdf"
        .staticName   = "PDF"
        .attach       = &registerPdfStrings
        .iconAtlas    = viewerIcons()
        .iconIndex    = cast(s32) ViewerIcons.Pdf
        .create       = &createPdfViewer
        .probe        = &pdfPluginProbe
        .smokeFixture = "viewer.pdf"
        .addSelectors(".pdf")
    }

    return result
}

private const PdfPageWidth = 76.0

private func pdfInfoWidth(metrics: const *ThemeMetrics)->f32 => 2 * themeActionButtonSize(metrics) + PdfPageWidth + ViewerZoomSlotWidth + 16

// Keeps the page controls and zoom selector in one fixed-width run. Their authored cells are
// wider than their current text and icons, so measuring each child by its contents would let the
// host shrink the group until the left- and right-docked controls overlap.
private struct PdfInfoControls
{
    using wnd: Wnd
}

private impl IWnd for PdfInfoControls
{
    mtd impl measureContent(available: Math.Point)->Math.Point
    {
        discard available
        return .preferredSize
    }
}

struct PdfViewerContent
{
    reader:  Pdf.Reader
    page:    Pdf.Page
    details: String
    outline: Array'Pdf.OutlineEntry
}

private func loadPdfViewerContent(fileName: string)->PdfViewerContent fail
{
    var result: retval
    result.reader  = #move try Pdf.Reader.open(fileName)
    result.outline = result.reader.loadOutline()
    if not result.reader.pageCount() do
        fail Errors.InvalidFormatError{"PDF document contains no page"}
    result.page    = #move try result.reader.loadPage(0)
    result.details = "PDF"
    return #move result
}

struct PdfViewer
{
    using wnd:            Wnd
    details:              String
    reportFailure:        Viewer.ReportFailure?
    reportDetails:        Viewer.ReportDetails?
    reportLoadingChanged: Viewer.ReportLoadingChanged?
    load:                 Viewer.BackgroundLoad'PdfViewerContent
    loadTimer:            *Timer?
    failureReason:        String
    outline:              *DocumentOutline?
    bookmarks:            Array'Pdf.OutlineEntry

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

private impl IWnd for PdfViewer
{
    mtd impl onNotifyEvent(evt: *NotifyEvent)
    {
        if evt.kind == .LanguageChanged
        {
            .previousButton.toolTip = pdfStrings().ui_Previous
            .nextButton.toolTip     = pdfStrings().ui_Next
            .pageLabel.toolTip      = pdfStrings().ui_GoToPage
            .zoomLabel.toolTip      = pdfStrings().ui_ZoomMenu
        }

        .wnd.IWnd.onNotifyEvent(evt)
    }

    mtd impl onTimerEvent(evt: *TimerEvent)
    {
        if evt.timer != .loadTimer
        {
            evt.accepted = false
            return
        }

        if not .load.isDone() do
            return

        .removeTimer(evt.timer)
        .loadTimer = null
        var content: PdfViewerContent
        .failureReason = .load.finish(&content)
        if not .failureReason.isEmpty()
        {
            if .reportFailure do
                .reportFailure(me, .failureReason.toString())
            return
        }

        .pdfView.exchangeDocument(&content.reader, &content.page)
        .bookmarks = #move content.outline
        if .outline
        {
            .outline.clear()
            for entry, index in .bookmarks do
                .outline.add(entry.title.toString(), entry.level, index)
            .outline.refresh()
        }

        .details = #move content.details
        .applyLayout()
        .refreshNavigation()
        .setInitialFocus(.pdfView)
        if .reportDetails do
            .reportDetails(me, .details.toString())
        if .reportLoadingChanged do
            .reportLoadingChanged(me)
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

private impl PdfViewer
{
    mtd retire()->bool
    {
        if not .load.retire() do
            return false
        if .loadTimer
        {
            .removeTimer(.loadTimer)
            .loadTimer = null
        }

        return true
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
            result.add({match.pageIndex, 0, match.byteOffset, match.byteLength})
        return complete
    }

    mtd revealMatch(match: Viewer.SearchMatch, text: string)->bool
    {
        discard text
        return .pdfView.revealTextMatch({match.major, match.offset, match.length})
    }

    mtd searchBounds(match: Viewer.SearchMatch, result: *Math.Rectangle)->bool => .pdfView.textMatchRect({match.major, match.offset, match.length}, result)

    mtd refreshNavigation()
    {
        .previousButton.enable(.pdfView.pageIndex > 0)
        .nextButton.enable(.pdfView.pageIndex + 1 < .pdfView.pageCount())
        .pageLabel.setText(Format.toString("% / %", .pdfView.pageIndex + 1, .pdfView.pageCount()))
    }

    mtd refreshZoom()
    {
        .zoomLabel.setText(Format.toString("% %", cast(u32) Math.round(.pdfView.effectiveZoom() * 100), "%"))
    }

    mtd goToTypedPage(text: string)->bool
    {
        let parsed = catch StrConv.parseU64(text) as parseError
        if parseError != null or parsed.eat != text.count or parsed.ovf or not parsed.value or parsed.value > .pdfView.pageCount() do
            return false
        .pdfView.showPage(parsed.value - 1)
        return true
    }

    mtd promptGoToPage()
    {
        if not .surface or not .pdfView.pageCount() do
            return
        var options: EditDlgOptions
        options.title   = pdfStrings().ui_GoToPage
        options.message = Format.toString(pdfStrings().ui_PageRange, .pdfView.pageCount()).toString()
        options.text    = Format.toString("%", .pdfView.pageIndex + 1).toString()
        let dialog = EditDlg.createSingleLine(.surface, options)
        if dialog.doModal() != Dialog.BtnOk do
            return
        let typed = dialog.text()
        discard .goToTypedPage(typed.toString())
    }

    mtd showZoomMenu()
    {
        let menu = MenuCtrl.createPopup(me, owner: me)
        menu.addItem("50%", "scope.pdf.zoom50")
        menu.addItem(pdfStrings().ui_Actual, "scope.pdf.zoomActual", .theme().icon(.ActualSize, themeRowIconSize(.themeMetrics())))
        menu.addItem("125%", "scope.pdf.zoom125")
        menu.addItem("150%", "scope.pdf.zoom150")
        menu.addItem("200%", "scope.pdf.zoom200")
        menu.addSeparator()
        menu.addItem(pdfStrings().ui_Fit, "scope.pdf.zoomFit", .theme().icon(.FitView, themeRowIconSize(.themeMetrics())), rightName: "F", checked: .pdfView.zoomMode == .FitPage)
        menu.addItem(pdfStrings().ui_FitWidth, "scope.pdf.zoomFitWidth", rightName: "W", checked: .pdfView.zoomMode == .FitWidth)
        menu.addSeparator()
        menu.addItem(pdfStrings().ui_Continuous, "scope.pdf.layoutContinuous", checked: .pdfView.pageLayout == .Continuous)
        menu.addItem(pdfStrings().ui_SinglePage, "scope.pdf.layoutSingle", checked: .pdfView.pageLayout == .Single)
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
    func create(contentParent, info: *Wnd, fileName: string, reportFailure: Viewer.ReportFailure? = null, reportDetails: Viewer.ReportDetails? = null, reportLoadingChanged: Viewer.ReportLoadingChanged? = null)->*PdfViewer
    {
        with let result = Wnd.create'PdfViewer(contentParent, "scope.pdf")
        {
            .backgroundStyle      = .View
            .reportFailure        = reportFailure
            .reportDetails        = reportDetails
            .reportLoadingChanged = reportLoadingChanged
            .info                 = info
        }

        result.createPageControls()
        result.createZoomControl()
        result.createPageView()

        result.applyLayout()
        result.refreshZoom()
        result.load.start(fileName, &loadPdfViewerContent)
        result.loadTimer = result.addTimer(Viewer.BackgroundPollInterval)
        return result
    }

    // Creates the previous-page, page-number, and next-page controls at the start of the information group.
    mtd createPageControls()
    {
        let actionSize = themeActionButtonSize(.themeMetrics())
        let iconSize   = themeActionIconSize(.themeMetrics())
        with .previousButton = IconButton.create(.info, .theme().icon(.ChevronLeft, iconSize), {0, 0, actionSize, actionSize})
        {
            .dockStyle       = .Left
            .preferredSize.x = actionSize
            .toolTip         = pdfStrings().ui_Previous
            .sigPressed      += func|view = me|(button)
            {
                discard button
                view.pdfView.previousPage()
            }
        }

        with .pageLabel = IconButton.create(.info, {}, {0, 0, PdfPageWidth, 32}, "scope.pdf.page", .CenterContent)
        {
            .dockStyle       = .Left
            .preferredSize.x = PdfPageWidth
            .margin.x        = 8
            .setForm(.Rectangle)
            .style.setFont(me.theme().createDefaultFontFs(11), .Regular)
            .toolTip    = pdfStrings().ui_GoToPage
            .sigPressed += func|view = me|(button)
            {
                discard button
                view.promptGoToPage()
            }
        }

        with .nextButton = IconButton.create(.info, .theme().icon(.ChevronRight, iconSize), {0, 0, actionSize, actionSize})
        {
            .dockStyle       = .Left
            .preferredSize.x = actionSize
            .toolTip         = pdfStrings().ui_Next
            .sigPressed      += func|view = me|(button)
            {
                discard button
                view.pdfView.nextPage()
            }
        }
    }

    // Creates the zoom menu button at the end of the information group.
    mtd createZoomControl()
    {
        with .zoomLabel = IconButton.create(.info, {}, {0, 0, ViewerZoomButtonWidth, 32}, "scope.pdf.zoom", .CenterContent)
        {
            .dockStyle       = .Right
            .preferredSize.x = ViewerZoomButtonWidth
            .margin          = {ViewerInfoControlInset + 8, 0, ViewerInfoControlInset, 0}
            .setText("100%")
            .setArrowPosition(.RightDownward)
            .setForm(.Rectangle)
            .style.setFont(me.theme().createDefaultFontFs(11), .Regular)
            .toolTip    = pdfStrings().ui_ZoomMenu
            .sigPressed += func|view = me|(button)
            {
                discard button
                view.showZoomMenu()
            }
        }
    }

    // Creates the page view and keeps the controls in step with its page and zoom.
    mtd createPageView()
    {
        with .pdfView = PdfView.create(me)
        {
            .dockStyle      = .Center
            .sigPageChanged += func|view = me|(pdf)
            {
                discard pdf
                view.refreshNavigation()
            }

            .sigZoomChanged += func|view = me|(pdf)
            {
                discard pdf
                view.refreshZoom()
            }

            .sigRenderError += func|view = me|(pdf, message)
            {
                discard pdf
                if view.reportFailure do
                    view.reportFailure(view, message)
            }
        }
    }
}

// Creates the integrated PDF view.
func createPdfViewer(host: Viewer.Host)
{
    let services  = host.services()
    let infoWidth = pdfInfoWidth(host.contentParent().themeMetrics())
    with let info = Wnd.create'PdfInfoControls(host.createInfoGroup(infoWidth), {0, 0, infoWidth, 36})
    {
        .dockStyle       = .Left
        .backgroundStyle = .Transparent
        .preferredSize.x = infoWidth
    }

    let view = PdfViewer.create(host.contentParent(), info, host.fileName(), services.reportFailure, services.reportDetails, services.reportLoadingChanged)
    host.attachView(view)
    view.outline = DocumentOutline.create(host)
    view.outline.sigSelected += func|view|(panel, index)
    {
        discard panel
        if index < view.bookmarks.count
        {
            let entry = &view.bookmarks[index]
            view.pdfView.showPosition(entry.pageIndex, entry.position)
        }
    }

    // PDF text lives compressed inside the file, so the viewer extracts every page's text and
    // hands the host stable logical matches for counting and bidirectional navigation, a page at
    // a time as the extraction progresses on its worker.
    host.setSearch({
        collectMatches: func(wnd, text, options, progress, matches)->bool => (cast #assume (*PdfViewer) wnd).collectMatches(text, options, progress, matches),
        revealMatch: func(wnd, match, text)->bool => (cast #assume (*PdfViewer) wnd).revealMatch(match, text),
        matchBounds: func(wnd, match, bounds)->bool => (cast #assume (*PdfViewer) wnd).searchBounds(match, bounds),
        clear: func(wnd) { (cast #assume (*PdfViewer) wnd).pdfView.clearSelection() }})
    host.setLifecycle({
        isLoading: func(wnd)->bool => (cast #assume (*PdfViewer) wnd).loadTimer != null,
        needsLoadingOverlay: func(wnd)->bool => (cast #assume (*PdfViewer) wnd).loadTimer != null,
        retire: func(wnd)->bool => (cast #assume (*PdfViewer) wnd).retire()})
}
