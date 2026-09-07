#global public

using Core, Pixel

// Selects how [[Gui.PdfView.findTextMatches]] compares document text.
struct PdfTextSearchOptions
{
    public
    {
        comparison = Utf8.ComparisonType.Latin1NoCase     // Text comparison, case-insensitive by default.
        wholeWord:         bool                           // Whether word characters may touch either side of a match.
        regularExpression: bool                           // Whether the query uses regular-expression syntax.
    }
}

// Identifies one text match in a PDF document.
struct PdfTextMatch
{
    public
    {
        pageIndex:  u64     // Zero-based page containing the match.
        byteOffset: u64     // UTF-8 byte offset in that page's indexed text.
        byteLength: u64     // UTF-8 byte length of the match.
    }
}

// Selects how the pages of a document are laid out in the viewport.
enum PdfPageLayout
{
    Continuous     // Every page in one column, scrolled as a single document.
    Single         // One page at a time, the way a slide is shown.
}

// Selects what a page is scaled to when the viewport changes.
enum PdfZoomMode
{
    FitPage      // The whole page fits inside the viewport.
    FitWidth     // The page's width fits the viewport's width.
    Free         // The scale [[Gui.PdfView.setZoom]] set is kept, whatever the viewport does.
}

// One position in a document's text: a page, and a byte offset in that page's text.
//
// The type identity is part of the exported widget layout, so it is public, but it carries no
// public contract of its own.
#[Swag.NoDoc]
public struct PdfTextPosition
{
    pageIndex = Swag.U64.Max     // Zero-based page, or `Swag.U64.Max` when there is no position.
    offset: u64                  // UTF-8 byte offset in that page's indexed text.
}

impl PdfTextPosition
{
    // Reports whether this position names a place in a document.
    mtd const isValid()->bool => .pageIndex != Swag.U64.Max

    // Reports whether this position comes before `other` in reading order.
    mtd const isBefore(other: PdfTextPosition)->bool
    {
        if .pageIndex != other.pageIndex do
            return .pageIndex < other.pageIndex
        return .offset < other.offset
    }

    // Reports whether both positions name the same byte of the same page.
    mtd const opEquals(other: PdfTextPosition)->bool => .pageIndex == other.pageIndex and .offset == other.offset
}

// The surface a [[Gui.PdfView]] draws its pages on.
//
// The type identity is part of the exported widget layout, so it is public, but it carries no
// public contract of its own.
#[Swag.NoDoc]
public struct PdfCanvas
{
    using wnd: Wnd

    late owner: *PdfView
}

// Displays a PDF document the way a reader scrolls one: every page in one column, decoded as it
// comes into view.
//
// The document's page sizes are read from its page tree when it opens, so the whole column is
// laid out and scrollable before a single page is decoded. A page is then decoded on a worker as
// the viewport reaches it, and a small number of pages around the viewport stay decoded, so
// scrolling, turning a page, or revealing a search hit never decodes on the thread that draws.
// A page that has not arrived yet shows as the paper it will be, at the exact place and size it
// will occupy, so nothing moves under the reader when it lands.
//
// A page is vector art, and it is painted as such: every paint draws the decoded items straight
// through the widget's painter — the application renderer, not an offline rasterization — at the
// exact scale the page is shown at, zoom and monitor scale included. A zoom or scroll step is
// therefore a transform change, not a raster: a page's images are uploaded to the renderer once,
// its typefaces are resolved once, and path tessellations are cached inside the decoded page.
//
// The wheel scrolls the document, `Ctrl` and the wheel zoom around the pointer, dragging pans, a
// double click toggles between fitted and actual size, and the arrow, page, `Home` and `End` keys
// move through the document. [[Gui.PdfView.setPageLayout]] switches to one page at a time, and
// [[Gui.PdfView.zoomToFit]], [[Gui.PdfView.zoomToFitWidth]] and [[Gui.PdfView.actualSize]] select
// what a page is scaled to. Embedded actions, scripts, and forms are never executed.
//
// The document's text can be worked with: a drag over words selects them across page boundaries,
// a double click takes the word, `Ctrl+C` and the right-click menu copy the selection, and
// [[Gui.PdfView.findText]] searches the whole document and reveals what it finds. A search reads
// the document's text, which is extracted once per document on a worker, text alone and none of
// the images a page carries, so it never waits for the whole document to decode.
//
// ```swag
// let view = PdfView.create(parent)
// try view.open("document.pdf")
// view.zoomToFitWidth()
// ```
struct PdfView
{
    public
    {
        using wnd: Wnd     // Embedded window behavior and presentation.

        sigPageChanged: SigArray'func||(*PdfView)             // Emitted after the page the viewport shows changes.
        sigZoomChanged: SigArray'func||(*PdfView)             // Emitted after the effective zoom changes.
        sigRenderError: SigArray'func||(*PdfView, string)     // Emitted when a page cannot be decoded or painted.

        readonly
        {
            zoom:      f32 = 1                            // Requested logical units per PDF point in free zoom mode.
            zoomMode       = PdfZoomMode.FitPage          // What a page is scaled to when the viewport changes.
            pageLayout     = PdfPageLayout.Continuous     // How the document's pages are laid out.
            pageIndex: u64                                // Zero-based page the viewport shows.
        }
    }

        late
    {
        scroll: *ScrollWnd
        canvas: *PdfCanvas
    }

    // The document, and the geometry of every one of its pages read from the page tree. A page's
    // place in the column is one multiplication away from the cumulative heights, whatever the
    // scale, so laying the document out costs no decode.
    reader:      Pdf.Reader
    hasDocument: bool
    pageSizes:   Array'Math.Point
    pageStarts:  Array'f32
    widestPage:  f32
    tallestPage: f32

    // The decoded pages, and the worker that decodes them.
    cache: PdfPageCache

    // One failing page reports through `sigRenderError` once, not once per frame.
    reportedPaintError: bool

    // The scale `sigZoomChanged` last carried. A fitted document changes scale whenever the
    // viewport does, and a host showing the zoom has no other way to learn about it.
    reportedZoom: f32 = 1

    isPanning:   bool
    lastPointer: Math.Point

    // The reader's selection, as positions in the document's text. The anchor is where the press
    // landed and the caret follows the pointer, so either end may come first.
    selAnchor: PdfTextPosition
    selCaret:  PdfTextPosition
    selecting: bool

    // Where the running search resumes: the page and the offset just past the last hit.
    searchQuery:  String
    searchPage:   u64
    searchOffset: u64

    // A match to bring into view once the page carrying it has been decoded.
    pendingReveal: bool

    // The text of every page, extracted on a worker the first time a search asks for it and kept
    // until the document closes.
    documentText: Pdf.DocumentText

    // How finely one resident page's geometry is being raised, and the lock that keeps the worker
    // and a frame off that page at the same time.
    //
    // Drawing at a finer scale than a page holds flattens and triangulates the whole page inside
    // that frame, which on a page of a few thousand marks is what a reader enlarging a window
    // sees as the window stopping. The view keeps drawing at the scale the page already holds and
    // has a worker raise it one item at a time, so a frame waits at most for the item the worker
    // is on.
    prepareTask:    Swag.Task
    pageLock:       Sync.Mutex
    preparingPage:  *PdfResidentPage?
    preparingScale: f32
    prepareReady:   u32     // Set by the worker when the page holds `preparingScale`; read atomically.
    prepareCancel:  u32     // Asks the worker to stop after the shape it is on; read atomically.
    preparing:      bool

