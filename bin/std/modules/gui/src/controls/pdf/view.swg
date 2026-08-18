#global public

using Core, Pixel

// Displays a PDF document with viewer-oriented zooming, panning, and page navigation.
//
// The view opens a document through [[Gui.Pdf.Reader]], so pages are decoded on demand and the
// displayed page stays decoded between paints. A page is vector art: the view rasterizes it at
// the exact scale it is shown at — zoom and monitor scale included — so sharpness follows the
// display rather than the scale the page happened to be rendered at first. Past a fixed pixel
// budget only the visible region is rasterized, which is what keeps a deep zoom costing the
// viewport rather than the page.
//
// The mouse wheel scrolls, `Ctrl` and the wheel zoom around the pointer, dragging pans, a double
// click toggles between fitted and actual size, and the arrow, page, `Home` and `End` keys turn
// pages. Embedded actions, scripts, and forms are never executed.
//
// ```swag
// let view = PdfView.create(parent)
// try view.open("document.pdf")
// view.setZoom(2.0)
// ```
struct PdfView
{
    public
    {
        using wnd: Wnd     // Embedded window behavior and presentation.

        sigPageChanged: SigArray'func||(*PdfView)             // Emitted after the displayed page changes.
        sigZoomChanged: SigArray'func||(*PdfView)             // Emitted after the effective zoom changes.
        sigRenderError: SigArray'func||(*PdfView, string)     // Emitted when a page cannot be decoded or rasterized.

        public readonly
        {
            zoom:      f32  = 1        // Requested logical units per PDF point outside fitted mode.
            isFitted:  bool = true     // Whether the page is scaled to the available viewport.
            panOffset: Math.Point      // Page-centre offset from the viewport centre, in logical units.
            pageIndex: u64             // Zero-based index of the displayed page.
        }

        internal
        {
            reader:  Pdf.Reader
            page:    Pdf.Page
            hasPage: bool

            // The current rasterization: which page region it covers, and at how many raster
            // pixels per PDF point it was produced.
            texture:     Texture
            rasterScale: f32
            rasterRect:  Math.Rectangle

            isPanning:   bool
            lastPointer: Math.Point
        }
    }
}

private impl PdfView
{
    // One PDF point shown at actual size covers 96/72 logical units: a point is 1/72 inch and
    // a logical unit is 1/96 inch.
    const ActualSizeZoom = 96.0'f32 / 72.0

    // Raster budget above which only the visible region is rasterized. A whole A4 page stays
    // whole up to roughly a 4x zoom on a standard display; past that the raster follows the
    // viewport, whose size bounds the cost of every further zoom step.
    const MaxFullRasterPixels = 16_777_216.0'f32

    // Page-space margin kept rasterized around the viewport, in raster pixels, so a small pan
    // does not rasterize on every pointer move.
    const RasterMarginPixels = 256.0'f32

    // Scale drift tolerated before the page is rasterized again.
    const RasterScaleTolerance = 0.02'f32

    // Returns the widget-space rectangle the complete page occupies.
    mtd const contentRect()->Math.Rectangle
    {
        if !.hasPage do
            return {}

        let client = .paddedClientRect()
        let scale  = .effectiveZoom()

        var result: retval
        result.width  = .page.width * scale
        result.height = .page.height * scale
        result.x      = client.horzCenter() - result.width * 0.5 + .panOffset.x
        result.y      = client.vertCenter() - result.height * 0.5 + .panOffset.y
        return result
    }

    mtd applyZoom(value: f32, anchor: #null const *Math.Point = null)
    {
        let oldZoom = .effectiveZoom()
        let oldRect = .contentRect()

        .isFitted = false
        .zoom     = Math.clamp(value, MinZoom, MaxZoom)

        if anchor and oldRect.width > 0 and oldRect.height > 0 and oldZoom > 0
        {
            let point  = anchor
            let ratioX = (point.x - oldRect.x) / oldRect.width
            let ratioY = (point.y - oldRect.y) / oldRect.height
            let next   = .contentRect()
            .panOffset.x += point.x - (next.x + next.width * ratioX)
            .panOffset.y += point.y - (next.y + next.height * ratioY)
        }

        .sigZoomChanged.call(me)
        .invalidate()
    }

    mtd showPageOrReport(index: u64)
    {
        catch .showPage(index) as pageError
        if pageError != null do
            .sigRenderError.call(me, Errors.message(pageError))
    }
}

internal impl PdfView
{
    mtd releaseRaster()
    {
        if .texture.isValid() do
            .app().renderer.removeTexture(&.texture)
        .rasterScale = 0
        .rasterRect.clear()
    }

