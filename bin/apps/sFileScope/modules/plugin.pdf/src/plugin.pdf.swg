#global public

using Core, Pdf, Pixel, Gui

private const PdfCommandWidth = 292.0
private const PdfRenderScale = 96.0 / 72.0     // PDF points to desktop pixels at 100%.

internal struct PdfPluginView
{
    using wnd:     Wnd
    document:      Document
    pageIndex:     u64
    details:       String
    reportFailure: #null ViewerReportFailure

    #[Swag.Late]
    {
        commands:       *Wnd
        imageView:      *ImageView
        previousButton: *IconButton
        nextButton:     *IconButton
        pageLabel:      *Label
    }
}

private impl PdfPluginView
{
    mtd refreshNavigation()
    {
        .previousButton.enable(.pageIndex > 0)
        .nextButton.enable(.pageIndex + 1 < .document.pages.count)
        .pageLabel.setText(Format.toString("% / %", .pageIndex + 1, .document.pages.count))
    }

    mtd showPage(index: u64) fail
    {
        if index >= .document.pages.count do
            return
        let image = try .document.pages[index].render({scale: PdfRenderScale, maxDimension: 8192})
        .pageIndex = index
        .imageView.setImage(image)
        .imageView.show()
        .imageView.zoomToFit()
        .refreshNavigation()
    }

    mtd showPageOrReport(index: u64)
    {
        catch .showPage(index) as renderError
        if renderError != null and .reportFailure do
            .reportFailure!(me, Errors.message(renderError))
    }

    func create(contentParent, commandParent: *Wnd, fileName: string, reportFailure: #null ViewerReportFailure = null)->*PdfPluginView fail
    {
        var document = try Document.load(fileName)
        if !document.pages.count do
            fail Errors.InvalidFormatError{"PDF document contains no page"}
        let firstPage = try document.pages[0].render({scale: PdfRenderScale, maxDimension: 8192})

        let result = Wnd.create'PdfPluginView(contentParent, "sFileScope.pdf")
        result.backgroundStyle = .View
        result.reportFailure   = reportFailure

        with result.commands = Wnd.create'Wnd(commandParent, {0, 0, PdfCommandWidth, 36})
        {
            .backgroundStyle = .Window
        }

        with result.previousButton = IconButton.create(result.commands, result.theme().icon(.ChevronLeft, 18), {0, 0, 36, 36})
        {
            .dockStyle  = .Left
            .toolTip    = pdfStrings().ui_Previous
            .sigPressed += func|view = result|(button)
            {
                discard button
                if view.pageIndex do
                    view.showPageOrReport(view.pageIndex - 1)
            }
        }

        with result.nextButton = IconButton.create(result.commands, result.theme().icon(.ChevronRight, 18), {0, 0, 36, 36})
        {
            .dockStyle  = .Left
            .toolTip    = pdfStrings().ui_Next
            .sigPressed += func|view = result|(button)
            {
                discard button
                if view.pageIndex + 1 < view.document.pages.count do
                    view.showPageOrReport(view.pageIndex + 1)
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
                view.imageView.zoomToFit()
            }
        }

        with let actual = PushButton.create(result.commands, pdfStrings().ui_Actual, {0, 0, 58, 36})
        {
            .dockStyle  = .Left
            .margin.x   = 8
            .sigPressed += func|view = result|(button)
            {
                discard button
                view.imageView.actualSize()
            }
        }

        result.imageView           = ImageView.create(result)
        result.imageView.dockStyle = .Center
        result.imageView.setImage(firstPage)

        result.document = #move document
        let count = result.document.pages.count
        result.details = Format.toString("PDF · % %", count, count == 1 ? pdfStrings().ui_Page : pdfStrings().ui_Pages)
        result.refreshNavigation()

        result.applyLayout()
        result.setInitialFocus(result.imageView)
        return result
    }
}

private impl IWnd for PdfPluginView
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
        case .Left, .PageUp:
            if .pageIndex do
                .showPageOrReport(.pageIndex - 1)

        case .Right, .PageDown:
            if .pageIndex + 1 < .document.pages.count do
                .showPageOrReport(.pageIndex + 1)

        case .Home:
            .showPageOrReport(0)

        case .End:
            if .document.pages.count do
                .showPageOrReport(.document.pages.count - 1)

        case .D0 where evt.modifiers.has(.Control):
            .imageView.actualSize()

        case .F:
            .imageView.zoomToFit()

        default:
            evt.accepted = false
        }
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
    return true
}
