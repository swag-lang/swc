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

// A small, independent render window used by the page rail. Images are capped by both
// the number of pages requested and the pixel budget in loadThumbnailBatch.
struct ThumbnailBatch
{
    first:  u64
    images: Array'Image
}

private const ThumbnailSide      = 192'u32
private const PageExportDpi       = 300'u32
private const MaxExportPages      = 50'u64

struct PageRange
{
    first: u64
    last:  u64
}

// Parses an inclusive one-based range such as `3-7`, refusing reversed, out-of-document, or
// oversized selections before any destination is touched.
func parsePageRange(source: string, pageCount: u64, result: *PageRange)->bool
{
    let text = Latin1.trim(source)
    let dash = Utf8.indexOf(text, '-'rune)
    if dash == Swag.U64.Max or not dash or dash + 1 >= text.count do
        return false
    let firstText = Latin1.trim(text[0 until dash])
    let lastText  = Latin1.trim(text[dash + 1 to])
    var firstResult: #decltype(expect StrConv.parseU64(firstText))
    var lastResult:  #decltype(expect StrConv.parseU64(lastText))
    var firstError:  Swag.Error
    var lastError:   Swag.Error
    catch { firstResult = try StrConv.parseU64(firstText) } as firstError
    catch { lastResult = try StrConv.parseU64(lastText) } as lastError
    if firstError.value() != null or
       lastError.value() != null or
       firstResult.eat != firstText.count or
       lastResult.eat != lastText.count or
       firstResult.ovf or
       lastResult.ovf or
       not firstResult.value or
       lastResult.value < firstResult.value or
       lastResult.value > pageCount or
       lastResult.value - firstResult.value + 1 > MaxExportPages do
        return false
    result.first = firstResult.value - 1
    result.last  = lastResult.value - 1
    return true
}

// Uses the PDF page renderer at a fixed, explicit print resolution rather than capturing the
// scaled viewer widget. The raster budget bounds unusually large authored page boxes.
func renderPageAtDpi(fileName: string, index: u64, dpi: u32)->Image fail
{
    if dpi < 36 or dpi > 1200 do
        fail Errors.UnsupportedFormatError{"PDF export DPI is outside the supported range"}
    var reader = try Pdf.Reader.open(fileName)
    if index >= reader.pageCount() do
        fail Errors.InvalidFormatError{texts().err_NoPage}
    let page  = try reader.loadPage(index)
    let scale = cast(f32, dpi) / 72
    return try page.render({scale: scale, maxDimension: 16_384, maxPixels: 64 * 1024 * 1024})
}

private func writePageImage(image: const *Image, target: string, refuseExisting = false) fail
{
    if refuseExisting and File.exists(target) do
        fail Errors.InvalidFormatError{texts().ui_ExportExists}
    let folder    = Path.directoryName(target) orelse "."
    let temporary = Path.combine(folder, Format.toString(".swag-pdf-%.tmp.png", Guid128.random()))
    defer discard catch File.delete(temporary)
    let encoded = try image.encode(temporary)
    try File.writeAllBytes(temporary, encoded)
    try File.move(target, temporary)
}

// Writes a rendered page through a temporary PNG and replaces the destination only on success.
func savePagePng(fileName, target: string, index: u64, dpi: u32 = PageExportDpi)->String fail
{
    let image = try renderPageAtDpi(fileName, index, dpi)
    try writePageImage(&image, target)
    return String.from(target)
}

func pageRangeFileName(folder, stem: string, index: u64)->String
    => Path.combine(folder, Format.toString("%-page-%.png", stem, index + 1))

