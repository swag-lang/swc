#global public

using Core, Pixel

// Displays a PDF document with viewer-oriented zooming, panning, and page navigation.
//
// The view opens a document through [[Gui.Pdf.Reader]], so pages are decoded on demand and the
// displayed page stays decoded between paints. A page is vector art, and it is painted as such:
// every paint draws the decoded items straight through the widget's painter — the application
// renderer, not an offline rasterization — at the exact scale the page is shown at, zoom and
// monitor scale included. A zoom or pan step is therefore a transform change, not a raster: the
// page's images are uploaded to the renderer once per page, its typefaces are resolved once per
// page, and path tessellations are cached inside the decoded page itself.
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
        sigRenderError: SigArray'func||(*PdfView, string)     // Emitted when a page cannot be decoded or painted.

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

            // Textures of the page's image items, uploaded to the application renderer once
            // per page and reused by every subsequent paint, in item order.
            imageTextures: Array'Texture
            hasTextures:   bool

            // Typefaces resolved once per page rather than once per paint.
            fonts: Pdf.RenderFontCache

            // One failing paint reports through `sigRenderError` once, not once per frame.
            reportedPaintError: bool

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
    // Uploads the page's images to the application renderer, once per page.
    //
    // The decoded page keeps the pixels; the textures are the renderer-side copies every
    // subsequent paint reuses, whatever the zoom.
    mtd ensureTextures()
    {
        if .hasTextures do
            return
        let renderer = .app().renderer
        for item in .page.items where item.kind == .Image do
            .imageTextures.add(renderer.addImage(item.image))
        .hasTextures = true
    }

    mtd releaseTextures()
    {
        if .hasTextures
        {
            let renderer = .app().renderer
            for &texture in .imageTextures do
                renderer.removeTexture(texture)
        }

        .imageTextures.clear()
        .hasTextures = false
    }
}

impl IWnd for PdfView
{
    mtd impl onDestroyEvent(evt: *DestroyEvent)
    {
        .releaseTextures()
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

        .ensureTextures()

        let content = .contentRect()
        let scale   = .effectiveZoom()
        if content.width <= 0 or content.height <= 0 or scale <= 0 do
            return

        // The page is drawn as the vector art it is, clipped to the view so a zoomed page
        // never paints over a neighbour. The widget's base transform only translates, so
        // composing the page scale under it keeps item clips axis-aligned.
        let base = painter.transform()
        painter.pushClippingRect(.clientRect())
        painter.fillRect(content, Color.fromArgb(Argb.White))

        let pageToSurface = Math.Transform2{scale, 0, 0, scale, base.tx + content.x, base.ty + content.y}
        catch Pdf.drawPageItems(painter, &.page, pageToSurface, scale * .deviceScale(), &.fonts, "", .imageTextures.toSlice()) as paintError
        painter.setTransform(base)
        painter.popClippingRect()

        if paintError != null and !.reportedPaintError
        {
            .reportedPaintError = true
            .sigRenderError.call(me, Errors.message(paintError))
        }
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

    // Releases the displayed page, its textures, and its typefaces while keeping the widget alive.
    mtd close()
    {
        .releaseTextures()
        @drop(&.page, 1)
        @init(&.page, 1)
        .fonts.reset(0)
        .hasPage            = false
        .pageIndex          = 0
        .zoom               = 1
        .isFitted           = true
        .panOffset          = {}
        .reportedPaintError = false
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
        .releaseTextures()
        @drop(&.page, 1)
        @init(&.page, 1)
        .page      = #move page
        .hasPage   = true
        .pageIndex = index
        .panOffset = {}
        .fonts.reset(.page.fonts.count)
        .reportedPaintError = false
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
