#global internal

using Core, Pixel, Gui, TrueType

// Air around the document, and the width the pixel-size label reserves beside a specimen line.
private const FontContentInset     = 32.0
private const FontSampleLabelWidth = 48.0

// Air between the two bands of the page, between a caption and what it names, and between two
// specimen lines.
private const FontSectionGap = 40.0
private const FontCaptionGap = 18.0
private const FontSampleGap  = 12.0

// One character cell: its width, the air between two of them, and the air it keeps inside its own
// edges. Its height is measured rather than fixed, because it is whatever the glyph and the code
// label need.
private const FontCellWidth   = 88.0
private const FontCellGap     = 8.0
private const FontCellPadding = 8.0

// Sizes the document sets its own chrome at, and the sizes the specimen is shown at.
private const FontNameSize    = 32'u32
private const FontGlyphSize   = 40'u32
private const FontCaptionSize = 12'u32
private const FontCodeSize    = 11'u32
private const FontSampleCount = 4
private const FontSampleSizes: [FontSampleCount] u32 = [22, 32, 46, 64]

private const FontCharacterPageSize = 192'u64
private const FontFirstCharacter    = 0x20'u32
private const FontCharacterLimit    = 0x110000'u32

// Collects one page of mapped Unicode scalars without materializing the whole character map.
internal func fontCharacterPage(face: *Face, start: u32, pageSize = FontCharacterPageSize)->{characters: Array'rune, end: u32, hasNext: bool}
{
    var result: retval
    var code = Math.max(start, FontFirstCharacter)
    result.end = code

    while code < FontCharacterLimit
    {
        let character = cast(rune) code
        if Utf8.isValidRune(character) and face.hasChar(character)
        {
            if result.characters.count == pageSize
            {
                result.hasNext = true
                break
            }

            result.characters.add(character)
            result.end = code
        }

        code += 1
    }

    return result
}

// One character of the loaded page, with the two texts its cell is drawn from.
//
// The texts are built when the page loads rather than when a cell is painted: the map repaints on
// every scroll notch, and formatting a page of code points again per frame would make scrolling
// allocate.
internal struct FontDocumentCell
{
    character: rune
    glyph:     String
    code:      String
}

// Where each band of the page sits, in content coordinates.
//
// The page is measured rather than assembled from fixed offsets. A specimen line is as tall as the
// face makes it at that size, so the character map below can only be placed once the lines above
// have been measured; a constant would work for one face and let a tall one overlap.
internal struct FontDocumentLayout
{
    nameTop:    f32                       // Top of the family name.
    metricsTop: f32                       // Top of the style, glyph count and units-per-em line.
    captionTop: f32                       // Top of the specimen caption.
    sampleTops: [FontSampleCount] f32     // Top of each specimen line, one per entry of `FontSampleSizes`.
    mapTop:     f32                       // Top of the character-map caption.
    gridTop:    f32                       // Top of the first row of cells.
    gridLeft:   f32                       // Left edge of the first column.
    cellHeight: f32                       // Height one cell needs for its glyph and its code label.
    columns:    u32 = 1                   // Cells one row holds.
    rows:       u64                       // Rows the loaded page fills.
    height:     f32                       // Total content height, which is what the scrollbar is given.
}

// Scrollable specimen and Unicode character map drawn with the inspected face.
internal struct FontDocumentView
{
    using wnd: Wnd

    #[Swag.Late]
    {
        scroll:     *ScrollWnd
        typeFace:   *TypeFace
        sampleEdit: *EditBox
        fontName:   *Font
        fontGlyph:  *Font
        fontLabel:  *Font
        fontCode:   *Font
    }

    fontBytes: Array'u8
    face:      #null *Face

    cells:     Array'FontDocumentCell
    layout:    FontDocumentLayout
    history:   Array'u32
    pageStart: u32
    pageEnd:   u32
    hasNext:   bool
}

private impl FontDocumentView
{
    // Returns the view the inspected face is drawn at for one specimen size.
    //
    // A font cache hands out views of shared glyph storage and walks a handful of entries to do it,
    // so resolving one on the draw path costs a lookup and no allocation. Caching four of them in
    // the view would only duplicate `FontSampleSizes` in a second place.
    mtd sampleFont(size: u32)->*Font
    {
        return .app().renderer.fontCache().createFont(.typeFace, size)
    }

    mtd paintSpecimen(painter: *Painter)
    {
        let colors = .themeColors()
        let family = .face!.familyName
        let style  = .face!.styleName.isEmpty() ? fontStrings().ui_Regular : .face!.styleName.toString()

        painter.drawString(FontContentInset, .layout.nameTop, family.toString(), .fontName, colors.label_Text)
        let metrics = Format.toString(fontStrings().ui_Metrics, style, .face!.glyphCount, .face!.unitsPerEm)
        painter.drawString(FontContentInset, .layout.metricsTop, metrics.toString(), .fontCode, colors.label_TextFaint)
        painter.drawString(FontContentInset, .layout.captionTop, fontStrings().ui_Specimen, .fontLabel, colors.label_TextFaint)

        let sample = .sampleEdit.text()
        for size, index in FontSampleSizes
        {
            let top      = .layout.sampleTops[index]
            let sizeText = Format.toString("% px", size)
            painter.drawString(FontContentInset, top + FontCellPadding, sizeText.toString(), .fontCode, colors.label_TextFaint)
            painter.drawString(FontContentInset + FontSampleLabelWidth, top, sample, .sampleFont(size), colors.label_Text)
        }
    }

    // Draws the cells the viewport crosses, `band` being the document band it shows.
    mtd paintCharacterMap(painter: *Painter, band: Math.Rectangle)
    {
        let colors = .themeColors()
        painter.drawString(FontContentInset, .layout.mapTop, fontStrings().ui_CharacterMap, .fontLabel, colors.label_TextFaint)

        if !.cells.count
        {
            painter.drawString(FontContentInset, .layout.gridTop, fontStrings().ui_NoCharacters, .fontCode, colors.label_TextLight)
            return
        }

        // A page holds far more cells than a viewport shows, so the band names the rows to draw
        // instead of the loop walking every cell to reject it.
        let pitch = .layout.cellHeight + FontCellGap
        let first = Math.min(cast(u64) (Math.max(band.y - .layout.gridTop, 0) / pitch), .layout.rows)
        let last  = Math.min(cast(u64) Math.ceil(Math.max(band.bottom() - .layout.gridTop, 0) / pitch), .layout.rows)

        let corner = .themeRects().btnIcon_RoundSquareBk.radius
        for row in first until last
        {
            let top = .layout.gridTop + cast(f32) row * pitch
            for column in .layout.columns
            {
                let index = row * .layout.columns + column
                if index >= .cells.count do
                    break

                let cell = &.cells[index]
                let box  = Math.Rectangle{.layout.gridLeft + cast(f32) column * (FontCellWidth + FontCellGap), top, FontCellWidth, .layout.cellHeight}
                painter.fillRoundRect(box, corner, corner, colors.wnd_Bk)

                let codeTop   = box.bottom() - FontCellPadding - .fontCode.height
                let codeWidth = Painter.measureString(cell.code.toString(), .fontCode).width
                painter.drawString(box.horzCenter() - codeWidth * 0.5, codeTop, cell.code.toString(), .fontCode, colors.label_TextFaint)

                // The glyph is centered on the ink of its own line rather than on its line box, so a
                // face that reserves room for accents it is not showing does not sit low in the cell
                // while a compact one sits high.
                let glyphWidth = Painter.measureString(cell.glyph.toString(), .fontGlyph).width
                let glyphTop   = .fontGlyph.opticalLineTop((box.y + FontCellPadding + codeTop) * 0.5)
                painter.drawString(box.horzCenter() - glyphWidth * 0.5, glyphTop, cell.glyph.toString(), .fontGlyph, colors.label_Text)
            }
        }
    }
}

internal impl IWnd for FontDocumentView
{
    mtd impl onDestroyEvent(evt: *DestroyEvent)
    {
        discard evt
        if .face
        {
            .face!.destroy()
            .face = null
        }
    }

    mtd impl onResizeEvent(evt: *ResizeEvent)
    {
        discard evt
        if !Swag.isSet(.scroll) do
            return
        .refreshLayout()
    }

    mtd impl onNotifyEvent(evt: *NotifyEvent)
    {
        if evt.kind != .ThemeChanged
        {
            evt.accepted = false
            return
        }

        // Both captions and every code label are set in the theme's own faces, so a theme change
        // replaces them and moves every band measured under them.
        .fontLabel = .theme().createDefaultFont(FontCaptionSize, .Bold)
        .fontCode  = .theme().createDefaultFontFS(FontCodeSize)
        .refreshLayout()
    }

    mtd impl onKeyEvent(evt: *KeyEvent)
    {
        if evt.kind != .Pressed
        {
            evt.accepted = false
            return
        }

        let line = .layout.cellHeight + FontCellGap
        let page = Math.max(.clientRect().height - line, line)
        switch evt.key
        {
        case .Up:       .scroll.setScrollPos(0, .scrollPos.y - line)
        case .Down:     .scroll.setScrollPos(0, .scrollPos.y + line)
        case .PageUp:   .scroll.setScrollPos(0, .scrollPos.y - page)
        case .PageDown: .scroll.setScrollPos(0, .scrollPos.y + page)
        case .Home:     .scroll.setScrollPos(0, 0)
        case .End:      .scroll.setScrollPos(0, .layout.height)
        default:        evt.accepted = false
        }
    }

    mtd impl onPaint(evt: *PaintEvent)
    {
        // The paint transform already carries the scroll offset: this view *is* the viewport, and
        // the host translates it by [[Gui.Wnd.scrollPos]] before the content event. Everything below
        // therefore draws in document coordinates, and the position is read only to know which band
        // of the document the viewport is showing.
        let painter = evt.paintContext.painter
        var band    = .clientRect()
        band.offset(.scrollPos)

        painter.setParams(.Antialiased)
        if band.y < .layout.mapTop do
            .paintSpecimen(painter)
        .paintCharacterMap(painter, band)
    }
}

internal impl FontDocumentView
{
    func create(parent: *Wnd, face: *Face, typeFace: *TypeFace, fontBytes: Array'u8, sampleEdit: *EditBox)->*FontDocumentView
    {
        let scroll = Wnd.create'ScrollWnd(parent, "scope.font.scroll", {})
        scroll.dockStyle = .Center
        scroll.updateFlags(.CompactBars | .TransparentBars | .DisableHorizontal)

        let result = scroll.createView'FontDocumentView()
        result.scroll          = scroll
        result.fontBytes       = #move fontBytes
        result.face            = face
        result.typeFace        = typeFace
        result.sampleEdit      = sampleEdit
        result.backgroundStyle = .View
        result.focusPolicy     = .Tab
        result.wndFlags        |= WndFlags.NoFocusRing | WndFlags.ClipChildren

        let cache = result.app().renderer.fontCache()
        result.fontName  = cache.createFont(typeFace, FontNameSize)
        result.fontGlyph = cache.createFont(typeFace, FontGlyphSize)
        result.fontLabel = result.theme().createDefaultFont(FontCaptionSize, .Bold)
        result.fontCode  = result.theme().createDefaultFontFS(FontCodeSize)

        result.loadPage(FontFirstCharacter)
        return result
    }

    // Reports whether the loaded page maps `character`.
    mtd hasCharacter(character: rune)->bool
    {
        for cell in .cells where cell.character == character do
            return true
        return false
    }

    // Measures every band of the page for the current width, then republishes the scrollable height.
    mtd refreshLayout()
    {
        var y = FontContentInset
        .layout.nameTop = y
        y               += .fontName.height

        .layout.metricsTop = y
        y += .fontCode.height + FontSectionGap

        .layout.captionTop = y
        y += .fontLabel.height + FontCaptionGap

        for size, index in FontSampleSizes
        {
            .layout.sampleTops[index] = y
            y += .sampleFont(size).height + FontSampleGap
        }

        .layout.mapTop     = y - FontSampleGap + FontSectionGap
        .layout.gridTop    = .layout.mapTop + .fontLabel.height + FontCaptionGap
        .layout.cellHeight = 3 * FontCellPadding + .fontGlyph.height + .fontCode.height

        let client = .clientRect()
        let usable = Math.max(client.width - 2 * FontContentInset, FontCellWidth)
        .layout.columns = Math.max(1, cast(u32) ((usable + FontCellGap) / (FontCellWidth + FontCellGap)))
        .layout.rows    = (.cells.count + .layout.columns - 1) / .layout.columns

        let gridWidth = cast(f32) .layout.columns * FontCellWidth + cast(f32) (.layout.columns - 1) * FontCellGap
        .layout.gridLeft = Math.max(FontContentInset, (client.width - gridWidth) * 0.5)

        var grid = .fontCode.height
        if .layout.rows do
            grid = cast(f32) .layout.rows * (.layout.cellHeight + FontCellGap) - FontCellGap
        .layout.height = .layout.gridTop + grid + FontContentInset

        .scroll.setScrollSize(0, .layout.height)
        .invalidate()
    }

    mtd loadPage(start: u32)
    {
        let page = fontCharacterPage(.face!, start)
        .pageStart = page.characters.count ? cast(u32) page.characters[0] : start
        .pageEnd   = page.end
        .hasNext   = page.hasNext

        .cells.clear()
        .cells.reserve(page.characters.count)
        for character in page.characters
        {
            var cell: FontDocumentCell
            cell.character = character
            cell.glyph.append(character)
            cell.code = Format.toString("U+%{X04}", cast(u32) character)
            .cells.add(#move cell)
        }

        .refreshLayout()
    }

    mtd nextPage()
    {
        if !.hasNext do
            return
        .history.add(.pageStart)
        .loadPage(.pageEnd + 1)
        .revealCharacterMap()
    }

    mtd previousPage()
    {
        if !.history.count do
            return
        .loadPage(.history.popBack())
        .revealCharacterMap()
    }

    mtd goToCharacterPage(start: u32)
    {
        if start != .pageStart do
            .history.add(.pageStart)
        .loadPage(start)
        .revealCharacterMap()
    }

    // Brings the character-map caption to the top of the viewport, which is where a reader who just
    // turned a page is looking.
    mtd revealCharacterMap()
    {
        .scroll.setScrollPos(0, .layout.mapTop - FontCaptionGap)
    }
}
