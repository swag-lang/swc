#global internal

using Core, Pixel, Gui

// Describes the PDF viewer to the host.
func pdfViewerPlugin()->Viewer.Plugin
{
    var result: retval
    result.key          = "pdf"
    result.staticName   = "PDF"
    result.attach       = &registerPdfStrings
    result.iconAtlas    = viewerIcons()
    result.iconIndex    = cast(s32) ViewerIcons.Pdf
    result.create       = &createPdfViewer
    result.smokeFixture = "viewer.pdf"
    result.addSelectors(".pdf")
    return result
}

private const PdfPageWidth = 76.0

private func pdfInfoWidth(metrics: const *ThemeMetrics)->f32
{
    return 2 * themeActionButtonSize(metrics) + PdfPageWidth + ViewerZoomSlotWidth + 16
}

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
}

private func loadPdfViewerContent(fileName: string)->PdfViewerContent fail
{
    var result: retval
    result.reader = #move try Pdf.Reader.open(fileName)
    let count = result.reader.pageCount()
    if !count do
        fail Errors.InvalidFormatError{"PDF document contains no page"}
    result.page    = #move try result.reader.loadPage(0)
    result.details = "PDF"
    return #move result
}

internal struct PdfViewer
{
    using wnd:            Wnd
    details:              String
    reportFailure:        #null Viewer.ReportFailure
    reportDetails:        #null Viewer.ReportDetails
    reportLoadingChanged: #null Viewer.ReportLoadingChanged
    load:                 Viewer.BackgroundLoad'PdfViewerContent
    loadTimer:            #null *Timer
    failureReason:        String

    #[Swag.Late]
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
        var content: PdfViewerContent
        .failureReason = .load.finish(&content)
        if !.failureReason.isEmpty()
        {
            if .reportFailure do
                .reportFailure!(me, .failureReason.toString())
            return
        }

        .pdfView.exchangeDocument(&content.reader, &content.page)
        .details = #move content.details
        .applyLayout()
        .refreshNavigation()
        .setInitialFocus(.pdfView)
        if .reportDetails do
            .reportDetails!(me, .details.toString())
        if .reportLoadingChanged do
            .reportLoadingChanged!(me)
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
        default:                                    evt.accepted = false
        }
    }
}