    // Publishes what the workers finish. It runs only while one of them owes the view a page.
    pollTimer: *Timer?
}

internal impl PdfView
{
    // One PDF point shown at actual size covers 96/72 logical units: a point is 1/72 inch and
    // a logical unit is 1/96 inch.
    const ActualSizeZoom = 96.0'f32 / 72.0

    // The size a page whose own boxes cannot be read is laid out at, in PDF points, when no page
    // before it gave a usable one: US Letter, which is what a reader expects of a page it is
    // shown nothing about.
    const DefaultPageWidth  = 612.0'f32
    const DefaultPageHeight = 792.0'f32

    // Returns the viewport the document is scrolled inside, in logical units.
    mtd const viewportSize()->Math.Point
    {
        let rect = .scroll.view!.clientRect()
        return {Math.max(rect.width, 1), Math.max(rect.height, 1)}
    }

    // Returns the size of the laid-out document, in logical units.
    mtd const contentSize()->Math.Point
    {
        if !.hasDocument do
            return {}

        let scale = .effectiveZoom()
        var result: retval
        if .pageLayout == .Single
        {
            let size = .pageSizes[.pageIndex]
            result.x = size.x * scale + 2 * PageMargin
            result.y = size.y * scale + 2 * PageMargin
            return result
        }

        let count = .pageSizes.count
        result.x = .widestPage * scale + 2 * PageMargin
        result.y = .pageStarts[count] * scale + cast(f32) (count - 1) * PageGap + 2 * PageMargin
        return result
    }

    // Returns where the top of one page sits in the laid-out document, in logical units.
    mtd const pageTop(index: u64)->f32
    {
        if .pageLayout == .Single do
            return PageMargin
        return PageMargin + .pageStarts[index] * .effectiveZoom() + cast(f32) index * PageGap
    }

    // Returns the rectangle one page occupies in the laid-out document, in logical units.
    mtd const pageRect(index: u64)->Math.Rectangle
    {
        let scale = .effectiveZoom()
        let size  = .pageSizes[index]

        var result: retval
        result.width  = size.x * scale
        result.height = size.y * scale
        result.x      = (.contentSize().x - result.width) * 0.5
        result.y      = .pageTop(index)
        return result
    }

    // Returns where the laid-out document starts inside the viewport, in canvas coordinates.
    //
    // A document narrower or shorter than the viewport is centred in it; anything larger starts
    // at the scroll position.
    mtd const documentOrigin()->Math.Point
    {
        let viewport = .viewportSize()
        let content  = .contentSize()
        let scroll   = .scroll.scrollPosition()
        return {Math.max((viewport.x - content.x) * 0.5, 0) - scroll.x, Math.max((viewport.y - content.y) * 0.5, 0) - scroll.y}
    }

    // Returns the band of the document the viewport shows, in document coordinates.
    mtd const visibleBand()->{ top: f32, bottom: f32 }
    {
        let origin = .documentOrigin()

        var result: retval
        result.top    = -origin.y
        result.bottom = result.top + .viewportSize().y
        return result
    }

    // Returns the page the document holds at vertical offset `y`, clamped to the document.
    mtd const pageAt(y: f32)->u64
    {
        if .pageLayout == .Single do
            return .pageIndex

        let count = .pageSizes.count
        if count <= 1 do
            return 0

        // The tops are increasing, so the page shown at an offset is the last one starting at or
        // before it. A document of a few thousand pages is scrolled every frame, and walking it
        // is the kind of cost that only shows up on the documents that need it most.
        var low  = 0'u64
        var high = count - 1
        while low < high
        {
            let mid = (low + high + 1) / 2
            if .pageTop(mid) <= y do
                low = mid
            else do
                high = mid - 1
        }

        return low
    }

    // Returns the pages the viewport currently reaches, both ends included.
    mtd const visibleRange()->{ first: u64, last: u64 }
    {
        var result: retval
        if !.hasDocument or .pageLayout == .Single
        {
            result.first = .pageIndex
            result.last  = .pageIndex
            return result
        }

        let band = .visibleBand()
        result.first = .pageAt(band.top)
        result.last  = .pageAt(band.bottom)
        return result
    }

    // Returns the page under a canvas point, and where in that page the point lands, in points.
    mtd const documentPointAt(local: Math.Point)->{ pageIndex: u64, point: Math.Point }
    {
        let origin = .documentOrigin()
        let scale  = .effectiveZoom()

        var result: retval
        result.pageIndex = .pageAt(local.y - origin.y)
        let rect = .pageRect(result.pageIndex)
        result.point = {(local.x - origin.x - rect.x) / scale, (local.y - origin.y - rect.y) / scale}
        return result
    }

    // Scrolls so that `content`, a point of the laid-out document, lands under `local`, a point
    // of the viewport.
    mtd scrollDocumentPointTo(content, local: Math.Point)
    {
        let viewport = .viewportSize()
        let size     = .contentSize()
        let offsetX  = Math.max((viewport.x - size.x) * 0.5, 0)
        let offsetY  = Math.max((viewport.y - size.y) * 0.5, 0)
        .scroll.setScrollPos(offsetX + content.x - local.x, offsetY + content.y - local.y)
    }

    // Returns the flattening the pages shown at the current scale are built for.
    mtd const flattenScale()->f32 => Painter.quantizeFlattenScale(.effectiveZoom() * .deviceScale())

    mtd applyZoom(value: f32, anchor: const *Math.Point? = null)
    {
        // The document point under the pointer is what the reader is zooming around, and the
        // laid-out column is not a uniform scaling of itself — its gaps and margins do not grow —
        // so the anchor is kept as a place on a page rather than as a content coordinate.
        var anchorPage  = 0'u64
        var anchorPoint = Math.Point{}
        if anchor
        {
            let hit = .documentPointAt(anchor[])
            anchorPage  = hit.pageIndex
            anchorPoint = hit.point
        }

        .zoomMode = .Free
        .zoom     = Math.clamp(value, MinZoom, MaxZoom)
        .placeDocument()

        if anchor
        {
            let rect  = .pageRect(anchorPage)
            let scale = .effectiveZoom()
            .scrollDocumentPointTo({rect.x + anchorPoint.x * scale, rect.y + anchorPoint.y * scale}, anchor[])
        }

        .updateCurrentPage()
        .publishZoom()
        .invalidate()
    }

    // Recomputes the page the viewport shows, and reports it when it changed.
    mtd updateCurrentPage()
    {
        if !.hasDocument or .pageLayout == .Single do
            return

        // The page a reader is on is the one under the middle of the viewport: the page at the
        // top would change on the first pixel of the next one, before the reader is reading it.
        let band  = .visibleBand()
        let index = .pageAt((band.top + band.bottom) * 0.5)
        if index == .pageIndex do
            return

        .pageIndex = index
        .sigPageChanged.call(me)
    }

