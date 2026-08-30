#global internal

using Core, Pixel, Gui

private const PdfCommandWidth = 336.0

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
    result.details = Format.toString("PDF · % %", count, count == 1 ? pdfStrings().ui_Page : pdfStrings().ui_Pages)
    return #move result
}

internal struct PdfViewer
{
    using wnd:            Wnd
    details:              String
    reportFailure:        #null ViewerReportFailure
    reportDetails:        #null ViewerReportDetails
    reportLoadingChanged: #null ViewerReportLoadingChanged
    load:                 ViewerBackgroundLoad'PdfViewerContent
    loadTimer:            #null *Timer
    failureReason:        String

    #[Swag.Late]
    {
        commands:       *Wnd
        pdfView:        *PdfView
        previousButton: *IconButton
        nextButton:     *IconButton
        pageLabel:      *Label
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

    mtd collectMatches(text: string, options: ViewerSearchOptions, result: *Array'ViewerSearchMatch)
    {
        var pdfOptions: PdfTextSearchOptions
        pdfOptions.comparison        = options.matchCase ? .Latin1 : .Latin1NoCase
        pdfOptions.wholeWord         = options.wholeWord
        pdfOptions.regularExpression = options.regularExpression
        let matches = .pdfView.findTextMatches(text, pdfOptions)
        for match in matches do
            result.add({match.pageIndex, 0, match.byteOffset, match.byteLength})
    }

    mtd revealMatch(match: ViewerSearchMatch, text: string)->bool
    {
        discard text
        return .pdfView.revealTextMatch({match.major, match.offset, match.length})
    }

    mtd searchBounds(match: ViewerSearchMatch, result: *Math.Rectangle)->bool
    {
        return .pdfView.textMatchRect({match.major, match.offset, match.length}, result)
    }

    mtd refreshNavigation()
    {
        .previousButton.enable(.pdfView.pageIndex > 0)
        .nextButton.enable(.pdfView.pageIndex + 1 < .pdfView.pageCount())
        .pageLabel.setText(Format.toString("% / %", .pdfView.pageIndex + 1, .pdfView.pageCount()))
    }

    func create(contentParent, commands: *Wnd, fileName: string, reportFailure: #null ViewerReportFailure = null, reportDetails: #null ViewerReportDetails = null, reportLoadingChanged: #null ViewerReportLoadingChanged = null)->*PdfViewer
    {
        let result = Wnd.create'PdfViewer(contentParent, "scope.pdf")
        result.backgroundStyle      = .View
        result.reportFailure        = reportFailure
        result.reportDetails        = reportDetails
        result.reportLoadingChanged = reportLoadingChanged

        result.commands = commands

        with result.previousButton = IconButton.create(result.commands, result.theme().icon(.ChevronLeft, themeActionIconSize(result.themeMetrics())), {0, 0, themeActionButtonSize(result.themeMetrics()), themeActionButtonSize(result.themeMetrics())})
        {
            .dockStyle  = .Left
            .toolTip    = pdfStrings().ui_Previous
            .sigPressed += func|view = result|(button)
            {
                discard button
                view.pdfView.previousPage()
            }
        }

        with result.nextButton = IconButton.create(result.commands, result.theme().icon(.ChevronRight, themeActionIconSize(result.themeMetrics())), {0, 0, themeActionButtonSize(result.themeMetrics()), themeActionButtonSize(result.themeMetrics())})
        {
            .dockStyle  = .Left
            .toolTip    = pdfStrings().ui_Next
            .sigPressed += func|view = result|(button)
            {
                discard button
                view.pdfView.nextPage()
            }
        }

        with result.pageLabel = Label.create(result.commands, "", {0, 0, 76, 36}, null, .SecondaryText)
        {
            .dockStyle = .Left
            .margin.x  = 8
            .setTextAlignment(.Center, .Center)
        }

        with let zoomOut = IconButton.create(result.commands, result.theme().icon(.ZoomOut, themeActionIconSize(result.themeMetrics())), {0, 0, themeActionButtonSize(result.themeMetrics()), themeActionButtonSize(result.themeMetrics())})
        {
            .dockStyle  = .Left
            .margin.x   = 8
            .toolTip    = pdfStrings().ui_ZoomOut
            .sigPressed += func|view = result|(button)
            {
                discard button
                view.pdfView.zoomOut()
            }
        }

        with let zoomIn = IconButton.create(result.commands, result.theme().icon(.ZoomIn, themeActionIconSize(result.themeMetrics())), {0, 0, themeActionButtonSize(result.themeMetrics()), themeActionButtonSize(result.themeMetrics())})
        {
            .dockStyle  = .Left
            .toolTip    = pdfStrings().ui_ZoomIn
            .sigPressed += func|view = result|(button)
            {
                discard button
                view.pdfView.zoomIn()
            }
        }

        with let fit = IconButton.create(result.commands, result.theme().icon(.FitView, themeActionIconSize(result.themeMetrics())), {0, 0, themeActionButtonSize(result.themeMetrics()), themeActionButtonSize(result.themeMetrics())})
        {
            .dockStyle  = .Left
            .margin.x   = 8
            .toolTip    = pdfStrings().ui_Fit
            .sigPressed += func|view = result|(button)
            {
                discard button
                view.pdfView.zoomToFit()
            }
        }

        with let actual = IconButton.create(result.commands, result.theme().icon(.ActualSize, themeActionIconSize(result.themeMetrics())), {0, 0, themeActionButtonSize(result.themeMetrics()), themeActionButtonSize(result.themeMetrics())})
        {
            .dockStyle  = .Left
            .margin.x   = 8
            .toolTip    = pdfStrings().ui_Actual
            .sigPressed += func|view = result|(button)
            {
                discard button
                view.pdfView.actualSize()
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

            .sigRenderError += func|view = result|(pdf, message)
            {
                discard pdf
                if view.reportFailure do
                    view.reportFailure!(view, message)
            }
        }

        result.applyLayout()
        result.load.start(fileName, &loadPdfViewerContent)
        result.loadTimer = result.addTimer(ViewerBackgroundPollInterval)
        return result
    }
}

// Creates the integrated PDF view.
func createPdfViewer(host: FileViewer.Host)
{
    registerPdfStrings(host.application())
    let services = host.services()
    let view     = PdfViewer.create(host.contentParent(), host.createCommandGroup(PdfCommandWidth), host.fileName(), services.reportFailure, services.reportDetails, services.reportLoadingChanged)
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
