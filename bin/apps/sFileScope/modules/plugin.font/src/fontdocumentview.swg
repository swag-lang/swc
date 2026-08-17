#global public

using Core, Pixel, Gui, TrueType

private const FontContentInset = 32.0
private const FontSampleLabelWidth = 48.0
private const FontSpecimenTop = 144.0
private const FontCharacterMapTop = 432.0
private const FontGridTop = 468.0
private const FontCellWidth = 88.0
private const FontCellHeight = 92.0
private const FontCellGap = 8.0
private const FontCharacterPageSize = 192'u64
private const FontFirstCharacter = 0x20'u32
private const FontCharacterLimit = 0x110000'u32
private const FontSampleSizes: [4] u32 = [22, 32, 46, 64]

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
        font22:     *Font
        font32:     *Font
        font46:     *Font
        font64:     *Font
        fontGlyph:  *Font
        fontLabel:  *Font
        fontCode:   *Font
    }

    fontBytes: Array'u8
    face:      #null *Face

    characters: Array'rune
    history:    Array'u32
    pageStart:  u32
    pageEnd:    u32
    hasNext:    bool
}

private impl FontDocumentView
{
    mtd sampleFont(index: u32)->*Font
    {
        switch index
        {
        case 0:  return .font22
        case 1:  return .font32
        case 2:  return .font46
        default: return .font64
        }
    }

    mtd columnCount()->u32
    {
        let usable = Math.max(.clientRect().width - 2 * FontContentInset, FontCellWidth)
        return Math.max(1, cast(u32) ((usable + FontCellGap) / (FontCellWidth + FontCellGap)))
    }

    mtd contentHeight()->f32
    {
        let columns = .columnCount()
        let rows    = (.characters.count + columns - 1) / columns
        return FontGridTop + cast(f32) rows * (FontCellHeight + FontCellGap) + FontContentInset
    }

    mtd refreshLayout()
    {
        .scroll.setScrollSize(0, .contentHeight())
        .invalidate()
    }

    mtd runeText(character: rune)->String
    {
        var result: retval
        result.append(character)
        return result
    }

    mtd paintSpecimen(painter: *Painter, scrollY: f32)
    {
        let colors = .themeColors()
        let family = .face!.familyName
        let style  = .face!.styleName.isEmpty() ? fontStrings().ui_Regular : .face!.styleName.toString()

        painter.drawString(FontContentInset, FontContentInset - scrollY, family.toString(), .fontName, colors.label_Text)
        let metrics = Format.toString(fontStrings().ui_Metrics, style, .face!.glyphCount, .face!.unitsPerEm)
        painter.drawString(FontContentInset, 76 - scrollY, metrics.toString(), .fontCode, colors.label_TextFaint)
        painter.drawString(FontContentInset, 112 - scrollY, fontStrings().ui_Specimen, .fontLabel, colors.label_TextFaint)

        let sample = .sampleEdit.text()
        var y      = FontSpecimenTop
        for size in FontSampleSizes
        {
            let sizeText = Format.toString("% px", size)
            painter.drawString(FontContentInset, y + 8 - scrollY, sizeText.toString(), .fontCode, colors.label_TextFaint)
            painter.drawString(FontContentInset + FontSampleLabelWidth, y - scrollY, sample, .sampleFont(cast(u32) @index), colors.label_Text)
            y += Math.max(cast(f32) size * 1.3, 32) + 12
        }
    }

