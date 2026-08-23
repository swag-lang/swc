#global internal

using Core, Pixel, Gui

private const PdfCommandWidth = 336.0

internal struct PdfViewer
{
    using wnd:     Wnd
    details:       String
    reportFailure: #null ViewerReportFailure

    #[Swag.Late]
    {
        commands:       *ViewerCommandBar
        pdfView:        *PdfView
        previousButton: *IconButton
        nextButton:     *IconButton
        pageLabel:      *Label
    }
}

private impl IWnd for PdfViewer
{
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
    mtd refreshNavigation()
    {
        .previousButton.enable(.pdfView.pageIndex > 0)
        .nextButton.enable(.pdfView.pageIndex + 1 < .pdfView.pageCount())
        .pageLabel.setText(Format.toString("% / %", .pdfView.pageIndex + 1, .pdfView.pageCount()))
    }

    func create(contentParent, commandParent: *Wnd, fileName: string, reportFailure: #null ViewerReportFailure = null)->*PdfViewer fail
    {
        let result = Wnd.create'PdfViewer(contentParent, "sFileScope.pdf")
        result.backgroundStyle = .View
        result.reportFailure   = reportFailure

        result.commands = ViewerCommandBar.create(commandParent, PdfCommandWidth)

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

        with let zoomOut = IconButton.create(result.commands, result.theme().icon(.ZoomOut, 18), {0, 0, 36, 36})
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

        with let zoomIn = IconButton.create(result.commands, result.theme().icon(.ZoomIn, 18), {0, 0, 36, 36})
        {
            .dockStyle  = .Left
            .toolTip    = pdfStrings().ui_ZoomIn
            .sigPressed += func|view = result|(button)
            {
                discard button
                view.pdfView.zoomIn()
            }
        }

        with let fit = IconButton.create(result.commands, result.commands.icon(.FitView, 18), {0, 0, 36, 36})
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

        with let actual = IconButton.create(result.commands, result.commands.icon(.ActualSize, 18), {0, 0, 36, 36})
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

private func loadPdfViewer(contentParent, commandParent: *Wnd, fileName: string, reportFailure: #null ViewerReportFailure)->#null *PdfViewer fail => try PdfViewer.create(contentParent, commandParent, fileName, reportFailure)

// Creates the integrated PDF view.
func createPdfViewer(request: const *ViewerRequest, result: *ViewerResult)
{
    registerPdfStrings(request.contentParent.app())
    let view = catch loadPdfViewer(request.contentParent, request.commandParent, request.fileName, request.reportFailure) as decodeError
    if decodeError != null
    {
        result.failureReason = Errors.message(decodeError)
        return
    }

    result.view     = view
    result.commands = view!.commands
    result.details  = view!.details

    // PDF text lives compressed inside the file, so the host's raw byte scan would never find
    // it: the viewer owns the search, walking pages and revealing what it finds.
    result.findText = func(wnd, text)->bool { return (cast(*PdfViewer) wnd).pdfView.findText(text) }
}