    // Reads the geometry of every page from the document.
    //
    // This is what makes the whole document scrollable before anything is decoded: the page tree
    // carries each page's boxes and rotation, and that is all a column of pages needs.
    mtd buildLayout()
    {
        .pageSizes.clear()
        .pageStarts.clear()
        .widestPage  = 0
        .tallestPage = 0
        .pageStarts.add(0)

        var total = 0.0'f32
        var last  = Math.Point{DefaultPageWidth, DefaultPageHeight}
        for index in .reader.pageCount()
        {
            // A page whose own boxes cannot be read still holds its place in the column: the
            // reader is given the size of the page before it rather than a collapsed row that
            // cannot be scrolled onto.
            var size = catch .reader.pageSize(index) as sizeError
            if sizeError != null or size.x <= 0 or size.y <= 0 or !Math.isFinite(size.x) or !Math.isFinite(size.y) do
                size = last

            last = size
            .pageSizes.add(size)
            .widestPage  = Math.max(.widestPage, size.x)
            .tallestPage = Math.max(.tallestPage, size.y)
            total        += size.y
            .pageStarts.add(total)
        }
    }

    // Publishes the document the view is about to show and starts it at its first page.
    mtd adoptDocument(reader: *Pdf.Reader)
    {
        .close()
        swap(&.reader, reader)
        .hasDocument = true
        .buildLayout()
        .cache.open(.reader.fileName(), .app().renderer)
        .pageIndex          = 0
        .reportedPaintError = false
        .placeDocument()
        .scroll.setScrollPos(0, 0)
        .sigPageChanged.call(me)
        .publishZoom()
        .invalidate()
    }

    // Drops the selection and the search cursor a new document invalidates.
    mtd clearTextState()
    {
        .selAnchor     = {}
        .selCaret      = {}
        .selecting     = false
        .pendingReveal = false
    }

    // Reports whether a match is bounded by non-word characters on both sides.
    func isWholeWord(source: string, offset, length: u64)->bool
    {
        if offset
        {
            let {c, ?} = Utf8.decodeLastRune(source[0 until offset])
            if Unicode.isWord(c) do
                return false
        }

        let end = offset + length
        if end < source.count
        {
            let {c, ?} = Utf8.decodeRune(source[end to])
            if Unicode.isWord(c) do
                return false
        }

        return true
    }

    // Appends every non-overlapping match in one page's text, in text order.
    func appendPageMatches(result: *Array'PdfTextMatch, source: string, pageIndex: u64, text: string, options: PdfTextSearchOptions, expression: *Parser.RegExp?)
    {
        if expression
        {
            let sourceData = source.buffer
            for value in expression!.grepAll(source)
            {
                // A zero-width occurrence is meaningful to a parser, but there is no span on the
                // page to select or outline.
                if !value.count do
                    continue
                let found = cast(u64) cast(s64) (value.buffer - sourceData)
                if !options.wholeWord or isWholeWord(source, found, value.count) do
                    result.add({pageIndex, found, value.count})
            }

            return
        }

        var from = 0'u64
        while from < source.count
        {
            let found = Utf8.indexOf(source, text, from, options.comparison)
            if found == Swag.U64.Max do
                break
            if !options.wholeWord or isWholeWord(source, found, text.count) do
                result.add({pageIndex, found, text.count})
            from = found + Math.max(text.count, 1)
        }
    }

    // Makes a found range the selection and brings it into view, then remembers where to resume.
    mtd revealMatch(pageIdx, offset, length: u64)
    {
        .selAnchor     = {pageIdx, offset}
        .selCaret      = {pageIdx, offset + length}
        .selecting     = false
        .searchPage    = pageIdx
        .searchOffset  = offset + length
        .pendingReveal = true
        .showPage(pageIdx)

        // The page carrying the match is asked for at once rather than by the next frame, so a
        // host that reads the match's rectangle right after revealing it gets one as soon as the
        // worker publishes the page.
        .updateResidency()
        .scrollSelectionIntoView()
        .invalidate()
    }
}

internal impl PdfView
{
    // How often the view asks whether a worker has finished the page it owes it.
    const PollInterval: Time.Duration = 16'ms

    // Logical units between two pages of the column, and between the column and the viewport.
    const PageGap    = 12.0'f32
    const PageMargin = 12.0'f32

    // How many decoded pages are kept, and how much memory they may hold between them. A page of
    // text costs a hundredth of a page of scans, so neither bound alone describes a document:
    // the count keeps a light document from being walked page by page, and the budget keeps a
    // heavy one from filling memory. The pages the viewport reaches are exempt from both, because
    // the frame about to run needs them.
    const ResidentPageLimit  = 8'u64
    const ResidentPageBudget = 32 * 1024 * 1024'u64

    // How far the air under a page reaches, in logical units. A page is paper standing on the
    // ground the viewer shows it against, and the shadow is what says so; without it the page is
    // a white rectangle drawn on a dark one.
    const PageShadowSpread = 6.0'f32

    // Lays the document out for the current viewport and scale, and publishes what can be
    // scrolled.
    //
    // The canvas is one viewport tall whatever the document measures, and the paint applies the
    // scroll offset itself: a window as tall as a thousand-page document is not a shape the
    // surface geometry is built for.
    mtd placeDocument()
    {
        // The view is resized before the canvas it holds exists, and there is nothing to lay out
        // until it does.
        if .canvas == null do
            return

        let viewport = .viewportSize()
        .canvas.setPosition({0, 0, viewport.x, viewport.y})

        let content = .contentSize()
        .scroll.setScrollSize(content.x, content.y)
        .scroll.verticalScrollStep   = WheelScrollStep
        .scroll.horizontalScrollStep = WheelScrollStep
        .canvas.invalidate()
        .publishZoom()
    }

    // Reports the effective scale when it moved, whatever moved it.
    //
    // A fitted document rescales with its viewport, so the signal cannot belong to the zoom
    // operations alone: a window the reader resizes changes the scale without any of them.
    mtd publishZoom()
    {
        let scale = .effectiveZoom()
        if scale == .reportedZoom do
            return
        .reportedZoom = scale
        .sigZoomChanged.call(me)
    }

    // Decodes and evicts around the viewport.
    //
    // One page is decoded at a time, closest to the viewport first, and the neighbours a scroll
    // step away are decoded once the visible ones are in. A process with no worker thread
    // finishes a decode inside the request, so the loop publishes it and asks for the next page
    // rather than leaving the frame without the page it was asked to show.
    mtd updateResidency()
    {
        if !.hasDocument do
            return

        let range    = .visibleRange()
        let count    = .pageSizes.count
        let keepFrom = range.first ? range.first - 1 : 0
        let keepTo   = Math.min(range.last + 1, count - 1)

        // The page about to be evicted must not be the one the flattening worker is on.
        if .preparing and .preparingPage and (.preparingPage!.index < keepFrom or .preparingPage!.index > keepTo) do
            .stopPrepare()

        while true
        {
            .adoptPage()
            .cache.trim(.app().renderer, keepFrom, keepTo, ResidentPageLimit, ResidentPageBudget)
            if .cache.isLoading() do
                break

            let wanted = .wantedPage(range.first, range.last, keepFrom, keepTo)
            if wanted == Swag.U64.Max do
                break
            if !.cache.request(wanted, .flattenScale()) do
                break
        }

        if .cache.isLoading() do
            .ensurePollTimer()
    }

