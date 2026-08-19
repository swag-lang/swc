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
// The page's text can be worked with: a drag over words selects them, a double click takes the
// word, `Ctrl+C` and the right-click menu copy the selection, and [[Gui.PdfView.findText]]
// searches the whole document and reveals what it finds.
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

        readonly
        {
            zoom:      f32  = 1        // Requested logical units per PDF point outside fitted mode.
            isFitted:  bool = true     // Whether the page is scaled to the available viewport.
            panOffset: Math.Point      // Page-centre offset from the viewport centre, in logical units.
            pageIndex: u64             // Zero-based index of the displayed page.
        }
    }

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

    // The displayed page's text, indexed once per page and only when selection or
    // search first asks for it.
    textIndex:    Pdf.TextIndex
    hasTextIndex: bool

    // The reader's selection, as byte offsets into the indexed page text. The anchor is
    // where the press landed and the caret follows the pointer.
    selAnchor = Swag.U64.Max
    selCaret  = Swag.U64.Max
    selecting: bool

    // Where the running search resumes: the page and the offset just past the last hit.
    searchQuery:  String
    searchPage:   u64
    searchOffset: u64
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

    // Converts a widget-local point into page points.
    mtd const pageFromLocal(point: Math.Point)->Math.Point
    {
        let content = .contentRect()
        let scale   = .effectiveZoom()
        if scale <= 0 do
            return {}
        return {(point.x - content.x) / scale, (point.y - content.y) / scale}
    }

    // Indexes the displayed page's text, once per page and only when selection or search asks.
    mtd ensureTextIndex()
    {
        if .hasTextIndex or !.hasPage do
            return
        .textIndex    = Pdf.TextIndex.build(&.page)
        .hasTextIndex = true
    }

    // Drops the text index and the selection a page change invalidates.
    mtd clearTextState()
    {
        .textIndex.text.clear()
        .textIndex.runs.clear()
        .hasTextIndex = false
        .selAnchor    = Swag.U64.Max
        .selCaret     = Swag.U64.Max
        .selecting    = false
    }

    // Pans just enough for the selection to be visible, which is what reveals a search hit.
    mtd scrollSelectionIntoView()
    {
        if !.hasSelection() do
            return

        var rects: Array'Math.Rectangle
        .textIndex.rangeRects(Math.min(.selAnchor, .selCaret), Math.max(.selAnchor, .selCaret), &rects)
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

        let content = .contentRect()
        let scale   = .effectiveZoom()
        let client  = .paddedClientRect()
        var target  = Math.Rectangle{content.x + bounds.x * scale, content.y + bounds.y * scale, bounds.width * scale, bounds.height * scale}

        var dx = 0.0'f32
        var dy = 0.0'f32
        if target.right() > client.right() do
            dx = client.right() - target.right()
        if target.x + dx < client.x do
            dx = client.x - target.x
        if target.bottom() > client.bottom() do
            dy = client.bottom() - target.bottom()
        if target.y + dy < client.y do
            dy = client.y - target.y

        if dx != 0 or dy != 0
        {
            .panOffset.x += dx
            .panOffset.y += dy
            .invalidate()
        }
    }

    // Makes a found range the selection and reveals it, then remembers where to resume.
    mtd revealMatch(pageIdx, offset, length: u64)
    {
        .ensureTextIndex()
        .selAnchor    = Math.min(offset, .textIndex.text.length)
        .selCaret     = Math.min(offset + length, .textIndex.text.length)
        .selecting    = false
        .searchPage   = pageIdx
        .searchOffset = offset + length
        .scrollSelectionIntoView()
        .invalidate()
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

        // The selection is a translucent wash over the drawn page, so the marked words stay
        // readable under it whatever the page paints there.
        if .hasSelection()
        {
            var rects: Array'Math.Rectangle
            .textIndex.rangeRects(Math.min(.selAnchor, .selCaret), Math.max(.selAnchor, .selCaret), &rects)
            var wash = .themeColors().edit_SelectedBk
            wash.a = cast(u8) (cast(u32) wash.a * 140 / 255)
            for rect in rects do
                painter.fillRect({content.x + rect.x * scale, content.y + rect.y * scale, rect.width * scale, rect.height * scale}, wash)
        }

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
            if .hasPage
            {
                // A double click on a word takes the word; elsewhere it keeps toggling the zoom.
                .ensureTextIndex()
                let hit = .textIndex.positionAt(.pageFromLocal(.surfaceToLocal(evt.surfacePos)))
                if hit.offset != Swag.U64.Max and hit.distance == 0
                {
                    .selectWordAt(hit.offset)
                    return
                }
            }

            if .isFitted do
                .actualSize()
            else do
                .zoomToFit()

        case .Pressed where evt.button == .Left:
            if !.hasPage do
                return

            // A press on a word starts a selection drag; a press on anything else pans, which
            // keeps the page draggable everywhere the text is not.
            .ensureTextIndex()
            let hit = .textIndex.positionAt(.pageFromLocal(.surfaceToLocal(evt.surfacePos)))
            if hit.offset != Swag.U64.Max and hit.distance == 0
            {
                .selAnchor = hit.offset
                .selCaret  = hit.offset
                .selecting = true
                .captureMouse()
                .invalidate()
                return
            }

            if .hasSelection() do
                .clearSelection()
            .isPanning   = true
            .lastPointer = evt.surfacePos
            .captureMouse()

        case .Move:
            if .selecting
            {
                let hit = .textIndex.positionAt(.pageFromLocal(.surfaceToLocal(evt.surfacePos)))
                if hit.offset != Swag.U64.Max and hit.offset != .selCaret
                {
                    .selCaret = hit.offset
                    .invalidate()
                }

                .app().setFrameCursor(Cursor.from(.IBeam))
                return
            }

            if !.isPanning
            {
                if .hasPage
                {
                    .ensureTextIndex()
                    let hit = .textIndex.positionAt(.pageFromLocal(.surfaceToLocal(evt.surfacePos)))
                    .app().setFrameCursor(Cursor.from(hit.offset != Swag.U64.Max and hit.distance == 0 ? CursorShape.IBeam : CursorShape.Hand))
                }

                return
            }

            .panOffset   += evt.surfacePos - .lastPointer
            .lastPointer = evt.surfacePos
            .invalidate()

        case .Pressed where evt.button == .Right:
            if !.hasPage do
                return
            .setFocus()
            .showContextMenu(evt.surfacePos)

        case .Released where evt.button == .Left:
            if .selecting
            {
                .selecting = false
                .releaseMouse()
            }
            elif .isPanning
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

        // A document view is a traversal stop: opening a file must leave the keyboard on the
        // page, or the arrows land on whatever container happens to hold the focus.
        result.focusPolicy = .Tab
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
        .clearTextState()
        .searchQuery.clear()
        .searchPage, .searchOffset = 0
        .hasPage                   = false
        .pageIndex                 = 0
        .zoom                      = 1
        .isFitted                  = true
        .panOffset                 = {}
        .reportedPaintError        = false
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
        .clearTextState()
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

    // Reports whether the reader selected text on the displayed page.
    mtd const hasSelection()->bool => .selAnchor != Swag.U64.Max and .selCaret != Swag.U64.Max and .selAnchor != .selCaret

    // Empties the selection.
    mtd clearSelection()
    {
        if .selAnchor == Swag.U64.Max and .selCaret == Swag.U64.Max do
            return
        .selAnchor = Swag.U64.Max
        .selCaret  = Swag.U64.Max
        .selecting = false
        .invalidate()
    }

    // Selects the whole text of the displayed page.
    mtd selectAll()
    {
        if !.hasPage do
            return
        .ensureTextIndex()
        if .textIndex.text.isEmpty() do
            return
        .selAnchor = 0
        .selCaret  = .textIndex.text.length
        .selecting = false
        .invalidate()
    }

    // Returns the selected text, in the reading order the page indexes to.
    mtd selectedText()->String
    {
        var result: retval
        if !.hasSelection() do
            return result
        let lo = Math.min(.selAnchor, .selCaret)
        let hi = Math.max(.selAnchor, .selCaret)
        result = .textIndex.text[lo until hi]
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
    // Every page visited between the current one and the match is decoded to extract its text,
    // so the first search through a large document pays one decode per crossed page.
    mtd findText(text: string)->bool
    {
        if !.hasPage or !@countof(text) do
            return false

        if .searchQuery != text
        {
            .searchQuery  = text
            .searchPage   = .pageIndex
            .searchOffset = 0
        }

        // The resume page is visited twice — its tail first, its head after the wrap — so one
        // pass covers the whole document from wherever the previous hit stopped.
        let count = .reader.pageCount()
        var visit = 0'u64
        while visit <= count
        {
            let pageIdx = (.searchPage + visit) % count
            let from    = visit == 0 ? .searchOffset : 0
            visit += 1

            if pageIdx == .pageIndex
            {
                .ensureTextIndex()
                if from >= .textIndex.text.length do
                    continue
                let found = Utf8.indexOf(.textIndex.text.toString(), text, from, .Latin1NoCase)
                if found == Swag.U64.Max do
                    continue
                .revealMatch(pageIdx, found, @countof(text))
                return true
            }

            var page = catch .reader.loadPage(pageIdx) as pageError
            if pageError != null do
                continue
            let index = Pdf.TextIndex.build(&page)
            if from >= index.text.length do
                continue
            let found = Utf8.indexOf(index.text.toString(), text, from, .Latin1NoCase)
            if found == Swag.U64.Max do
                continue

            .showPageOrReport(pageIdx)
            if .pageIndex != pageIdx do
                return false
            .revealMatch(pageIdx, found, @countof(text))
            return true
        }

        return false
    }

    internal const CtxCopy = "Pdf.CtxCopy"
    internal const CtxSelectAll = "Pdf.CtxSelectAll"

    // Selects the word around one offset of the page text, the double-click gesture.
    internal mtd selectWordAt(offset: u64)
    {
        .ensureTextIndex()
        let range = .textIndex.wordRangeAt(offset)
        if range.end <= range.start do
            return
        .selAnchor = range.start
        .selCaret  = range.end
        .selecting = false
        .invalidate()
    }

    // Offers the reading vocabulary at `surfacePos`: what a page can give the clipboard, with
    // the same shortcuts the keyboard already binds.
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