    // Rasterizes what the viewport shows, at the sharpness it is shown at, when the raster on
    // hand no longer provides it. The decoded page is reused as it is: no zoom or pan step
    // decodes the document again.
    mtd ensureRaster()
    {
        if !.hasPage do
            return
        let client = .paddedClientRect()
        if client.width <= 0 or client.height <= 0 do
            return
        let scale  = .effectiveZoom()
        let wanted = scale * .deviceScale()
        if wanted <= 0 or !Math.isFinite(wanted) do
            return

        // The whole page within the pixel budget, the visible region past it.
        let pageRect  = Math.Rectangle{0, 0, .page.width, .page.height}
        var region    = pageRect
        var needed    = pageRect
        let wholePage = .page.width * wanted * .page.height * wanted <= MaxFullRasterPixels
        if !wholePage
        {
            let content = .contentRect()
            var visible = Math.Rectangle{(client.x - content.x) / scale, (client.y - content.y) / scale, client.width / scale, client.height / scale}
            visible.intersect(pageRect)
            if visible.width <= 0 or visible.height <= 0 do
                visible = {0, 0, Math.min(.page.width, 1'f32), Math.min(.page.height, 1'f32)}
            needed = visible
            visible.inflate(RasterMarginPixels / wanted)
            visible.intersect(pageRect)
            region = visible
        }

        if .texture.isValid() and Math.abs(.rasterScale - wanted) <= wanted * RasterScaleTolerance and .rasterRect.contains(needed) do
            return

        let image = catch .page.render({scale: wanted, sourceRect: wholePage ? Math.Rectangle{} : region}) as renderError
        if renderError != null
        {
            .sigRenderError.call(me, Errors.message(renderError))
            return
        }

        .releaseRaster()
        .texture     = .app().renderer.addImage(image)
        .rasterScale = wanted
        .rasterRect  = region
    }
}

impl IWnd for PdfView
{
    mtd impl onDestroyEvent(evt: *DestroyEvent)
    {
        .releaseRaster()
    }

    mtd impl onResizeEvent(evt: *ResizeEvent)
    {
        if .isFitted do
            .sigZoomChanged.call(me)
    }

    mtd impl onPaint(evt: *PaintEvent)
    {
        let painter = evt.paintContext.painter
        painter.fillRect(.clientRect(), .themeColors().view_Bk)
        if !.hasPage do
            return

        .ensureRaster()
        if !.texture.isValid() do
            return

        // The raster covers `rasterRect` of the page; place exactly that region.
        let content = .contentRect()
        let scale   = .effectiveZoom()
        var destination: Math.Rectangle
        destination.x      = content.x + .rasterRect.x * scale
        destination.y      = content.y + .rasterRect.y * scale
        destination.width  = .rasterRect.width * scale
        destination.height = .rasterRect.height * scale
        painter.drawTexture(destination, .texture)
    }

    mtd impl onMouseEvent(evt: *MouseEvent)
    {
        switch evt.kind
        {
        case .Wheel:
            if !.hasPage
            {
                evt.accepted = false
                return
            }

            // The wheel scrolls, as it does in every document viewer; with `Ctrl` it zooms
            // around the pointer, and with `Shift` it scrolls sideways.
            if evt.modifiers.has(.Control)
            {
                let factor = evt.delta.y > 0 ? 1.12'f32 : 1.0'f32 / 1.12
                let anchor = .surfaceToLocal(evt.surfacePos)
                .applyZoom(.effectiveZoom() * factor, &anchor)
            }
            else
            {
                let step = evt.delta.y > 0 ? WheelScrollStep : -WheelScrollStep
                if evt.modifiers.has(.Shift) do
                    .panOffset.x += step
                else do
                    .panOffset.y += step
                .invalidate()
            }

        case .DoubleClick where evt.button == .Left:
            if .isFitted do
                .actualSize()
            else do
                .zoomToFit()

        case .Pressed where evt.button == .Left:
            if !.hasPage do
                return
            .isPanning   = true
            .lastPointer = evt.surfacePos
            .captureMouse()

        case .Move:
            if !.isPanning
            {
                if .hasPage do
                    .app().setFrameCursor(Cursor.from(.Hand))
                return
            }

            .panOffset   += evt.surfacePos - .lastPointer
            .lastPointer = evt.surfacePos
            .invalidate()

        case .Released where evt.button == .Left:
            if .isPanning
            {
                .isPanning = false
                .releaseMouse()
            }

        default:
            evt.accepted = false
        }
    }

