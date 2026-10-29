#global internal
#global namespace Viewers.Typeface

using Core, Pixel, Gui, TrueType

private
{
    // Air around the document, and the width the pixel-size label reserves beside a specimen line.
    const ContentInset     = 48.0
    const SampleLabelWidth = 40.0

    // The specimen page: the size of its large "Aa", of the family's name, the width of its left
    // column, the air between the two columns, and the pitch of the row of glyphs.
    const SpecimenSize = 160'u32
    const FamilySize   = 28'u32
    const LeftColumn   = 400.0
    const ColumnGap    = 64.0
    const RowGlyphSize = 22'u32
    const RowPitch     = 34.0
    const WideWidth    = 900.0

    // Air between the two bands of the page, between a caption and what it names, and between two
    // specimen lines.
    const SectionGap = 40.0
    const CaptionGap = 18.0
    const SampleGap  = 12.0

    // One character cell: its width, the air between two of them, and the air it keeps inside its own
    // edges. Its height is measured rather than fixed, because it is whatever the glyph and the code
    // label need.
    const CellWidth   = 88.0
    const CellGap     = 8.0
    const CellPadding = 8.0

    // Sizes the document sets its own chrome at, and the sizes the specimen is shown at.
    const NameSize    = 32'u32
    const GlyphSize   = 40'u32
    const CaptionSize = 12'u32
    const CodeSize    = 11'u32
    const SampleCount = 5
    const SampleSizes: [SampleCount] u32 = [64, 36, 22, 15, 11]

    // The glyphs the row under the name shows, those the face maps, and the one chosen in it.
    const RowGlyphs:   [12] rune = ['A', 'g', 'ß', 'é', 'ç', 'Ω', '&', '@', '€', '≠', '→', '3']
    const ChosenGlyph: rune      = 'é'

    const CharacterPageSize = 192'u64
    const FirstCharacter    = 0x20'u32
    const CharacterLimit    = 0x110000'u32
}