    // Returns the next page worth decoding, or `Swag.U64.Max` when the viewport has what it needs.
    mtd const wantedPage(first, last, keepFrom, keepTo: u64)->u64
    {
        for index in first to last where !.cache.isResident(index) do
            return index
        for index in keepFrom to keepTo where !.cache.isResident(index) do
            return index
        return Swag.U64.Max
    }

    // Moves the document by `notches` wheel steps, gliding rather than jumping.
    //
    // A wheel notch that lands the view somewhere new instantly is what makes a document reader
    // feel like a list of pages: the reader loses where the text they were on went. Each notch is
    // composed on top of where the movement in flight was heading, so a fast run of them is one
    // continuous glide.
    mtd scrollByWheel(notches: f32, modifiers: Input.KeyModifiers)
    {
        let target = .scroll.scrollTarget()
        let step   = notches * WheelScrollStep
        if modifiers.has(.Shift) or .contentSize().y <= .viewportSize().y do
            .scroll.smoothScrollTo({target.x - step, target.y})
        else do
            .scroll.smoothScrollTo({target.x, target.y - step})
    }

    // Publishes a page a worker finished decoding.
    mtd adoptPage()
    {
        let entry = .cache.adopt()
        if !entry do
            return

        if !entry!.failure.isEmpty() and !.reportedPaintError
        {
            .reportedPaintError = true
            .sigRenderError.call(me, entry!.failure.toString())
        }

        // A search that revealed a hit on this page could not place it until the page arrived.
        if .pendingReveal do
            .scrollSelectionIntoView()
        .invalidate()
    }

    // Has a worker raise one page's flattening to `wanted` when the page does not hold it.
    mtd requestPrepare(entry: *PdfResidentPage, wanted: f32)
    {
        if .preparing or wanted <= entry.preparedScale do
            return

        .preparingPage  = entry
        .preparingScale = wanted
        .prepareReady   = 0
        .prepareCancel  = 0
        .preparing      = true

        // Without a worker the task runs here and is already finished; the timer publishes it
        // either way rather than leaving this frame to decide.
        let view = me
        .prepareTask.submit(func|view|() { view.runPrepare() })
        .ensurePollTimer()
    }

    // Runs on the worker: prepares one page a shape at a time, handing it back between them.
    //
    // The lock is taken per shape rather than for the page, so a frame that starts while this
    // runs waits for one shape and not for the rest of the document. The page it is preparing may
    // be about to be evicted, so it stops between shapes when asked.
    mtd runPrepare()
    {
        let entry = .preparingPage
        if !entry do
            return

        var preparer: Pixel.FillPreparer
        let scale = .preparingScale

        for index in entry!.page.clipPaths.count
        {
            if Atomic.get(&.prepareCancel) != 0 do
                return
            Sync.scopedLock(&.pageLock)
            entry!.page.prepareClipPath(index, scale, &preparer)
        }

        for index in entry!.page.items.count
        {
            if Atomic.get(&.prepareCancel) != 0 do
                return
            Sync.scopedLock(&.pageLock)
            entry!.page.prepareItem(index, scale, &preparer)
        }

        Atomic.exchange(&.prepareReady, 1)
    }

    // Adopts a finished preparation, and reports whether a page moved to a finer flattening.
    mtd adoptPrepare()->bool
    {
        if !.preparing or Atomic.get(&.prepareReady) == 0 do
            return false

        .prepareTask.wait()
        if .preparingPage
        {
            // A finer flattening is geometry the page did not hold, so what the cache evicts on
            // is taken again here.
            .preparingPage!.preparedScale = .preparingScale
            .preparingPage!.measure()
        }

        .preparing     = false
        .preparingPage = null
        return true
    }

    // Stops the worker and forgets what it was raising, before the page it is on is replaced.
    mtd stopPrepare()
    {
        if .preparing
        {
            Atomic.exchange(&.prepareCancel, 1)
            .prepareTask.wait()
            .preparing = false
        }

        .preparingPage  = null
        .prepareReady   = 0
        .prepareCancel  = 0
        .preparingScale = 0
    }

    mtd ensurePollTimer()
    {
        if !.pollTimer do
            .pollTimer = .addTimer(PollInterval)
    }

    mtd stopPollTimer()
    {
        if .pollTimer
        {
            .removeTimer(.pollTimer!)
            .pollTimer = null
        }
    }

    // Draws the pages the viewport reaches, and the paper of those still being decoded.
    mtd paintDocument(painter: *Painter)
    {
        let colors = .themeColors()
        let range  = .visibleRange()
        let origin = .documentOrigin()
        let scale  = .effectiveZoom()
        if scale <= 0 do
            return

        let devicePerPoint = scale * .deviceScale()
        let wantedFlatten  = Painter.quantizeFlattenScale(devicePerPoint)
        let base           = painter.transform()

        for index in range.first to range.last
        {
            let rect = .pageRect(index)
            let box  = Math.Rectangle{origin.x + rect.x, origin.y + rect.y, rect.width, rect.height}
            if box.width <= 0 or box.height <= 0 do
                continue

            // The paper is drawn whether or not the page arrived, so a document scrolled faster
            // than it decodes shows where its pages are instead of a hole that fills in behind
            // the reader.
            painter.fillShadow(box, 0, PageShadowSpread, colors.wnd_Shadow)
            painter.fillRect(box, Color.fromArgb(Argb.White))
            painter.drawRect(box, colors.border, 1)

            let entry = .cache.resident(index)
            if !entry or !entry!.isDrawable() do
                continue

            entry!.ensureTextures(.app().renderer)

            // The page's curves are flattened for the scale it is shown at. Raising that is the
            // whole page's work, so the frame asks for what the page holds and lets a worker
            // catch up; the timer publishes the result.
            var flatten = wantedFlatten
            if entry!.preparedScale <= 0 do
                entry!.preparedScale = wantedFlatten
            elif entry!.preparedScale < wantedFlatten
            {
                .requestPrepare(entry!, wantedFlatten)
                flatten = entry!.preparedScale
            }

            // The widget's base transform only translates, so composing the page scale under it
            // keeps item clips axis-aligned.
            let pageToSurface = Math.Transform2{scale, 0, 0, scale, base.tx + box.x, base.ty + box.y}
            .pageLock.lock()
            catch Pdf.drawPageItems(painter, &entry!.page, pageToSurface, devicePerPoint, flatten, &entry!.fonts, "", entry!.textures.toSlice()) as pageError
            .pageLock.unlock()
            painter.setTransform(base)
            if pageError != null and !.reportedPaintError
            {
                .reportedPaintError = true
                .sigRenderError.call(me, Errors.message(pageError))
            }

            .paintSelection(painter, index, entry!, box, scale)
        }
    }

