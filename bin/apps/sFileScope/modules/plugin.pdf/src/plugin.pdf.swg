#global public

using Core, Pdf, Pixel, Gui

private const PdfCommandWidth = 292.0
private const PdfRenderScale = 96.0'f32 / 72.0     // PDF points to desktop pixels at 100%.
private const PdfMaxDimension = 8192

internal struct PdfPluginView
{
    using wnd:     Wnd
    reader:        Reader
    pageIndex:     u64
    pageSize:      Math.Point
    rasterScale:   f32
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
    mtd renderScale()->f32
    {
        let client       = .paddedClientRect()
        let fittedScale  = Math.min(client.width / .pageSize.x, client.height / .pageSize.y)
        let logicalScale = Math.max(PdfRenderScale, fittedScale)
        let maximumScale = cast(f32) (PdfMaxDimension - 1) / Math.max(.pageSize.x, .pageSize.y)
        return Math.min(logicalScale * .deviceScale(), maximumScale)
    }

    mtd actualSize()
    {
        .imageView.actualSize()
        .imageView.setZoom(PdfRenderScale / .rasterScale)
    }

    mtd refreshNavigation()
    {
        .previousButton.enable(.pageIndex > 0)
        .nextButton.enable(.pageIndex + 1 < .reader.pageCount())
        .pageLabel.setText(Format.toString("% / %", .pageIndex + 1, .reader.pageCount()))
    }

    mtd showPage(index: u64) fail
    {
        if index >= .reader.pageCount() do
            return
        var page  = try .reader.loadPage(index)
        .pageSize = {page.width, page.height}
        let scale = .renderScale()
        let image = try page.render({scale: scale, maxDimension: PdfMaxDimension})
        .pageIndex = index
        .rasterScale = scale
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
        var reader = try Reader.open(fileName)
        if !reader.pageCount() do
            fail Errors.InvalidFormatError{"PDF document contains no page"}
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
                if view.pageIndex + 1 < view.reader.pageCount() do
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
                view.actualSize()
            }
        }

        result.imageView           = ImageView.create(result)
        result.imageView.dockStyle = .Center

        result.reader = #move reader
        var complete: bool
        defer if !complete
        {
            result.commands.destroy()
            result.destroy()
        }

        let count = result.reader.pageCount()
        result.details = Format.toString("PDF · % %", count, count == 1 ? pdfStrings().ui_Page : pdfStrings().ui_Pages)
        result.applyLayout()
        try result.showPage(0)
        result.setInitialFocus(result.imageView)
        complete = true
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
            if .pageIndex + 1 < .reader.pageCount() do
                .showPageOrReport(.pageIndex + 1)

        case .Home:
            .showPageOrReport(0)

        case .End:
            if .reader.pageCount() do
                .showPageOrReport(.reader.pageCount() - 1)

        case .D0 where evt.modifiers.has(.Control):
            .actualSize()

        case .F:
            .imageView.zoomToFit()

        default:
            evt.accepted = false
        }
    }

    mtd impl onResizeEvent(evt: *ResizeEvent)
    {
        discard evt
        if !@isset(.imageView) or .pageSize.x <= 0 or !.imageView.isFitted do
            return

        // Keep fitted pages backed by roughly one source pixel per physical display pixel.
        // A margin avoids rerasterizing for every small step of an interactive resize.
        if .renderScale() > .rasterScale * 1.2 do
            .showPageOrReport(.pageIndex)
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