    mtd impl onKeyEvent(evt: *KeyEvent)
    {
        if evt.kind != .Pressed or !.hasPage
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
            .zoomToFit()

        default:
            evt.accepted = false
        }
    }
}

impl PdfView
{
    const MinZoom         = 0.05'f32     // Smallest supported scale, in logical units per PDF point.
    const MaxZoom         = 64.0'f32     // Largest supported scale, in logical units per PDF point.
    const WheelScrollStep = 60.0'f32     // Logical units scrolled per wheel notch.

    // Creates an empty PDF viewer.
    #[Swag.Discardable]
    func create(parent: *Wnd, position: Math.Rectangle = {}, id: #null WndId = null)->*PdfView
    {
        Debug.assert(parent != null)
        let result = Wnd.create'PdfView(parent, null, position, id)
        result.focusPolicy = .Click
        return result
    }

    // Opens a PDF file and shows its first page fitted to the viewport.
    //
    // The previous document, if any, is released. Encryption and embedded executable content
    // are not supported; embedded actions are ignored rather than executed.
    mtd open(fileName: string) fail
    {
        var reader = try Pdf.Reader.open(fileName)
        if !reader.pageCount() do
            fail Errors.InvalidFormatError{"PDF document contains no page"}

        .close()
        @drop(&.reader, 1)
        @init(&.reader, 1)
        .reader = #move reader
        try .showPage(0)
    }

    // Releases the displayed page and its raster while keeping the widget alive.
    mtd close()
    {
        .releaseRaster()
        @drop(&.page, 1)
        @init(&.page, 1)
        .hasPage   = false
        .pageIndex = 0
        .zoom      = 1
        .isFitted  = true
        .panOffset = {}
        .invalidate()
    }

    // Returns the document's descriptive fields.
    mtd const metadata()->Pdf.Metadata => .reader.metadata()

    // Returns the number of pages of the open document, or zero when none is open.
    mtd const pageCount()->u64 => .hasPage ? .reader.pageCount() : 0

    // Returns the displayed page's dimensions in PDF points.
    mtd const pageSize()->Math.Point => .hasPage ? Math.Point{.page.width, .page.height} : Math.Point{}

    // Decodes and shows the page at zero-based `index`, preserving the zoom mode.
    mtd showPage(index: u64) fail
    {
        if index >= .reader.pageCount() do
            fail Errors.BadParameterError{"PDF page index exceeds the document page count"}

        var page = try .reader.loadPage(index)
        .releaseRaster()
        @drop(&.page, 1)
        @init(&.page, 1)
        .page      = #move page
        .hasPage   = true
        .pageIndex = index
        .panOffset = {}
        .sigPageChanged.call(me)
        if .isFitted do
            .sigZoomChanged.call(me)
        .invalidate()
    }

    // Shows the next page when one exists.
    mtd nextPage()
    {
        if .hasPage and .pageIndex + 1 < .reader.pageCount() do
            .showPageOrReport(.pageIndex + 1)
    }

    // Shows the previous page when one exists.
    mtd previousPage()
    {
        if .hasPage and .pageIndex do
            .showPageOrReport(.pageIndex - 1)
    }

    // Returns the scale the page is currently shown at, in logical units per PDF point.
    mtd const effectiveZoom()->f32
    {
        if !.hasPage do
            return 1
        if !.isFitted do
            return .zoom

        let client = .paddedClientRect()
        if client.width <= 0 or client.height <= 0 or .page.width <= 0 or .page.height <= 0 do
            return 1
        return Math.min(client.width / .page.width, client.height / .page.height)
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

    // Fits the complete page inside the viewport and recentres it.
    mtd zoomToFit()
    {
        .isFitted  = true
        .panOffset = {}
        .sigZoomChanged.call(me)
        .invalidate()
    }

    // Shows the page at actual size: one PDF point per 1/96 of a logical inch.
    mtd actualSize()
    {
        .panOffset = {}
        .applyZoom(ActualSizeZoom)
    }
}