// Renders the selected bounded range sequentially, retaining only one full-resolution page at a
// time. Existing outputs are rejected up front so a partial overwrite cannot destroy older work.
func savePageRange(fileName, folder, stem: string, first, last: u64, dpi: u32)->String fail
{
    if dpi < 36 or dpi > 1200 or first > last or last - first + 1 > MaxExportPages do
        fail Errors.InvalidFormatError{texts().ui_InvalidExportRange}
    var reader = try Pdf.Reader.open(fileName)
    if last >= reader.pageCount() do
        fail Errors.InvalidFormatError{texts().ui_InvalidExportRange}
    for index in first until last + 1
    {
        let target = pageRangeFileName(folder, stem, index)
        if File.exists(target) do
            fail Errors.InvalidFormatError{texts().ui_ExportExists}
    }

    for index in first until last + 1
    {
        if Swag.isCancelled() do
            return ""
        let page  = try reader.loadPage(index)
        let image = try page.render({scale: cast(f32, dpi) / 72, maxDimension: 16_384, maxPixels: 64 * 1024 * 1024})
        try writePageImage(&image, pageRangeFileName(folder, stem, index), refuseExisting: true)
    }

    return Format.toString("%–% · % DPI", first + 1, last + 1, dpi)
}

private func loadThumbnailBatch(fileName: string, first, end: u64)->ThumbnailBatch
{
    var result: #returntype
    result.first = first
    result.images.resize(end - first)
    var reader = catch Pdf.Reader.open(fileName) orelse Pdf.Reader{}
    for index in first until Math.min(end, reader.pageCount())
    {
        if Swag.isCancelled() do
            break
        let page = catch reader.loadPage(index) orelse Pdf.Page{}

        if page.width <= 0 or page.height <= 0 do
            continue

        // The rasterizer rounds point dimensions upward.
        let side  = cast(f32, ThumbnailSide - 2)
        let scale = side / Math.max(page.width, page.height, 1)
        result.images[index - first] = catch page.render({scale: scale,
                                                         maxDimension: cast(s32, ThumbnailSide),
                                                         maxPixels: cast(u64, ThumbnailSide) * ThumbnailSide}) orelse Image{}
    }

    return result
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
        .pageSize  = catch result.reader.pageSize(0) orelse {}
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
    using wnd:        Wnd
    details:          String
    facts:            DocumentFacts
    services:         Viewer.HostServices
    load:             Viewer.BackgroundLoad'ViewerContent
    failureReason:    String
    outline:          *DocumentOutline?
    bookmarks:        Array'Pdf.OutlineEntry
    pageLabels:       Array'String     // Labels the document gives its pages, one per page, or empty.
    history:          Viewer.History'PdfReadingPosition
    fileName:         String
    thumbnailTask:    Swag.Task'ThumbnailBatch
    pageExportTask:   Swag.Task'String
    pageExporting:    bool
    pageExportPath:   String
    pageExportFolder: String
    pageExportStem:   String
    pageExportFirst:  u64
    pageExportLast:   u64
    pageExportDpi:    u32 = PageExportDpi
    pageExportRange:  bool
    pageExportToast:  *Toast?
    previewTextures:  Array'Texture
    thumbnailStart:   u64
    using navigation: DocumentPageNavigation

    using steps: Viewer.PageSteps

    late
    {
        commands:         *Wnd
        info:             *Wnd
        pdfView:          *PdfView
        exportPageButton: *IconButton
        pageLabel:        *IconButton
        zoomLabel:        *IconButton
    }
}

private impl IWnd for Panel
{
    mtd impl onDestroyEvent(_: *DestroyEvent)
    {
        .clearThumbnails()
    }