private impl PdfViewer
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

    mtd collectMatches(text: string, options: Viewer.SearchOptions, result: *Array'Viewer.SearchMatch)
    {
        var pdfOptions: PdfTextSearchOptions
        pdfOptions.comparison        = options.matchCase ? .Latin1 : .Latin1NoCase
        pdfOptions.wholeWord         = options.wholeWord
        pdfOptions.regularExpression = options.regularExpression
        let matches = .pdfView.findTextMatches(text, pdfOptions)
        for match in matches do
            result.add({match.pageIndex, 0, match.byteOffset, match.byteLength})
    }

    mtd revealMatch(match: Viewer.SearchMatch, text: string)->bool
    {
        discard text
        return .pdfView.revealTextMatch({match.major, match.offset, match.length})
    }

    mtd searchBounds(match: Viewer.SearchMatch, result: *Math.Rectangle)->bool
    {
        return .pdfView.textMatchRect({match.major, match.offset, match.length}, result)
    }

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
        if parseError != null or parsed.eat != text.count or parsed.ovf or !parsed.value or parsed.value > .pdfView.pageCount() do
            return false
        catch .pdfView.showPage(parsed.value - 1)
        return true
    }

    mtd promptGoToPage()
    {
        if !.surface or !.pdfView.pageCount() do
            return
        var options: EditDlgOptions
        options.title   = pdfStrings().ui_GoToPage
        options.message = Format.toString(pdfStrings().ui_PageRange, .pdfView.pageCount()).toString()
        options.text    = Format.toString("%", .pdfView.pageIndex + 1).toString()
        let dialog = EditDlg.createSingleLine(.surface!, options)
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
        menu.addItem(pdfStrings().ui_Fit, "scope.pdf.zoomFit", .theme().icon(.FitView, themeRowIconSize(.themeMetrics())), rightName: "F")
        switch menu.doModal(.zoomLabel, autoDestroy: true) orelse ""
        {
        case "scope.pdf.zoom50":     .pdfView.setZoom(0.5)
        case "scope.pdf.zoomActual": .pdfView.actualSize()
        case "scope.pdf.zoom125":    .pdfView.setZoom(1.25)
        case "scope.pdf.zoom150":    .pdfView.setZoom(1.5)
        case "scope.pdf.zoom200":    .pdfView.setZoom(2)
        case "scope.pdf.zoomFit":    .pdfView.zoomToFit()
        }
    }

    func create(contentParent, info: *Wnd, fileName: string, reportFailure: #null Viewer.ReportFailure = null, reportDetails: #null Viewer.ReportDetails = null, reportLoadingChanged: #null Viewer.ReportLoadingChanged = null)->*PdfViewer
    {
        let result = Wnd.create'PdfViewer(contentParent, "scope.pdf")
        result.backgroundStyle      = .View
        result.reportFailure        = reportFailure
        result.reportDetails        = reportDetails
        result.reportLoadingChanged = reportLoadingChanged

        result.info = info

        let actionSize = themeActionButtonSize(result.themeMetrics())
        let iconSize   = themeActionIconSize(result.themeMetrics())
        with result.previousButton = IconButton.create(result.info, result.theme().icon(.ChevronLeft, iconSize), {0, 0, actionSize, actionSize})
        {
            .dockStyle       = .Left
            .preferredSize.x = actionSize
            .toolTip         = pdfStrings().ui_Previous
            .sigPressed      += func|view = result|(button)
            {
                discard button
                view.pdfView.previousPage()
            }
        }

        with result.pageLabel = IconButton.create(result.info, {}, {0, 0, PdfPageWidth, 32}, "scope.pdf.page", .CenterContent)
        {
            .dockStyle       = .Left
            .preferredSize.x = PdfPageWidth
            .margin.x        = 8
            .setForm(.Rectangle)
            .style.setFont(result.theme().createDefaultFontFS(11), .Regular)
            .toolTip    = pdfStrings().ui_GoToPage
            .sigPressed += func|view = result|(button)
            {
                discard button
                view.promptGoToPage()
            }
        }

        with result.nextButton = IconButton.create(result.info, result.theme().icon(.ChevronRight, iconSize), {0, 0, actionSize, actionSize})
        {
            .dockStyle       = .Left
            .preferredSize.x = actionSize
            .toolTip         = pdfStrings().ui_Next
            .sigPressed      += func|view = result|(button)
            {
                discard button
                view.pdfView.nextPage()
            }
        }

        with result.zoomLabel = IconButton.create(result.info, {}, {0, 0, ViewerZoomButtonWidth, 32}, "scope.pdf.zoom", .CenterContent)
        {
            .dockStyle       = .Right
            .preferredSize.x = ViewerZoomButtonWidth
            .margin          = {ViewerInfoControlInset + 8, 0, ViewerInfoControlInset, 0}
            .setText("100%")
            .setArrowPosition(.RightDownward)
            .setForm(.Rectangle)
            .style.setFont(result.theme().createDefaultFontFS(11), .Regular)
            .toolTip    = pdfStrings().ui_ZoomMenu
            .sigPressed += func|view = result|(button)
            {
                discard button
                view.showZoomMenu()
            }
        }

        with result.pdfView = PdfView.create(result)
        {
            .dockStyle      = .Center
            .sigPageChanged += func|view = result|(pdf)
            {
                discard pdf
                view.refreshNavigation()
            }

            .sigZoomChanged += func|view = result|(pdf)
            {
                discard pdf
                view.refreshZoom()
            }

            .sigRenderError += func|view = result|(pdf, message)
            {
                discard pdf
                if view.reportFailure do
                    view.reportFailure!(view, message)
            }
        }

        result.applyLayout()
        result.refreshZoom()
        result.load.start(fileName, &loadPdfViewerContent)
        result.loadTimer = result.addTimer(Viewer.BackgroundPollInterval)
        return result
    }
}

// Creates the integrated PDF view.
func createPdfViewer(host: Viewer.Host)
{
    let services  = host.services()
    let infoWidth = pdfInfoWidth(host.contentParent().themeMetrics())
    let infoGroup = host.createInfoGroup(infoWidth)
    let info      = Wnd.create'PdfInfoControls(infoGroup, {0, 0, infoWidth, 36})
    info.dockStyle       = .Left
    info.backgroundStyle = .Transparent
    info.preferredSize.x = infoWidth
    let view = PdfViewer.create(host.contentParent(), info, host.fileName(), services.reportFailure, services.reportDetails, services.reportLoadingChanged)
    host.attachView(view)

    // PDF text lives compressed inside the file, so the viewer indexes every page and hands the
    // host stable logical matches for counting and bidirectional navigation.
    host.setSearch({
        collectMatches: func(wnd, text, options, matches) { (cast(*PdfViewer) wnd).collectMatches(text, options, matches) },
        revealMatch: func(wnd, match, text)->bool { return (cast(*PdfViewer) wnd).revealMatch(match, text) },
        matchBounds: func(wnd, match, bounds)->bool { return (cast(*PdfViewer) wnd).searchBounds(match, bounds) },
        clear: func(wnd) { (cast(*PdfViewer) wnd).pdfView.clearSelection() }})
    host.setLifecycle({
        isLoading: func(wnd)->bool { return (cast(*PdfViewer) wnd).loadTimer != null },
        needsLoadingOverlay: func(wnd)->bool { return (cast(*PdfViewer) wnd).loadTimer != null },
        retire: func(wnd)->bool { return (cast(*PdfViewer) wnd).retire() }})
}