    // Washes the selected words of one page.
    //
    // The wash is translucent, so the marked words stay readable under it whatever the page
    // paints there.
    mtd paintSelection(painter: *Painter, index: u64, entry: *PdfResidentPage, box: Math.Rectangle, scale: f32)
    {
        let range = .selectionOnPage(index, entry)
        if range.end <= range.start do
            return

        var rects: Array'Math.Rectangle
        entry.textIndex.rangeRects(range.start, range.end, &rects)
        var wash = .themeColors().edit_SelectedBk
        wash.a = cast(u8) (cast(u32) wash.a * 140 / 255)
        for rect in rects do
            painter.fillRect({box.x + rect.x * scale, box.y + rect.y * scale, rect.width * scale, rect.height * scale}, wash)
    }

    // Returns the byte range of one page the selection covers, which is empty when it covers none.
    mtd selectionOnPage(index: u64, entry: *PdfResidentPage)->{ start: u64, end: u64 }
    {
        var result: retval
        if !.hasSelection() do
            return result

        let first = .selectionStart()
        let last  = .selectionEnd()
        if index < first.pageIndex or index > last.pageIndex do
            return result

        entry.ensureTextIndex()
        let length = entry.textIndex.text.length
        result.start = index == first.pageIndex ? Math.min(first.offset, length) : 0
        result.end   = index == last.pageIndex ? Math.min(last.offset, length) : length
        return result
    }

    // Returns the text of one page, from the page itself when it is decoded and from the text
    // the document extracted for search otherwise.
    mtd pageText(index: u64)->string
    {
        let entry = .cache.resident(index)
        if entry
        {
            entry!.ensureTextIndex()
            return entry!.text()
        }

        if .documentText.started and index < .documentText.readyCount() do
            return .documentText.pageText(index)
        return ""
    }

    // Returns the position of the page text under a canvas point, if any.
    mtd textPositionAt(local: Math.Point)->{ position: PdfTextPosition, distance: f32 }
    {
        var result: retval
        if !.hasDocument do
            return result

        let hit   = .documentPointAt(local)
        let entry = .cache.resident(hit.pageIndex)
        if !entry or !entry!.isDrawable() do
            return result

        entry!.ensureTextIndex()
        let found = entry!.textIndex.positionAt(hit.point)
        if found.offset == Swag.U64.Max do
            return result

        result.position = {hit.pageIndex, found.offset}
        result.distance = found.distance
        return result
    }

    // Brings the selection into view, which is what reveals a search hit.
    //
    // A hit on a page that is still being decoded cannot be placed on the page yet: the view
    // scrolls to the page and finishes the reveal when the page arrives.
    mtd scrollSelectionIntoView()
    {
        if !.hasSelection() do
            return

        let start = .selectionStart()
        let entry = .cache.resident(start.pageIndex)
        if !entry or !entry!.isDrawable() do
            return

        let range = .selectionOnPage(start.pageIndex, entry!)
        var rects: Array'Math.Rectangle
        entry!.textIndex.rangeRects(range.start, range.end, &rects)
        if rects.isEmpty() do
            return

        var bounds = rects[0]
        for index in 1 until rects.count
        {
            let rect  = rects[index]
            let right = Math.max(bounds.right(), rect.right())
            let down  = Math.max(bounds.bottom(), rect.bottom())
            bounds.x      = Math.min(bounds.x, rect.x)
            bounds.y      = Math.min(bounds.y, rect.y)
            bounds.width  = right - bounds.x
            bounds.height = down - bounds.y
        }

        .pendingReveal = false

        let page   = .pageRect(start.pageIndex)
        let scale  = .effectiveZoom()
        let target = Math.Rectangle{page.x + bounds.x * scale, page.y + bounds.y * scale, bounds.width * scale, bounds.height * scale}
        .scrollRectIntoView(target)
    }

    // Scrolls the smallest distance that brings a rectangle of the document inside the viewport.
    mtd scrollRectIntoView(target: Math.Rectangle)
    {
        let viewport = .viewportSize()
        let origin   = .documentOrigin()
        let left     = -origin.x
        let top      = -origin.y

        var dx = 0.0'f32
        var dy = 0.0'f32
        if target.right() + PageMargin > left + viewport.x do
            dx = target.right() + PageMargin - left - viewport.x
        if target.x - PageMargin < left + dx do
            dx = target.x - PageMargin - left
        if target.bottom() + PageMargin > top + viewport.y do
            dy = target.bottom() + PageMargin - top - viewport.y
        if target.y - PageMargin < top + dy do
            dy = target.y - PageMargin - top

        if dx == 0 and dy == 0 do
            return

        let position = .scroll.scrollPosition()
        .scroll.setScrollPos(position.x + dx, position.y + dy)
    }
}

impl IWnd for PdfView
{
    mtd impl onDestroyEvent(evt: *DestroyEvent)
    {
        .stopPrepare()
        .documentText.stop()
        .cache.close(.app().renderer)
    }

    mtd impl onTimerEvent(evt: *TimerEvent)
    {
        if evt.timer != .pollTimer
        {
            evt.accepted = false
            return
        }

        // A page now holds the finer flattening, or a worker finished decoding one; the frame
        // that shows either is free.
        if .adoptPrepare() do
            .invalidate()
        .adoptPage()

        if !.preparing and !.cache.isLoading() do
            .stopPollTimer()
    }

    mtd impl onKeyEvent(evt: *KeyEvent)
    {
        if evt.kind != .Pressed or !.hasDocument
        {
            evt.accepted = false
            return
        }

        // A held key is a run of steps, and each one is composed on top of where the glide before
        // it was heading rather than on where the view happens to be mid-movement.
        let viewport = .viewportSize()
        let target   = .scroll.scrollTarget()
        let step     = Math.max(viewport.y - WheelScrollStep, WheelScrollStep)
        switch evt.key
        {
        case .Up where evt.modifiers == .None:
            .scroll.smoothScrollTo({target.x, target.y - WheelScrollStep})

        case .Down where evt.modifiers == .None:
            .scroll.smoothScrollTo({target.x, target.y + WheelScrollStep})

        case .PageUp, .Space where evt.modifiers == .Shift:
            if .pageLayout == .Single do
                .previousPage()
            else do
                .scroll.smoothScrollTo({target.x, target.y - step})

        case .PageDown, .Space where evt.modifiers == .None:
            if .pageLayout == .Single do
                .nextPage()
            else do
                .scroll.smoothScrollTo({target.x, target.y + step})

        case .Left:

            // A page wider than the viewport is scrolled sideways; one that fits has nothing to
            // move, so the same key turns to the page before it.
            if .contentSize().x > viewport.x do
                .scroll.smoothScrollTo({target.x - WheelScrollStep, target.y})
            else do
                .previousPage()

        case .Right:
            if .contentSize().x > viewport.x do
                .scroll.smoothScrollTo({target.x + WheelScrollStep, target.y})
            else do
                .nextPage()

        case .Home:
            .showPage(0)

        case .End:
            if .pageSizes.count do
                .showPage(.pageSizes.count - 1)

        case .D0 where evt.modifiers.has(.Control):
            .actualSize()

        case .F:
            .zoomToFit()

        case .W:
            .zoomToFitWidth()

        case .C where evt.modifiers == .Control:
            if !.copySelection() do
                evt.accepted = false

        case .Insert where evt.modifiers == .Control:
            if !.copySelection() do
                evt.accepted = false

        case .A where evt.modifiers == .Control:
            .selectAll()

        case .Escape where evt.modifiers == .None:
            if .hasSelection() do
                .clearSelection()
            else do
                evt.accepted = false

        default:
            evt.accepted = false
        }
    }
}

internal impl IWnd for PdfCanvas
{
    mtd impl onPaint(evt: *PaintEvent)
    {
        let owner = .owner

        // The pages stand on the panel ground rather than on the ground content is read on: the
        // paper of a page is its own, and a white page on a white ground has no edge.
        let painter = evt.paintContext.painter
        painter.fillRect(.clientRect(), .themeColors().wnd_Bk)
        if !owner.hasDocument do
            return

        // What the viewport reaches decides what is decoded, so the residency step runs before
        // the pages are drawn rather than a frame behind them.
        owner.updateResidency()
        discard owner.adoptPrepare()

        // A page is drawn wherever the document puts it, and the painter rejects nothing on its
        // own, so the clip is what keeps a zoomed page inside the view.
        painter.pushClippingRect(.clientRect())
        owner.paintDocument(painter)
        painter.popClippingRect()
    }