// Collects one page of mapped Unicode scalars without materializing the whole character map.
func characterPage(face: *Face, start: u32, pageSize = CharacterPageSize)->{characters: Array'rune, end: u32, hasNext: bool}
{
    var result: #returntype
    var code = Math.max(start, FirstCharacter)
    result.end = code

    while code < CharacterLimit
    {
        let character = cast(rune, code)
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
struct DocumentCell
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
struct DocumentLayout
{
    wide:         bool        // Whether the specimen stands in two columns beside the name.
    aaTop:        f32         // Top of the large "Aa".
    tabsTop:      f32         // Top of the style tabs.
    glyphsTop:    f32         // Top of the glyph-row caption.
    rowTop:       f32         // Top of the row of glyphs.
    glyphNameTop: f32         // Top of the line naming the chosen glyph.
    sampleLeft:   f32         // Left edge of the specimen lines.
    sampleWidth:  f32         // Width the specimen lines may take.
    nameTop:      f32         // Top of the family name.
    metricsTop:   f32         // Top of the style, version, glyph count and units-per-em line.
    noticeTop:    f32         // Top of the designer and copyright line, when the face names either.
    captionTop:   f32         // Top of the specimen caption.
    sampleTops:   [SampleCount] f32     // Top of each specimen line, one per entry of `SampleSizes`.
    mapTop:       f32         // Top of the character-map caption.
    gridTop:      f32         // Top of the first row of cells.
    gridLeft:     f32         // Left edge of the first column.
    cellHeight:   f32         // Height one cell needs for its glyph and its code label.
    columns:      u32 = 1     // Cells one row holds.
    rows:         u64         // Rows the loaded page fills.
    height:       f32         // Total content height, which is what the scrollbar is given.
}

// Scrollable specimen and Unicode character map drawn with the inspected face.
struct DocumentView
{
    using wnd: Wnd

    late
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
    face:      *Face?

    cells:     Array'DocumentCell
    layout:    DocumentLayout
    history:   Array'u32
    pageStart: u32
    pageEnd:   u32
    hasNext:   bool
}

private impl DocumentView
{
    // Returns the face's version without the build details some foundries append after a
    // semicolon, such as `Version 1.000;PS 1.0;hotconv`.
    mtd versionText()->string
    {
        let version = .face!.version.toString()
        let end     = Utf8.indexOf(version, ";")
        return Latin1.trim(end == Swag.U64.Max ? version : version[until end])
    }

    // Returns the designer and the first copyright notice the face carries, joined on one line.
    //
    // A face often stacks several notices separated by line breaks, tabs, or runs of spaces; the
    // first is the one that names the face, and a long one is cut so it never runs off the page.
    mtd noticeText()->String
    {
        const NoticeLimit = 120'u64
        let source = .face!.copyright.toString()
        var end    = source.count
        for index in source.count
        {
            let byte = source[index]
            if byte == '\n' or
               byte == '\r' or
               byte == '\t' or
               (byte == ' ' and index + 1 < source.count and source[index + 1] == ' ')
            {
                end = index
                break
            }
        }

        var copyright = Latin1.trim(source[until Math.min(end, NoticeLimit)])
        let designer  = Latin1.trim(.face.designer.toString())

        var result: #returntype
        if designer.count do
            result += designer
        if copyright.count
        {
            if result.count do
                result += " · "
            result += copyright
            if end > NoticeLimit do
                result += "…"
        }

        return result
    }

    // Returns the view the inspected face is drawn at for one specimen size.
    //
    // A font cache hands out views of shared glyph storage and walks a handful of entries to do it,
    // so resolving one on the draw path costs a lookup and no allocation. Caching four of them in
    // the view would only duplicate `SampleSizes` in a second place.
    mtd sampleFont(size: u32)->*Font => .app().renderer.fontCache().createFont(.typeFace, size)

    // Paints the specimen page: a large "Aa" in the face, the family's name over its identity and
    // its style as a tab, the row of glyphs with the chosen one on the Arc ground and its code,
    // then the sample text at each of `SampleSizes`, each led by its size in mono — beside that
    // column on a wide page, under it otherwise.
    mtd paintSpecimen(painter: *Painter)
    {
        let colors = .themeColors()
        let family = .face!.familyName
        let style  = .face.styleName.isEmpty() ? texts().ui_Regular : .face.styleName.toString()
        let left   = ContentInset

        painter.drawString(left - 4, .layout.aaTop, "Aa", .sampleFont(SpecimenSize), colors.text)
        let familyFont = .theme().createDefaultFont(FamilySize, .Bold)
        painter.drawString(left, .layout.nameTop, family, familyFont, colors.text)
        let version  = .versionText()
        let identity = version.count ? Format.toString("TrueType · %", version) : String.from("TrueType")
        let metrics  = Format.toString(texts().ui_Metrics, identity, .face.glyphCount, .face.unitsPerEm)
        painter.drawString(left, .layout.metricsTop, metrics, .fontCode, colors.faintText)

        // The style is a tab, the one in use.
        let tabFont  = .theme().createDefaultFont(13)
        let tabWidth = Painter.measureString(style, tabFont).width
        painter.drawString(left, tabFont.opticalLineTop(.layout.tabsTop + 10), style, tabFont, colors.text)
        painter.fillRect(Math.Rectangle{left, .layout.tabsTop + 22, tabWidth, 2}, colors.arc)

        // The row of glyphs, the chosen one on the Arc ground.
        SectionLabel.paint(me, painter, Math.Rectangle{left, .layout.glyphsTop, LeftColumn, .fontLabel.height}, texts().ui_Glyphs)
        let glyphFont = .sampleFont(RowGlyphSize)
        let radius    = .themeMetrics().corner_Control
        var x         = left
        var chosen    = Swag.U32.Max
        for glyph in RowGlyphs where .face.hasChar(glyph)
        {
            var text: String
            text.append(glyph)
            let width = Math.max(Painter.measureString(text, glyphFont).width, 14)
            if x + width > left + LeftColumn do
                break
            let cell = Math.Rectangle{x - 6, .layout.rowTop, width + 12, RowPitch}
            if glyph == ChosenGlyph or (chosen == Swag.U32.Max and glyph == RowGlyphs[0] and not .face.hasChar(ChosenGlyph))
            {
                chosen = cast(u32, glyph)
                painter.fillRoundRect(cell, radius, radius, colors.selection)
            }

            painter.drawString(x, glyphFont.opticalLineTop(cell.vertCenter()), text, glyphFont, colors.text)
            x += width + 18
        }

        if chosen != Swag.U32.Max
        {
            var text: String
            text.append(cast(rune, chosen))
            let line = Format.toString("% · U+%{X04}", text, chosen)
            painter.drawString(left, .layout.glyphNameTop, line, .fontCode, colors.faintText)
        }

        // The sample at each size, its size in mono before it.
        let sample = .sampleEdit.text()
        painter.pushClippingRect(Math.Rectangle{.layout.sampleLeft, 0, .layout.sampleWidth + SampleLabelWidth, .layout.mapTop})
        for size, index in SampleSizes
        {
            let top      = .layout.sampleTops[index]
            let font     = .sampleFont(size)
            let sizeText = Format.toString("%", size)
            painter.drawString(.layout.sampleLeft, font.opticalLineTop(top + font.height * 0.5) + (font.height - .fontCode.height) * 0.35, sizeText, .fontCode, colors.faintText)
            painter.drawString(.layout.sampleLeft + SampleLabelWidth, top, sample, font, colors.text)
        }

        painter.popClippingRect()
    }

    // Draws the cells the viewport crosses, `band` being the document band it shows.
    mtd paintCharacterMap(painter: *Painter, band: Math.Rectangle)
    {
        let colors = .themeColors()
        painter.drawString(ContentInset, .layout.mapTop, texts().ui_CharacterMap, .fontLabel, colors.label_TextFaint)

        if .cells.isEmpty()
        {
            painter.drawString(ContentInset, .layout.gridTop, texts().ui_NoCharacters, .fontCode, colors.label_TextLight)
            return
        }

        // A page holds far more cells than a viewport shows, so the band names the rows to draw
        // instead of the loop walking every cell to reject it.
        let pitch = .layout.cellHeight + CellGap
        let first = Math.min(cast(u64, (Math.max(band.y - .layout.gridTop, 0) / pitch)), .layout.rows)
        let last  = Math.min(cast(u64, Math.ceil(Math.max(band.bottom() - .layout.gridTop, 0) / pitch)), .layout.rows)

        let corner = .themeRects().btnIcon_RoundSquareBk.radius
        for row in first until last
        {
            let top = .layout.gridTop + cast(f32, row) * pitch
            for column in .layout.columns
            {
                let index = row * .layout.columns + column
                if index >= .cells.count do
                    break

                let cell = &.cells[index]
                let box  = Math.Rectangle{.layout.gridLeft + cast(f32, column) * (CellWidth + CellGap), top, CellWidth, .layout.cellHeight}
                painter.fillRoundRect(box, corner, corner, colors.wnd_Bk)

                let codeTop   = box.bottom() - CellPadding - .fontCode.height
                let codeWidth = Painter.measureString(cell.code, .fontCode).width
                painter.drawString(box.horzCenter() - codeWidth * 0.5, codeTop, cell.code, .fontCode, colors.label_TextFaint)

                // The glyph is centered on the ink of its own line rather than on its line box, so a
                // face that reserves room for accents it is not showing does not sit low in the cell
                // while a compact one sits high.
                let glyphWidth = Painter.measureString(cell.glyph, .fontGlyph).width
                let glyphTop   = .fontGlyph.opticalLineTop((box.y + CellPadding + codeTop) * 0.5)
                painter.drawString(box.horzCenter() - glyphWidth * 0.5, glyphTop, cell.glyph, .fontGlyph, colors.label_Text)
            }
        }
    }
}

impl IWnd for DocumentView
{
    mtd impl onDestroyEvent(_: *DestroyEvent)
    {
        if .face
        {
            .face.destroy()
            .face = null
        }
    }

    mtd impl onResizeEvent(_: *ResizeEvent)
    {
        if .scroll == null do
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
        .fontLabel = .theme().createDefaultFont(CaptionSize, .Bold)
        .fontCode  = .theme().createDefaultFontFs(CodeSize)
        .refreshLayout()
    }

    mtd impl onKeyEvent(evt: *KeyEvent)
    {
        if evt.kind != .Pressed
        {
            evt.accepted = false
            return
        }

        let line = .layout.cellHeight + CellGap
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

impl DocumentView
{
    // Creates the scrollable specimen of `face` under `parent`, taking ownership of `face` and of
    // the bytes it was loaded from; `sampleEdit` supplies the specimen text.
    func create(parent: *Wnd, face: *Face, typeFace: *TypeFace, fontBytes: #move Array'u8, sampleEdit: *EditBox)->*DocumentView
    {
        with let scroll = Wnd.create'ScrollWnd(parent, "scope.font.scroll", {})
        {
            .dockStyle = .Center
            .updateFlags(.TransparentBars | .DisableHorizontal)
        }

        with let result = scroll.createView'DocumentView()
        {
            .scroll          = scroll
            .fontBytes       = #move fontBytes
            .face            = face
            .typeFace        = typeFace
            .sampleEdit      = sampleEdit
            .backgroundStyle = .View
            .focusPolicy     = .Tab
            .wndFlags        |= WndFlags.NoFocusRing | WndFlags.ClipChildren
        }

        let cache = result.app().renderer.fontCache()
        result.fontName  = cache.createFont(typeFace, NameSize)
        result.fontGlyph = cache.createFont(typeFace, GlyphSize)
        result.fontLabel = result.theme().createDefaultFont(CaptionSize, .Bold)
        result.fontCode  = result.theme().createDefaultFontFs(CodeSize)

        result.loadPage(FirstCharacter)
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
        let client = .clientRect()
        .layout.wide = client.width >= WideWidth

        // The left column: "Aa", the name, the identity, the style, the row of glyphs.
        // The "Aa" stands on its own ink: the room a face keeps above its capitals is left out.
        let aa = .sampleFont(SpecimenSize)
        var y  = ContentInset
        .layout.aaTop        = y - Math.round(aa.height * 0.2)
        y                    = .layout.aaTop + aa.height
        .layout.nameTop      = y
        y                    += .theme().createDefaultFont(FamilySize, .Bold).height
        .layout.metricsTop   = y + 2
        y                    += .fontCode.height + 18
        .layout.tabsTop      = y
        y                    += 24 + 28
        .layout.glyphsTop    = y
        y                    += .fontLabel.height + 8
        .layout.rowTop       = y
        y                    += RowPitch + 8
        .layout.glyphNameTop = y
        y                    += .fontCode.height
        let leftBottom = y

        // The specimen lines: beside the column on a wide page, under it otherwise.
        if .layout.wide
        {
            .layout.sampleLeft  = ContentInset + LeftColumn + ColumnGap
            .layout.sampleWidth = Math.max(client.width - .layout.sampleLeft - SampleLabelWidth - ContentInset, 120)
            y = ContentInset + 16
        }
        else
        {
            .layout.sampleLeft  = ContentInset
            .layout.sampleWidth = Math.max(client.width - 2 * ContentInset - SampleLabelWidth, 120)
            y = leftBottom + SectionGap
        }

        for size, index in SampleSizes
        {
            .layout.sampleTops[index] = y
            y += .sampleFont(size).height + SampleGap
        }

        y = Math.max(y - SampleGap, leftBottom)
        .layout.captionTop = 0
        .layout.mapTop     = y + SectionGap
        .layout.gridTop    = .layout.mapTop + .fontLabel.height + CaptionGap
        .layout.cellHeight = 3 * CellPadding + .fontGlyph.height + .fontCode.height

        let usable = Math.max(client.width - 2 * ContentInset, CellWidth)
        .layout.columns = Math.max(1, cast(u32, ((usable + CellGap) / (CellWidth + CellGap))))
        .layout.rows    = (.cells.count + .layout.columns - 1) / .layout.columns

        // The grid starts on the same edge as the name, so the page reads as one column.
        .layout.gridLeft = ContentInset

        var grid = .fontCode.height
        if .layout.rows do
            grid = cast(f32, .layout.rows) * (.layout.cellHeight + CellGap) - CellGap
        .layout.height = .layout.gridTop + grid + ContentInset

        .scroll.setScrollSize(0, .layout.height)
        .invalidate()
    }

    // Shows the page of mapped characters that begins at or after `start`, one cell per character.
    mtd loadPage(start: u32)
    {
        let page = characterPage(unwrap .face, start)
        .pageStart = not page.characters.isEmpty() ? cast(u32, page.characters[0]) : start
        .pageEnd   = page.end
        .hasNext   = page.hasNext

        .cells.clear()
        .cells.reserve(page.characters.count)
        for character in page.characters
        {
            var cell: DocumentCell
            cell.character = character
            cell.glyph.append(character)
            cell.code = Format.toString("U+%{X04}", cast(u32, character))
            .cells.add(#move cell)
        }

        .refreshLayout()
    }

    mtd nextPage()
    {
        if not .hasNext do
            return
        .history.add(.pageStart)
        .loadPage(.pageEnd + 1)
        .revealCharacterMap()
    }

    mtd previousPage()
    {
        if .history.isEmpty() do
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
        .scroll.setScrollPos(0, .layout.mapTop - CaptionGap)
    }
}
