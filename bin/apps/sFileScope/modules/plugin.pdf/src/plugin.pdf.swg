#global public

using Core, Pixel, Gui

private const PdfCommandWidth = 292.0

internal struct PdfPluginView
{
    using wnd:     Wnd
    details:       String
    reportFailure: #null ViewerReportFailure

    #[Swag.Late]
    {
        commands:       *Wnd
        pdfView:        *PdfView
        previousButton: *IconButton
        nextButton:     *IconButton
        pageLabel:      *Label
    }
}

private impl PdfPluginView
{
    mtd refreshNavigation()
    {
        .previousButton.enable(.pdfView.pageIndex > 0)
        .nextButton.enable(.pdfView.pageIndex + 1 < .pdfView.pageCount())
        .pageLabel.setText(Format.toString("% / %", .pdfView.pageIndex + 1, .pdfView.pageCount()))
    }

    func create(contentParent, commandParent: *Wnd, fileName: string, reportFailure: #null ViewerReportFailure = null)->*PdfPluginView fail
    {
        let result = Wnd.create'PdfPluginView(contentParent, "sFileScope.pdf")
        result.backgroundStyle = .View
        result.reportFailure   = reportFailure

        with result.commands = Wnd.create'Wnd(commandParent, {0, 0, PdfCommandWidth, 36})
        {
            .backgroundStyle = .Window
        }

        var complete: bool
        defer if !complete
        {
            result.commands.destroy()
            result.destroy()
        }

        with result.previousButton = IconButton.create(result.commands, result.theme().icon(.ChevronLeft, 18), {0, 0, 36, 36})
        {
            .dockStyle  = .Left
            .toolTip    = pdfStrings().ui_Previous
            .sigPressed += func|view = result|(button)
            {
                discard button
                view.pdfView.previousPage()
            }
        }

        with result.nextButton = IconButton.create(result.commands, result.theme().icon(.ChevronRight, 18), {0, 0, 36, 36})
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

        with let fit = PushButton.create(result.commands, pdfStrings().ui_Fit, {0, 0, 58, 36})
        {
            .dockStyle  = .Left
            .margin.x   = 8
            .sigPressed += func|view = result|(button)
            {
                discard button
                view.pdfView.zoomToFit()
            }
        }

        with let actual = PushButton.create(result.commands, pdfStrings().ui_Actual, {0, 0, 58, 36})
        {
            .dockStyle  = .Left
            .margin.x   = 8
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

        try result.pdfView.open(fileName)

        let count = result.pdfView.pageCount()
        result.details = Format.toString("PDF · % %", count, count == 1 ? pdfStrings().ui_Page : pdfStrings().ui_Pages)
        result.applyLayout()
        result.refreshNavigation()
        result.setInitialFocus(result.pdfView)
        complete = true
        return result
    }
}

private func createPdfPluginView(contentParent, commandParent: *Wnd, fileName: string, reportFailure: #null ViewerReportFailure, view: *#null *PdfPluginView) fail
{
    view[] = try PdfPluginView.create(contentParent, commandParent, fileName, reportFailure)
}

// Creates the PDF view exported through the sFileScope plugin ABI.
func sFileScopePluginCreate(request: const *ViewerRequest, result: *ViewerResult)->bool
{
    if request.apiVersion != ViewerPluginApiVersion do
        return false
    registerPdfStrings(request.contentParent.app())
    var view: #null *PdfPluginView
    catch createPdfPluginView(request.contentParent, request.commandParent, request.fileName, request.reportFailure, &view) as decodeError
    if decodeError != null
    {
        result.failureReason = Errors.message(decodeError)
        return true
    }

    result.view     = view
    result.commands = view!.commands
    result.details  = view!.details

    // PDF text lives compressed inside the file, so the host's raw byte scan would never find
    // it: the viewer owns the search, walking pages and revealing what it finds.
    result.findText = func(wnd, text)->bool { return (cast(*PdfPluginView) wnd).pdfView.findText(text) }
    return true
}