    mtd impl onMouseEvent(evt: *MouseEvent)
    {
        let owner = .owner
        if !owner.hasDocument
        {
            evt.accepted = false
            return
        }

        let local = .surfaceToLocal(evt.surfacePos)
        switch evt.kind
        {
        case .Wheel:

            // `Ctrl` and the wheel zoom around the pointer; a plain wheel moves the document.
            if evt.modifiers.has(.Control)
            {
                let factor = evt.delta.y > 0 ? 1.12'f32 : 1.0'f32 / 1.12
                owner.applyZoom(owner.effectiveZoom() * factor, &local)
                return
            }

            owner.scrollByWheel(evt.delta.y, evt.modifiers)

        case .DoubleClick where evt.button == .Left:

            // A double click on a word takes the word; elsewhere it keeps toggling the zoom.
            let hit = owner.textPositionAt(local)
            if hit.position.isValid() and hit.distance == 0
            {
                owner.selectWordAt(hit.position)
                return
            }

            if owner.zoomMode == .Free do
                owner.zoomToFit()
            else do
                owner.actualSize()

        case .Pressed where evt.button == .Left:
            owner.setFocus()

            // A press on a word starts a selection drag; a press on anything else pans, which
            // keeps the document draggable everywhere the text is not.
            let hit = owner.textPositionAt(local)
            if hit.position.isValid() and hit.distance == 0
            {
                owner.selAnchor = hit.position
                owner.selCaret  = hit.position
                owner.selecting = true
                .captureMouse()
                .invalidate()
                return
            }

            if owner.hasSelection() do
                owner.clearSelection()
            owner.isPanning   = true
            owner.lastPointer = evt.surfacePos
            .captureMouse()

        case .Move:
            if owner.selecting
            {
                let hit = owner.textPositionAt(local)
                if hit.position.isValid() and !(hit.position == owner.selCaret)
                {
                    owner.selCaret = hit.position
                    .invalidate()
                }

                .app().setFrameCursor(Cursor.from(.IBeam))
                return
            }

            if !owner.isPanning
            {
                let hit = owner.textPositionAt(local)
                .app().setFrameCursor(Cursor.from(hit.position.isValid() and hit.distance == 0 ? CursorShape.IBeam : CursorShape.Hand))
                return
            }

            let delta    = evt.surfacePos - owner.lastPointer
            let position = owner.scroll.scrollPosition()
            owner.scroll.setScrollPos(position.x - delta.x, position.y - delta.y)
            owner.lastPointer = evt.surfacePos

        case .Pressed where evt.button == .Right:
            owner.setFocus()
            owner.showContextMenu(evt.surfacePos)

        case .Released where evt.button == .Left:
            if owner.selecting
            {
                owner.selecting = false
                .releaseMouse()
            }
            elif owner.isPanning
            {
                owner.isPanning = false
                .releaseMouse()
            }

        default:
            evt.accepted = false
        }
    }
}

impl PdfView
{
    const MinZoom         = 0.05'f32     // Smallest supported scale, in logical units per PDF point.
    const MaxZoom         = 64.0'f32     // Largest supported scale, in logical units per PDF point.
    const WheelScrollStep = 60.0'f32     // Logical units scrolled per wheel notch and per arrow key.

    // Creates an empty PDF viewer.
    #[Swag.Discardable]
    func create(parent: *Wnd, position: Math.Rectangle = {}, id: WndId? = null)->*PdfView
    {
        Swag.assert(parent != null)
        let result = Wnd.create'PdfView(parent, null, position, id)

        // A document view is a traversal stop: opening a file must leave the keyboard on the
        // document, or the arrows land on whatever container happens to hold the focus. The ring
        // itself belongs to the pages, which show where the reader is by scrolling.
        result.focusPolicy = .Tab
        result.wndFlags    |= .NoFocusRing

        result.scroll           = Wnd.create'ScrollWnd(result, "", {})
        result.scroll.dockStyle = .Center

        // The document is laid out from the viewport the scroll frame gives its view, so the
        // resize that has to trigger it is the view's own: the frame reserves the room its bars
        // take before it places the view, and hooking the frame instead would lay the document
        // out against the rectangle it had before that.
        let view = result.scroll.createView'Wnd(func|target = result|(wnd, evt)
        {
            discard wnd
            if evt is ResizeEvent do
                target.placeDocument()
            return false
        })

        view.backgroundStyle = .Window

        result.canvas          = Wnd.create'PdfCanvas(view, "gui.pdf.canvas")
        result.canvas.owner    = result
        result.canvas.wndFlags |= .NoScroll

        result.scroll.sigScrollPositionChanged += func|target = result|(scroll, oldPosition, newPosition)
        {
            discard scroll
            discard oldPosition
            discard newPosition
            target.updateCurrentPage()
            target.canvas.invalidate()
        }

        return result
    }

    // Opens a PDF file and shows its first page.
    //
    // The document's pages are laid out from its page tree, so the whole document is scrollable
    // when this returns; the pages themselves are decoded on a worker as the viewport reaches
    // them. The previous document, if any, is released. Encryption and embedded executable
    // content are not supported; embedded actions are ignored rather than executed.
    mtd open(fileName: string) fail
    {
        var reader = #move try Pdf.Reader.open(fileName)
        if !reader.pageCount() do
            fail Errors.InvalidFormatError{"PDF document contains no page"}
        .adoptDocument(&reader)
    }

    // Displays a prepared reader and its decoded first page by exchanging their ownership.
    //
    // This is the publication counterpart to opening and decoding a PDF outside the GUI thread.
    // `reader` must contain at least one page and `page` must be page zero decoded from that
    // reader. On return they own the content that previously belonged to the view, if any.
    mtd exchangeDocument(reader: *Pdf.Reader, page: *Pdf.Page)
    {
        Swag.assert(reader.pageCount() != 0)
        .adoptDocument(reader)

        // The page the host decoded is the one the first frame needs, so it is taken as it is
        // rather than decoded a second time on the worker.
        discard .cache.insert(0, page)
        .invalidate()
    }