    mtd paintCharacterMap(painter: *Painter, scrollY: f32)
    {
        let client = .clientRect()
        let colors = .themeColors()
        let titleY = FontCharacterMapTop - scrollY
        painter.drawString(FontContentInset, titleY, fontStrings().ui_CharacterMap, .fontLabel, colors.label_TextFaint)

        if !.characters.count
        {
            painter.drawString(FontContentInset, FontGridTop - scrollY, fontStrings().ui_NoCharacters, .fontCode, colors.label_TextLight)
            return
        }

        let columns = .columnCount()
        let width   = cast(f32) columns * FontCellWidth + cast(f32) (columns - 1) * FontCellGap
        let left    = Math.max(FontContentInset, (client.width - width) * 0.5)
        let corner  = .themeRects().btnIcon_RoundSquareBk.radius

        for character in .characters
        {
            let row = @index / columns
            let col = @index % columns
            let x   = left + cast(f32) col * (FontCellWidth + FontCellGap)
            let y   = FontGridTop + cast(f32) row * (FontCellHeight + FontCellGap) - scrollY
            if y + FontCellHeight < 0 do
                continue
            if y > client.height do
                break

            let cell = Math.Rectangle{x, y, FontCellWidth, FontCellHeight}
            painter.fillRoundRect(cell, corner, corner, colors.wnd_Bk)

            let glyph      = .runeText(character)
            let glyphWidth = Painter.measureString(glyph.toString(), .fontGlyph).width
            painter.drawString(cell.horzCenter() - glyphWidth * 0.5, y + 8, glyph.toString(), .fontGlyph, colors.label_Text)

            let code      = Format.toString("U+%{X04}", cast(u32) character)
            let codeWidth = Painter.measureString(code.toString(), .fontCode).width
            painter.drawString(cell.horzCenter() - codeWidth * 0.5, cell.bottom() - .fontCode.height - 8, code.toString(), .fontCode, colors.label_TextFaint)
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
        if !@isset(.scroll) do
            return
        .refreshLayout()
    }

    mtd impl onKeyEvent(evt: *KeyEvent)
    {
        if evt.kind != .Pressed
        {
            evt.accepted = false
            return
        }

        let page = Math.max(.clientRect().height - 48, 48)
        switch evt.key
        {
        case .PageUp:   .scroll.setScrollPos(0, .scroll.scrollPosition().y - page)
        case .PageDown: .scroll.setScrollPos(0, .scroll.scrollPosition().y + page)
        case .Home:     .scroll.setScrollPos(0, 0)
        case .End:      .scroll.setScrollPos(0, .contentHeight())
        default:        evt.accepted = false
        }
    }

    mtd impl onPaint(evt: *PaintEvent)
    {
        let painter = evt.paintContext.painter
        let scrollY = .scroll.scrollPosition().y
        painter.setParams(.Antialiased)
        .paintSpecimen(painter, scrollY)
        .paintCharacterMap(painter, scrollY)
    }
}

internal impl FontDocumentView
{
    func create(parent: *Wnd, face: *Face, typeFace: *TypeFace, fontBytes: Array'u8, sampleEdit: *EditBox)->*FontDocumentView
    {
        let scroll = Wnd.create'ScrollWnd(parent, "sFileScope.font.scroll", {})
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
        result.fontName  = cache.createFont(typeFace, 32)
        result.font22    = cache.createFont(typeFace, 22)
        result.font32    = cache.createFont(typeFace, 32)
        result.font46    = cache.createFont(typeFace, 46)
        result.font64    = cache.createFont(typeFace, 64)
        result.fontGlyph = cache.createFont(typeFace, 40)
        result.fontLabel = result.theme().createDefaultFont(12, .Bold)
        result.fontCode  = result.theme().createDefaultFontFS(11)

        result.loadPage(FontFirstCharacter)
        return result
    }

    mtd loadPage(start: u32)
    {
        var page = fontCharacterPage(.face!, start)
        .characters = #move page.characters
        .pageStart  = .characters.count ? cast(u32) .characters[0] : start
        .pageEnd    = page.end
        .hasNext    = page.hasNext
        .refreshLayout()
    }

    mtd nextPage()
    {
        if !.hasNext do
            return
        .history.add(.pageStart)
        .loadPage(.pageEnd + 1)
        .scroll.setScrollPos(0, FontCharacterMapTop - 16)
    }

    mtd previousPage()
    {
        if !.history.count do
            return
        .loadPage(.history.popBack())
        .scroll.setScrollPos(0, FontCharacterMapTop - 16)
    }
}