    mtd impl onNotifyEvent(evt: *NotifyEvent)
    {
        if evt.kind == .LanguageChanged
        {
            .previousButton.toolTip   = appStrings().ui_PreviousPage
            .nextButton.toolTip       = appStrings().ui_NextPage
            .zoomLabel.toolTip        = texts().ui_ZoomMenu
            .exportPageButton.toolTip = texts().ui_ExportPageShort
            .translateNavigation(texts().ui_Thumbnails, texts().ui_Bookmarks)
            .refreshNavigation()
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
        if evt.task == &.pageExportTask
        {
            .pageExportTask.waitSubmission(evt.submission)
            if evt.submission != .pageExportTask.currentSubmission() or not .pageExportTask.isDone() do
                return
            .finishPageExport()
            return
        }

        if evt.task == &.thumbnailTask
        {
            .thumbnailTask.waitSubmission(evt.submission)
            if evt.submission != .thumbnailTask.currentSubmission() or not .thumbnailTask.isDone() do
                return
            var loadErrorOutcome: Swag.Error
            var batch: ThumbnailBatch
            catch { batch = try .thumbnailTask.take() } as loadErrorOutcome
            let loadError = loadErrorOutcome.value()
            if loadError == null do
                .installThumbnails(&batch)
            return
        }

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
        if .pageExportTask.isPending()
        {
            .pageExportTask.cancel()
            if not .pageExportTask.isDone() do
                return false
            discard catch .pageExportTask.take()
        }

        if .thumbnailTask.isPending()
        {
            .thumbnailTask.cancel()
            if not .thumbnailTask.isDone() do
                return false
            discard catch .thumbnailTask.take()
        }

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
        if .steps.updateSteps(.pdfView.pageIndex, .pdfView.pageCount()) do
            .services.chromeChanged(me)
        .exportPageButton.enable(.pdfView.pageCount() > 0 and not .pageExporting)
        .pageLabel.setText(.pageReadout())
        .navigation.pageCount   = .pdfView.pageCount()
        .navigation.currentPage = .pdfView.pageIndex
        if .gallery != null and .thumbnailScroll.isVisible() do
            .gallery.revealCurrentPage()
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
        .setNavigationMode(.bookmarks.isEmpty())
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
        entries.add(strings.ui_Previous, .ChevronLeft, func|view = me|() { view.pdfView.previousPage() }, disabled: not .previousButton.isEnabled(), defaultKey: {modifiers: .Control, key: .PageUp}, bindId: "scope.pdf.previous")
        entries.add(strings.ui_Next, .ChevronRight, func|view = me|() { view.pdfView.nextPage() }, disabled: not .nextButton.isEnabled(), defaultKey: {modifiers: .Control, key: .PageDown}, bindId: "scope.pdf.next")
        entries.add(strings.ui_ShowPages, .Grid, func|view = me|() { view.openPages() }, disabled: not .pdfView.pageCount(), bindId: "scope.pdf.thumbnails")
        .steps.addPageJump(entries, "scope.pdf.goToPage")
        entries.add(strings.ui_ExportPage, .SaveAs, func|view = me|() { view.promptExportPage() }, disabled: not .pdfView.pageCount() or .pageExporting, bindId: "scope.pdf.exportPage")
        entries.add(strings.ui_ExportRange, .Export, func|view = me|() { view.promptExportRange() }, disabled: not .pdfView.pageCount() or .pageExporting, bindId: "scope.pdf.exportRange")
        entries.add(strings.ui_Back, .ChevronLeft, func|view = me|() { view.goBack() }, disabled: not .history.canGoBack(), defaultKey: {modifiers: .Alt, key: .Left}, bindId: "scope.pdf.back")
        entries.add(strings.ui_Forward, .ChevronRight, func|view = me|() { view.goForward() }, disabled: not .history.canGoForward(), defaultKey: {modifiers: .Alt, key: .Right}, bindId: "scope.pdf.forward")

        // The page view zooms by factors, far past the shared bounds, so only actual size, the
        // 100 % of the readout, is the shared row; it reads as chosen while the pages show at it.
        // The steps read as unavailable at the page view's own limits.
        entries.add(appStrings().cmd_ZoomIn, .ZoomIn, func|view = me|() { view.pdfView.zoomIn() }, disabled: not .pdfView.canZoomIn(), defaultKey: {modifiers: .Control, key: .OemPlus}, bindId: "scope.pdf.zoomIn")
        entries.add(appStrings().cmd_ZoomOut, .ZoomOut, func|view = me|() { view.pdfView.zoomOut() }, disabled: not .pdfView.canZoomOut(), defaultKey: {modifiers: .Control, key: .OemMinus}, bindId: "scope.pdf.zoomOut")
        entries.addZoom(.Reset, .zoomPercent(), func|view = me|() { view.pdfView.actualSize() })
        entries.add(strings.ui_Fit, .FitView, func|view = me|() { view.pdfView.zoomToFit() }, checked: .pdfView.zoomMode == .FitPage, defaultKey: {modifiers: .None, key: .F}, bindId: "scope.pdf.fit")
        entries.add(strings.ui_FitWidth, .FitWidth, func|view = me|() { view.pdfView.zoomToFitWidth() }, checked: .pdfView.zoomMode == .FitWidth, defaultKey: {modifiers: .None, key: .W}, bindId: "scope.pdf.fitWidth")
        entries.add(strings.ui_Continuous, .Outline, func|view = me|() { view.pdfView.setPageLayout(.Continuous) }, checked: .pdfView.pageLayout == .Continuous, bindId: "scope.pdf.layoutContinuous")
        entries.add(strings.ui_SinglePage, .File, func|view = me|() { view.pdfView.setPageLayout(.Single) }, checked: .pdfView.pageLayout == .Single, bindId: "scope.pdf.layoutSingle")
        entries.add(appStrings().cmd_ZoomMenu, .ZoomLevels, func|view = me|() { view.showZoomMenu() }, bindId: "scope.pdf.zoomMenu")

        // The commands of the page's context menu, so none of them needs a right click.
        entries.add(strings.ui_CopyText, .Copy, func|view = me|() { discard view.pdfView.copySelection() }, disabled: not .pdfView.hasSelection(), defaultKey: {modifiers: .Control, key: .C}, bindId: "scope.pdf.copyText")
        entries.add(strings.ui_SelectPage, .SelectAll, func|view = me|() { view.pdfView.selectAll() }, disabled: not .pdfView.pageCount(), defaultKey: {modifiers: .Control, key: .A}, bindId: "scope.pdf.selectPage")
    }

    mtd promptExportPage()
    {
        let surface = .surface
        if not surface or not .pdfView.pageCount() or .pageExporting do
            return

        let pageIndex = .pdfView.pageIndex
        let dpi       = .chooseExportDpi()
        if not dpi do
            return
        let stem = Path.fileNameWithoutExtension(.fileName) orelse .fileName.toString()
        let suggestedName = Format.toString("%-page-%-%.png", stem, pageIndex + 1, dpi)
        var options: FileDlgOptions
        options.mode          = .CreateFile
        options.title         = texts().ui_ExportPage
        options.initialFolder = Path.directoryName(.fileName) orelse ""
        options.initialName   = suggestedName.toString()
        options.filters.add({texts().ui_ExportPageType, ".png"})
        let dialog = FileDlg.create(surface, options)
        if dialog.doModal() == Dialog.BtnOk
        {
            let target = String.from(dialog.selectedPath())
            .startPageExport(pageIndex, target.toString(), dpi)
        }
    }

    mtd promptExportRange()
    {
        let surface = .surface
        if not surface or not .pdfView.pageCount() or .pageExporting do
            return
        let defaultRange = Format.toString("1-%", .pdfView.pageCount())
        var options: EditDlgOptions
        options.title   = texts().ui_ExportRangeTitle
        options.message = texts().ui_ExportRangePrompt
        options.text    = defaultRange.toString()
        let dialog = EditDlg.createSingleLine(surface, options)
        if dialog.doModal() != Dialog.BtnOk do
            return
        var range: PageRange
        if not parsePageRange(dialog.text(), .pdfView.pageCount(), &range)
        {
            .showExportNotice(texts().ui_InvalidExportRange, .Failure)
            return
        }

        let dpi = .chooseExportDpi()
        if not dpi do
            return
        var folderOptions: FileDlgOptions
        folderOptions.mode          = .SelectFolder
        folderOptions.title         = texts().ui_SelectExportFolder
        folderOptions.initialFolder = Path.directoryName(.fileName) orelse ""
        let folderDialog = FileDlg.create(surface, folderOptions)
        if folderDialog.doModal() != Dialog.BtnOk do
            return
        let folder = String.from(folderDialog.selectedPath())
        let stem   = Path.fileNameWithoutExtension(.fileName) orelse .fileName.toString()
        .startPageRangeExport(range, folder.toString(), stem, dpi)
    }

    mtd chooseExportDpi()->u32
    {
        let menu = MenuCtrl.createPopup(me, owner: me)
        menu.addItem(texts().ui_ExportDpi150, "scope.pdf.exportDpi150", .theme().icon(.SaveAs, themeRowIconSize(.themeMetrics())))
        menu.addItem(texts().ui_ExportDpi300, "scope.pdf.exportDpi300", .theme().icon(.SaveAs, themeRowIconSize(.themeMetrics())), checked: true)
        menu.addItem(texts().ui_ExportDpi600, "scope.pdf.exportDpi600", .theme().icon(.SaveAs, themeRowIconSize(.themeMetrics())))
        switch menu.doModal(.exportPageButton, autoDestroy: true) orelse ""
        {
        case "scope.pdf.exportDpi150": return 150
        case "scope.pdf.exportDpi300": return 300
        case "scope.pdf.exportDpi600": return 600
        }

        return 0
    }

    mtd showExportMenu()
    {
        if .pageExporting do
            return
        let menu = MenuCtrl.createPopup(me, owner: me)
        menu.addItem(texts().ui_ExportPage, "scope.pdf.exportCurrent", .theme().icon(.SaveAs, themeRowIconSize(.themeMetrics())))
        menu.addItem(texts().ui_ExportRange, "scope.pdf.exportRange", .theme().icon(.Export, themeRowIconSize(.themeMetrics())))
        switch menu.doModal(.exportPageButton, autoDestroy: true) orelse ""
        {
        case "scope.pdf.exportCurrent": .promptExportPage()
        case "scope.pdf.exportRange":   .promptExportRange()
        }
    }

    mtd showExportNotice(message: string, tone: ToastTone)
    {
        if not .pageExportToast do
            .pageExportToast = Toast.create(me)
        .pageExportToast.show(message, "", tone)
    }

    internal mtd startPageExport(index: u64, target: string, dpi: u32 = PageExportDpi)
    {
        if .pageExporting or index >= .pdfView.pageCount() do
            return
        .pageExporting   = true
        .pageExportRange = false
        .pageExportPath  = String.from(target)
        .pageExportDpi   = dpi
        .exportPageButton.enable(false)
        .pageExportTask.submit(func|view = me, index|()->String fail => try savePagePng(view.fileName.toString(), view.pageExportPath.toString(), index, view.pageExportDpi), me.taskNotifier(&.pageExportTask))
    }

    internal mtd startPageRangeExport(range: PageRange, folder, stem: string, dpi: u32)
    {
        if .pageExporting or
           range.first > range.last or
           range.last >= .pdfView.pageCount() or
           range.last - range.first + 1 > MaxExportPages do
            return
        .pageExporting    = true
        .pageExportRange  = true
        .pageExportFolder = String.from(folder)
        .pageExportStem   = String.from(stem)
        .pageExportFirst  = range.first
        .pageExportLast   = range.last
        .pageExportDpi    = dpi
        .exportPageButton.enable(false)
        .pageExportTask.submit(func|view = me|()->String fail => try savePageRange(view.fileName.toString(), view.pageExportFolder.toString(), view.pageExportStem.toString(), view.pageExportFirst, view.pageExportLast, view.pageExportDpi), me.taskNotifier(&.pageExportTask))
    }

    internal mtd finishPageExport()
    {
        if not .pageExporting or not .pageExportTask.isDone() do
            return
        .pageExporting = false
        var saved:       String
        var exportError: Swag.Error
        catch { saved = try .pageExportTask.take() } as exportError
        let failure = exportError.value()
        if failure != null
        {
            if not Swag.isCancelled()
            {
                if not .pageExportToast do
                    .pageExportToast = Toast.create(me)
                .pageExportToast.show(texts().ui_ExportPageFailed, Viewer.failureText(failure), .Failure)
            }
        }
        else
        {
            if not .pageExportToast do
                .pageExportToast = Toast.create(me)
            if .pageExportRange do
                .pageExportToast.show(texts().ui_ExportRangeSaved, saved, .Done)
            else do
                .pageExportToast.show(texts().ui_ExportPageSaved, Path.fileName(saved) orelse saved.toString(), .Done)
        }

        .pageExportRange = false
        .refreshNavigation()
    }

    // Offers the zoom presets, fit to page or width, and the continuous or single-page layout, with
    // the level in use, the fit and the layout checked. A page is read near its actual size, so the
    // levels stay around 100 % as the text viewers' do rather than reaching down as a picture's do.
    mtd showZoomMenu()
    {
        let menu    = MenuCtrl.createPopup(me, owner: me)
        let percent = .zoomPercent()
        menu.addItem("50 %", "scope.pdf.zoom50", checked: percent == 50)
        menu.addItem("100 %", "scope.pdf.zoomActual", checked: percent == 100)
        menu.addItem("125 %", "scope.pdf.zoom125", checked: percent == 125)
        menu.addItem("150 %", "scope.pdf.zoom150", checked: percent == 150)
        menu.addItem("200 %", "scope.pdf.zoom200", checked: percent == 200)
        menu.addSeparator()
        menu.addItem(texts().ui_Fit,
                     "scope.pdf.zoomFit",
                     .theme().icon(.FitView, themeRowIconSize(.themeMetrics())),
                     rightName: .keyShortcutName("scope.pdf.fit", "F"),
                     checked: .pdfView.zoomMode == .FitPage)
        menu.addItem(texts().ui_FitWidth,
                     "scope.pdf.zoomFitWidth",
                     .theme().icon(.FitWidth, themeRowIconSize(.themeMetrics())),
                     rightName: .keyShortcutName("scope.pdf.fitWidth", "W"),
                     checked: .pdfView.zoomMode == .FitWidth)
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
            .fileName        = String.from(fileName)
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
        let turn = func|view = me|(dir: s32)
        {
            if dir < 0 do
                view.pdfView.previousPage()
            else do
                view.pdfView.nextPage()
        }
        .pageLabel = .steps.create(.commands, "scope.pdf.page", .Page, turn, func|view = me|(index)
        {
            view.history.visit(view.pdfView.readingPosition())
            view.pdfView.showPage(index)
        })
        .steps.labelAt = func|view = me|(index)->string
        {
            return view.pageLabelOf(index)
        }

        .steps.resolveLabel = func|view = me|(typed)->u64
        {
            for label, index in view.pageLabels where not label.isEmpty() and Utf8.compare(label.toString(), typed, .Latin1NoCase) == 0 do
                return index
            return Swag.U64.Max
        }

        with .exportPageButton = Viewer.createActionButton(.info, .SaveAs)
        {
            .dockStyle = .Left
            .toolTip   = texts().ui_ExportPageShort
            .enable(false)
            .sigPressed += func|view = me|(_) { view.showExportMenu() }
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
    let metrics  = host.contentParent().themeMetrics()
    let info     = host.createInfoGroup(Viewer.ZoomSlotWidth + themeActionButtonSize(metrics))
    let commands = host.createCommandGroup(Viewer.pageControlWidth(metrics))
    let view     = Panel.create(host.contentParent(), info, commands, host.fileName(), services)
    host.attachView(view)
    view.outline             = DocumentOutline.create(host)
    view.createPdfNavigation()
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