    // Releases the document, its decoded pages, their textures, their typefaces, and the text
    // extracted for search, while keeping the widget alive.
    mtd close()
    {
        .stopPrepare()
        .stopPollTimer()
        .documentText.stop()
        .cache.close(.app().renderer)
        Swag.drop(&.reader, 1)
        Swag.init(&.reader, 1)
        .pageSizes.clear()
        .pageStarts.clear()
        .widestPage  = 0
        .tallestPage = 0
        .clearTextState()
        .searchQuery.clear()
        .searchPage, .searchOffset = 0
        .hasDocument               = false
        .pageIndex                 = 0
        .zoom                      = 1
        .zoomMode                  = .FitPage
        .reportedPaintError        = false
        .scroll.setScrollSize(0, 0)
        .scroll.setScrollPos(0, 0)
        .invalidate()
    }

    // Returns the document's descriptive fields.
    mtd const metadata()->Pdf.Metadata => .reader.metadata()

    // Returns the number of pages of the open document, or zero when none is open.
    mtd const pageCount()->u64 => .hasDocument ? .pageSizes.count : 0

    // Returns the dimensions of the page the viewport shows, in PDF points.
    mtd const pageSize()->Math.Point => .hasDocument ? .pageSizes[.pageIndex] : Math.Point{}

    // Selects how the document's pages are laid out, keeping the page the viewport shows.
    mtd setPageLayout(value: PdfPageLayout)
    {
        if .pageLayout == value do
            return
        .pageLayout = value
        .placeDocument()
        .showPage(.pageIndex)
        .publishZoom()
        .invalidate()
    }

    // Brings the page at zero-based `index` to the top of the viewport.
    //
    // Nothing is decoded here: the page is scrolled to at once and its content arrives from the
    // worker. An out-of-range index is ignored.
    mtd showPage(index: u64)
    {
        if !.hasDocument or index >= .pageSizes.count do
            return

        if .pageLayout == .Single
        {
            if index != .pageIndex
            {
                .pageIndex = index
                .placeDocument()
                .sigPageChanged.call(me)
                .publishZoom()
            }

            .scroll.setScrollPos(0, 0)
            .invalidate()
            return
        }

        let rect = .pageRect(index)
        .scroll.setScrollPos(.scroll.scrollPosition().x, rect.y - PageMargin)
        .updateCurrentPage()
        .invalidate()
    }

    // Shows the next page when one exists.
    mtd nextPage()
    {
        if .hasDocument and .pageIndex + 1 < .pageSizes.count do
            .showPage(.pageIndex + 1)
    }

    // Shows the previous page when one exists.
    mtd previousPage()
    {
        if .hasDocument and .pageIndex do
            .showPage(.pageIndex - 1)
    }

    // Returns the scale pages are currently shown at, in logical units per PDF point.
    mtd const effectiveZoom()->f32
    {
        if !.hasDocument do
            return 1
        if .zoomMode == .Free do
            return .zoom

        let viewport = .viewportSize()
        let width    = viewport.x - 2 * PageMargin
        let height   = viewport.y - 2 * PageMargin
        if width <= 0 or height <= 0 do
            return 1

        // A continuous document is fitted to the page it would need the most room for, so the
        // scale is the document's and does not change under the reader on the page that happens
        // to be the largest.
        let page = .pageLayout == .Single ? .pageSizes[.pageIndex] : Math.Point{.widestPage, .tallestPage}
        if page.x <= 0 or page.y <= 0 do
            return 1
        if .zoomMode == .FitWidth do
            return width / page.x
        return Math.min(width / page.x, height / page.y)
    }

    // Sets an explicit page scale and leaves fitted mode.
    mtd setZoom(value: f32)
    {
        .applyZoom(value)
    }

    // Increases the page scale by one viewer step.
    mtd zoomIn()
    {
        .applyZoom(.effectiveZoom() * 1.25)
    }

    // Decreases the page scale by one viewer step.
    mtd zoomOut()
    {
        .applyZoom(.effectiveZoom() / 1.25)
    }

    // Fits a whole page inside the viewport and keeps it fitted as the viewport changes.
    mtd zoomToFit()
    {
        .setZoomMode(.FitPage)
    }

    // Fits the page's width to the viewport and keeps it fitted as the viewport changes.
    //
    // This is the reading scale of a continuous document: the text is as wide as the window
    // allows, and scrolling runs through the pages.
    mtd zoomToFitWidth()
    {
        .setZoomMode(.FitWidth)
    }

    // Shows pages at actual size: one PDF point per 1/96 of a logical inch.
    mtd actualSize()
    {
        .applyZoom(ActualSizeZoom)
    }

    // Selects what a page is scaled to, keeping the page the viewport shows.
    mtd setZoomMode(value: PdfZoomMode)
    {
        if .zoomMode == value do
            return

        let current = .pageIndex
        .zoomMode = value
        .placeDocument()
        .showPage(current)
        .publishZoom()
        .invalidate()
    }

    // Reports whether the reader selected text.
    mtd const hasSelection()->bool => .selAnchor.isValid() and .selCaret.isValid() and !(.selAnchor == .selCaret)

    // Returns the first end of the selection in reading order.
    mtd const selectionStart()->PdfTextPosition => .selCaret.isBefore(.selAnchor) ? .selCaret : .selAnchor

    // Returns the last end of the selection in reading order.
    mtd const selectionEnd()->PdfTextPosition => .selCaret.isBefore(.selAnchor) ? .selAnchor : .selCaret

    // Empties the selection.
    mtd clearSelection()
    {
        if !.selAnchor.isValid() and !.selCaret.isValid() do
            return
        .clearTextState()
        .invalidate()
    }

    // Finds every non-overlapping text occurrence in page order.
    //
    // The document's text is extracted once per document, on a worker, the first time a search
    // asks for it; this call waits for that extraction, so the first search through a document
    // pays it and every later one costs the comparison alone. [[Gui.PdfView.collectTextMatches]]
    // is the same search without the wait. The returned value owns stable page and UTF-8 text
    // coordinates; pass one of its entries to [[Gui.PdfView.revealTextMatch]] while this document
    // remains open. An invalid regular expression returns an empty array.
    mtd findTextMatches(text: string, options: PdfTextSearchOptions = {})->Array'PdfTextMatch
    {
        var result: retval
        if !.hasDocument or !text.count do
            return result

        .ensureDocumentText()
        .documentText.wait()
        var page = 0'u64
        discard .collectTextMatches(text, options, &page, &result)
        return result
    }

    // Appends the matches of the pages whose text is extracted so far, from page `page[]` on,
    // and reports whether the whole document has been searched.
    //
    // The document's text is extracted on a worker, a page at a time, the first time a search
    // asks for it. This call never waits for a page: it searches the pages extracted since
    // `page[]`, moves `page[]` past them, and answers false while pages remain, so a host polls
    // it with the same query, options, page and array until it answers true. A new search starts
    // with `page[]` at zero. Matches arrive in page order, then in text order within a page; an
    // invalid regular expression ends the search with nothing appended.
    mtd collectTextMatches(text: string, options: PdfTextSearchOptions, page: *u64, result: *Array'PdfTextMatch)->bool
    {
        if !.hasDocument or !text.count do
            return true

        var expression: Parser.RegExp
        if options.regularExpression
        {
            catch expression.compile(text, ignoreCase: options.comparison == .Latin1NoCase) as expressionError
            if expressionError != null do
                return true
        }

        .ensureDocumentText()
        let ready = .documentText.readyCount()
        while page[] < ready
        {
            appendPageMatches(result, .documentText.pageText(page[]), page[], text, options, options.regularExpression ? &expression : null)
            page[] += 1
        }

        return .documentText.isComplete()
    }

    // Selects and reveals one match returned by [[Gui.PdfView.findTextMatches]].
    //
    // The page carrying the match is scrolled to at once; the match itself is brought into view
    // as soon as that page is decoded. Returns false when its page no longer belongs to the open
    // document.
    mtd revealTextMatch(match: PdfTextMatch)->bool
    {
        if !.hasDocument or match.pageIndex >= .pageSizes.count do
            return false
        .revealMatch(match.pageIndex, match.byteOffset, match.byteLength)
        return true
    }

    // Reports the rendered rectangle of a match in surface coordinates.
    //
    // Returns false until the page carrying the match is decoded, or when the range no longer
    // belongs to the open document. This is the geometry-only counterpart of
    // [[Gui.PdfView.revealTextMatch]]; hosts remain responsible for how a current result is
    // presented.
    mtd textMatchRect(match: PdfTextMatch, result: *Math.Rectangle)->bool
    {
        if !.hasDocument or match.pageIndex >= .pageSizes.count do
            return false

        let entry = .cache.resident(match.pageIndex)
        if !entry or !entry!.isDrawable() do
            return false

        entry!.ensureTextIndex()
        if match.byteOffset + match.byteLength > entry!.textIndex.text.length do
            return false

        var rects: Array'Math.Rectangle
        entry!.textIndex.rangeRects(match.byteOffset, match.byteOffset + match.byteLength, &rects)
        if rects.isEmpty() do
            return false

        var bounds = rects[0]
        for index in 1 until rects.count
        {
            let rect  = rects[index]
            let right = Math.max(bounds.right(), rect.right())
            let down  = Math.max(bounds.bottom(), rect.bottom())
            bounds.x      = Math.min(bounds.x, rect.x)
            bounds.y      = Math.min(bounds.y, rect.y)
            bounds.width  = right - bounds.x
            bounds.height = down - bounds.y
        }

        let page   = .pageRect(match.pageIndex)
        let origin = .documentOrigin()
        let scale  = .effectiveZoom()
        let local  = Math.Rectangle{origin.x + page.x + bounds.x * scale, origin.y + page.y + bounds.y * scale,
                                    bounds.width * scale, bounds.height * scale}
        result[] = .canvas.localToSurface(local)
        return !result.isEmpty()
    }

    // Selects the whole text of the page the viewport shows.
    mtd selectAll()
    {
        if !.hasDocument do
            return

        let entry = .cache.resident(.pageIndex)
        if !entry or !entry!.isDrawable() do
            return

        entry!.ensureTextIndex()
        if entry!.textIndex.text.isEmpty() do
            return

        .selAnchor = {.pageIndex, 0}
        .selCaret  = {.pageIndex, entry!.textIndex.text.length}
        .selecting = false
        .invalidate()
    }

    // Returns the selected text, in the reading order the pages index to.
    //
    // A selection running through several pages joins them with one line feed per page boundary.
    mtd selectedText()->String
    {
        var result: retval
        if !.hasSelection() do
            return result

        let first = .selectionStart()
        let last  = .selectionEnd()
        for index in first.pageIndex to last.pageIndex
        {
            let text  = .pageText(index)
            let start = index == first.pageIndex ? Math.min(first.offset, text.count) : 0
            let end   = index == last.pageIndex ? Math.min(last.offset, text.count) : text.count
            if end <= start do
                continue
            if !result.isEmpty() do
                result.append("\n")
            result.append(text[start until end])
        }

        return result
    }

    // Puts the selected text on the clipboard, and reports whether there was one.
    mtd copySelection()->bool
    {
        if !.hasSelection() do
            return false
        let text = .selectedText()
        if text.isEmpty() do
            return false
        Clipboard.addString(text.toString())
        return true
    }

    // Finds and reveals the next occurrence of `text`, scanning forward from the last hit and
    // wrapping once around the document. The match becomes the selection, so a copy right after
    // a search takes what the search found. Reports whether any page holds the text.
    //
    // The document's text is extracted once per document, on a worker, and the first search waits
    // for it; the page carrying the match is scrolled to without waiting for it to decode.
    mtd findText(text: string)->bool
    {
        if !.hasDocument or !text.count do
            return false

        if .searchQuery != text
        {
            .searchQuery  = text
            .searchPage   = .pageIndex
            .searchOffset = 0
        }

        .ensureDocumentText()
        .documentText.wait()

        // The resume page is visited twice — its tail first, its head after the wrap — so one
        // pass covers the whole document from wherever the previous hit stopped.
        let count = .pageSizes.count
        var visit = 0'u64
        while visit <= count
        {
            let pageIdx = (.searchPage + visit) % count
            let from    = visit == 0 ? .searchOffset : 0
            visit += 1

            let source = .documentText.pageText(pageIdx)
            if from >= source.count do
                continue
            let found = Utf8.indexOf(source, text, from, .Latin1NoCase)
            if found == Swag.U64.Max do
                continue

            .revealMatch(pageIdx, found, text.count)
            return true
        }

        return false
    }

    internal const CtxCopy      = "Pdf.CtxCopy"
    internal const CtxSelectAll = "Pdf.CtxSelectAll"

    // Starts extracting the document's text for search, once per document.
    internal mtd ensureDocumentText()
    {
        if .documentText.started or !.hasDocument do
            return
        .documentText.start(.reader.fileName(), .reader.pageCount())
    }

    // Selects the word around one position of the document, the double-click gesture.
    internal mtd selectWordAt(position: PdfTextPosition)
    {
        let entry = .cache.resident(position.pageIndex)
        if !entry or !entry!.isDrawable() do
            return

        entry!.ensureTextIndex()
        let range = entry!.textIndex.wordRangeAt(position.offset)
        if range.end <= range.start do
            return

        .selAnchor = {position.pageIndex, range.start}
        .selCaret  = {position.pageIndex, range.end}
        .selecting = false
        .invalidate()
    }

    // Offers the reading vocabulary at `surfacePos`: what a page can give the clipboard, with the
    // same shortcuts the keyboard already binds.
    internal mtd showContextMenu(surfacePos: Math.Point)
    {
        let menu = MenuCtrl.createPopup(me, owner: me)
        menu.addItem(strings().edit_Copy, CtxCopy, rightName: "Ctrl+C", disabled: !.hasSelection())
        menu.addSeparator()
        menu.addItem(strings().edit_SelectAll, CtxSelectAll, rightName: "Ctrl+A")

        let picked = menu.doModal(surfacePos, .TopLeft, autoDestroy: true) orelse ""
        switch picked
        {
        case CtxCopy:      discard .copySelection()
        case CtxSelectAll: .selectAll()
        }
    }
}
