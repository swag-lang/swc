#global public
using Core

enum StringHorzAlignment
{
    Center
    Left
    Right
    Justify
}

enum StringVertAlignment
{
    Center
    Top
    Bottom
}

enum UnderlineStyle
{
    None
    Underline
    Strikeout
}

#[Swag.EnumFlags]
enum StringFormatFlags
{
    Default
    WordWrap
    Clip
    DontAdaptSingleLineHeight
}

struct StringMetrics
{
    ascent:      f32     // Maximum size above baseline
    descent:     f32     // Maximum size below baseline
    width:       f32
    height:      f32     // ascent + descent
}

struct ShapedGlyph
{
    desc:        const *GlyphDesc
    glyphIndex:  u32
    cluster:     u64
    advanceX:    f32
    advanceY:    f32
    offsetX:     f32
    offsetY:     f32
}

struct ShapedRun
{
    font:        *Font
    glyphs:      Array'ShapedGlyph
    metrics:     StringMetrics
}

struct RichStringFormat
{
    font:              FontFamily
    fontStyle:         FontFamilyStyle = Regular
    palette:           [4] Color                       // Color of text between <p?>...<p?> markers
    colorUrl:          Color = Color.fromArgb(Argb.White)              // Color of text between <url>...<url> markers
    colorHotUrl:       Color = Color.fromArgb(Argb.Blue)               // Color of text between <url>...<url> markers when mouse is inside
    brush:             Brush
    horzAlignment:     StringHorzAlignment = Left
    vertAlignment:     StringVertAlignment = Top
    lineGap:           s32
    flags:             StringFormatFlags = Default
    justifyLimit:      f32 = 2
}

fileprivate func appendShapedGlyph(run: *ShapedRun, font: *Font, glyphIndex: u32, cluster: u64, previousGlyphIndex: u32)
{
    var glyph: ShapedGlyph
    glyph.desc       = font.getGlyphDescByIndex(glyphIndex)
    glyph.glyphIndex = glyphIndex
    glyph.cluster    = cluster
    glyph.advanceX   = glyph.desc.advanceX
    glyph.advanceY   = glyph.desc.advanceY
    if previousGlyphIndex do
        glyph.offsetX = font.cache.kerning(previousGlyphIndex, glyphIndex)

    if run.glyphs.isEmpty()
    {
        run.metrics.ascent  = glyph.desc.shiftY
        run.metrics.descent = glyph.desc.height - glyph.desc.shiftY
    }
    else
    {
        run.metrics.ascent  = Math.max(run.metrics.ascent, glyph.desc.shiftY)
        run.metrics.descent = Math.max(run.metrics.descent, glyph.desc.height - glyph.desc.shiftY)
    }

    run.metrics.width += glyph.offsetX + glyph.advanceX
    run.glyphs.add(glyph)
}

fileprivate func finishShapedRun(run: *ShapedRun, font: *Font)
{
    if run.glyphs.isEmpty() do
        return

    let sc = font.scale()
    run.metrics.ascent  *= sc
    run.metrics.descent *= sc
    run.metrics.width   *= sc
    run.metrics.height = run.metrics.ascent + run.metrics.descent
}

impl Painter
{
    // Shape a single-font text run. This currently preserves the legacy one-rune
    // to one-glyph behavior, but stores glyph indexes, advances and cluster
    // positions so GSUB/GPOS, fallback and bidi can be introduced at this layer.
    func shapeRun(text: string, font: *Font)->ShapedRun
    {
        Debug.assert(font != null, "invalid font")

        var result: retval
        result.font = font
        result.glyphs.reserve(@countof(text))

        var count = @countof(text)
        var scan = @dataof(text)
        var byteIdx = 0'u64
        var previousGlyphIndex = 0'u32

        while count
        {
            let sl = @mkslice(scan, count)
            let (c, eat) = Utf8.decodeRune(sl)
            if eat == 0 do
                break

            let glyphIndex = font.glyphIndex(c)
            appendShapedGlyph(&result, font, glyphIndex, byteIdx, previousGlyphIndex)
            previousGlyphIndex = glyphIndex

            byteIdx += eat
            scan += eat
            count -= eat
        }

        finishShapedRun(&result, font)
        return result
    }

    // Rebuild a shaped run for another concrete font cache while preserving its
    // glyph sequence and cluster mapping.
    func shapeRunForFont(run: *ShapedRun, font: *Font)->ShapedRun
    {
        Debug.assert(font != null, "invalid font")
        Debug.assert(run.font == null or run.font.cache.typeFace == font.cache.typeFace, "cannot reuse glyph indexes with another typeface")

        var result: retval
        result.font = font
        result.glyphs.reserve(run.glyphs.count)

        var previousGlyphIndex = 0'u32
        foreach glyph in run.glyphs
        {
            appendShapedGlyph(&result, font, glyph.glyphIndex, glyph.cluster, previousGlyphIndex)
            previousGlyphIndex = glyph.glyphIndex
        }

        finishShapedRun(&result, font)
        return result
    }

    // Returns all the glyphs for a given string and font
    func getGlyphs(text: string, font: *Font)->Array'(const *GlyphDesc)
    {
        var result: retval
        result.reserve(@countof(text))
        Utf8.visitRunes(|c| text)
        {
            result.add(font.getGlyphDesc(c))
        }

        return result
    }

    // Returns all the glyphs for a given string and font
    func getGlyphs(text: Array'rune, font: *Font)->Array'(const *GlyphDesc)
    {
        var result: retval
        result.reserve(@countof(text))
        foreach c in text
        {
            result.add(font.getGlyphDesc(c))
        }

        return result
    }

    // Get a rune size for a given font
    func measureRune(c: rune, font: #null *Font)->Math.Point
    {
        var result: retval
        if !font do
            return result
        let localFont = cast(*Font) font
        let desc = localFont.getGlyphDesc(c)
        let sc   = localFont.scale()
        result.x = desc.advanceX * sc
        result.y = (desc.shiftY + desc.height) * sc
        return result
    }

    // Returns the metrics of a given text
    func measureString(text: string, font: *Font)->StringMetrics
    {
        let shaped = shapeRun(text, font)
        return shaped.metrics
    }

    // Returns the metrics of an already shaped text run
    func measureString(text: *ShapedRun)->StringMetrics => text.metrics

    // Returns the bounding rectangle of a given text, scaled to the font draw size
    func measureString(text: Array'(const *GlyphDesc), font: *Font)->StringMetrics
    {
        var result: retval
        result.ascent  = Swag.F32.NegInf
        result.descent = Swag.F32.NegInf
        foreach refr, i in text
        {
            result.ascent  = Math.max(result.ascent, refr.shiftY)
            result.descent = Math.max(result.descent, refr.height - refr.shiftY)
            if i do
                result.width += font.cache.kerning(text[i - 1].glyphIndex, refr.glyphIndex)
            result.width += refr.advanceX
        }

        let sc = font.scale()
        result.ascent  *= sc
        result.descent *= sc
        result.width   *= sc
        result.height = result.ascent + result.descent
        return result
    }

    // Draw an already shaped text run
    mtd drawShapedRun(left, top: f32, shaped: *ShapedRun, font: *Font, brush: Brush, under = UnderlineStyle.None, zoom = 1.0)
    {
        if shaped.glyphs.isEmpty() or !brush.hasVisibleAlpha() do
            return
        if .fake do
            return

        let tr      = .curState.transform
        let trScale = Math.max(Math.sqrt(tr.m11 * tr.m11 + tr.m12 * tr.m12), Math.sqrt(tr.m21 * tr.m21 + tr.m22 * tr.m22))
        let drawFont = Font.resolveDrawFont(font, cast(f32) font.size * zoom * trScale)

        var drawShape: ShapedRun
        var runToDraw: *ShapedRun = shaped
        if shaped.font != drawFont
        {
            drawShape = shapeRunForFont(shaped, drawFont)
            runToDraw = &drawShape
        }

        var x = Math.round(left)
        let y = Math.round(top + font.ascent * zoom)

        switch drawFont.cache.renderMode
        {
        case Msdf:
            .startMsdfFont()
        default:
            .startFont()
        }

        // Set brush main texture
        if brush.type != .SolidColor do
            .setTexture0({x, y - shaped.metrics.ascent * zoom}, {x + shaped.metrics.width * zoom, y + shaped.metrics.height * zoom}, brush)
        else do
            .resetTexture0()

        // Underline
        if under != .None
        {
            var pen = Pen.createSolid(brush.color, Math.max(1, Math.floor(font.underlineSize)))
            pen.begCapStyle = .None
            pen.endCapStyle = .None

            .canSetTexture0 = false
            switch under
            {
            case Strikeout:
                let yUnder = y - (shaped.metrics.ascent * zoom / 2)
                .drawLine(x, yUnder, x + shaped.metrics.width * zoom, yUnder, pen)
            case Underline:
                let yUnder = y - font.underlinePos
                .drawLine(x, yUnder, x + shaped.metrics.width * zoom, yUnder, pen)
            }

            .canSetTexture0 = true
        }

        .updateFont(drawFont)

        // Glyph descriptors are stored at the cache reference size; scale to draw size.
        let sc = drawFont.scale() * zoom

        foreach glyph in runToDraw.glyphs
        {
            let glyphX = x + Math.round(glyph.offsetX * sc)

            let refr = glyph.desc
            .setTextureFont(drawFont, refr.atlasIndex)

            let x1 = Math.round(glyphX + refr.shiftX * sc)
            let y1 = Math.round(y + glyph.offsetY * sc - refr.shiftY * sc)
            let x2 = Math.round(glyphX + (refr.shiftX * sc) + (refr.width * sc))
            let y2 = Math.round(y + glyph.offsetY * sc - (refr.shiftY * sc) + (refr.height * sc))

            let p1 = Math.Vector2{x1, y1}
            let p2 = Math.Vector2{x2, y1}
            let p3 = Math.Vector2{x1, y2}
            let p4 = Math.Vector2{x2, y2}

            let uv1 = Math.Vector2{refr.uv.x, refr.uv.y}
            let uv2 = Math.Vector2{refr.uv.x + refr.uv.width, refr.uv.y}
            let uv3 = Math.Vector2{refr.uv.x, refr.uv.y + refr.uv.height}
            let uv4 = Math.Vector2{refr.uv.x + refr.uv.width, refr.uv.y + refr.uv.height}

            discard .pushTriangle(p1, p2, p3, uv1, uv2, uv3, brush.color)
            discard .pushTriangle(p3, p2, p4, uv3, uv2, uv4, brush.color)

            x = glyphX + Math.round(glyph.advanceX * sc)
        }

        .resetTextureFont()
        .endFont()
    }

    // Draw a simple string (centered)
    mtd drawStringCenter(x, y: f32, text: string, font: *Font, color: Color, under = UnderlineStyle.None, zoom = 1.0)
    {
        let ms = measureString(text, font)
        var yr = y - (ms.height * 0.5 * zoom)
        yr -= (font.ascent - ms.ascent) * zoom
        .drawString(x - (ms.width * 0.5 * zoom), yr, text, font, color, under, zoom)
    }

    // Draw a simple string
    mtd drawString(left, top: f32, text: string, font: *Font, color: Color, under = UnderlineStyle.None, zoom = 1.0)
    {
        if @countof(text) == 0 or color.a == 0 do
            return

        let brush = Brush.createSolid(color)
        .drawString(left, top, text, font, brush, under, zoom)
    }

    // Draw a simple string
    mtd drawString(left, top: f32, text: string, font: *Font, brush: Brush, under = UnderlineStyle.None, zoom = 1.0)
    {
        if @countof(text) == 0 or !brush.hasVisibleAlpha() do
            return
        if .fake do
            return

        var shaped = shapeRun(text, font)
        .drawShapedRun(left, top, &shaped, font, brush, under, zoom)
    }

    // Recompute the layout for a given rectangle
    func computeLayout(pos: Math.Rectangle, text: *RichString, format: RichStringFormat)
    {
        Debug.assert(format.font.regular != null, "invalid default font")
        text.layoutRect = pos

        struct OneLine
        {
            measure:         StringMetrics
            start, end:      s32
            countSpaces:     s32
            whiteSpaces:     f32
            hasEol:          bool
        }

        // Divide in lines
        var lines: Array'OneLine
        var line:  OneLine

        var startLine    = 0
        var lastWasSpace = false

        foreach &c, idx in text.chunks
        {
            // Attributes
            let fs = c.hasFontStyle ? c.fontStyle : format.fontStyle
            c.font = format.font.getFont(fs)

            // Measure
            c.shaped = shapeRun(c.slice, c.font)
            let ms = c.shaped.metrics
            c.boundRect = {0, 0, ms.width, ms.height}

            // User eol
            if c.isEol
            {
                line.start  = startLine
                line.end    = cast(s32) idx
                line.hasEol = true
                lines.add(line)

                startLine = line.end + 1
                line.measure.width, line.measure.height = 0
                line.measure.ascent, line.measure.descent = 0
                line.countSpaces = 0
                line.hasEol      = false
                continue
            }

            // Wrap
            if format.flags & .WordWrap or format.horzAlignment == .Justify
            {
                var curW = line.measure.width
                if format.horzAlignment == .Justify do
                    curW += line.whiteSpaces

                if curW + c.boundRect.width > pos.width
                {
                    if startLine != idx
                    {
                        line.start = startLine
                        line.end   = cast(s32) idx

                        // We: not want the current line to end with a space
                        if lastWasSpace and idx
                        {
                            line.countSpaces -= 1
                            if format.horzAlignment != .Justify do
                                line.measure.width -= text.chunks[idx - 1].boundRect.width
                            else do
                                line.whiteSpaces -= text.chunks[idx - 1].boundRect.width
                            line.end -= 1
                        }

                        lines.add(line)
                    }

                    startLine = cast(s32) idx
                    line.measure.width, line.measure.height = 0
                    line.measure.ascent, line.measure.descent = 0
                    line.countSpaces = 0
                    line.whiteSpaces = 0

                    // We: not want the new line to start with a space
                    if c.isSpace do
                        startLine += 1
                    else
                    {
                        line.measure.width += ms.width
                        line.measure.ascent  = Math.max(line.measure.ascent, ms.ascent)
                        line.measure.descent = Math.max(line.measure.descent, ms.descent)
                        line.measure.height  = Math.max(line.measure.height, ms.height)
                    }

                    continue
                }
            }

            lastWasSpace = c.isSpace
            if c.isSpace
            {
                line.countSpaces += 1
                if format.horzAlignment != .Justify do
                    line.measure.width += ms.width
                else do
                    line.whiteSpaces += ms.width
            }
            else do
                line.measure.width += ms.width
            line.measure.ascent  = Math.max(line.measure.ascent, ms.ascent)
            line.measure.descent = Math.max(line.measure.descent, ms.descent)
            line.measure.height  = Math.max(line.measure.height, ms.height)

            c.boundRect.height = format.font.regular.height
        }

        if startLine != text.chunks.count
        {
            line.start = startLine
            line.end   = cast(s32) text.chunks.count
            lines.add(line)
        }

        let x = text.layoutRect.x
        var y = text.layoutRect.y

        // Vertical
        var totalHeight: f32

        let singleLine = lines.count == 1
        if lines.count > 1
        {
            totalHeight = cast(f32) (lines.count * format.font.regular.height)
            totalHeight += cast(f32) (lines.count - 1) * format.lineGap
        }
        elif singleLine
        {
            if format.flags & .DontAdaptSingleLineHeight do
                totalHeight = format.font.regular.height
            else do
                totalHeight = lines[0].measure.height
        }

        switch format.vertAlignment
        {
        case Bottom:
            y = pos.bottom() - totalHeight
        case Center:
            y = pos.vertCenter() - (totalHeight * 0.5)
        }

        text.boundRect.x      = Swag.F32.Max
        text.boundRect.y      = y
        text.boundRect.width  = 0
        text.boundRect.height = totalHeight

        // Y correction if single line
        if singleLine and !(format.flags & .DontAdaptSingleLineHeight) do
            y -= (format.font.regular.ascent - lines[0].measure.ascent)

        // Layout
        foreach &l, idxLine in lines
        {
            var x1 = x
            let y1 = y

            switch format.horzAlignment
            {
            case Left:
                break
            case Right:
                x1 = pos.right() - l.measure.width
            case Center:
                x1 = pos.horzCenter() - l.measure.width * 0.5
            }

            text.boundRect.x     = Math.min(text.boundRect.x, x1)
            text.boundRect.width = Math.max(text.boundRect.width, l.measure.width)

            if l.end > l.start
            {
                for idx in l.start until l.end
                {
                    let c = &text.chunks[idx]
                    c.pos.x = x1

                    if c.isSpace and format.horzAlignment == .Justify and idxLine != lines.count - 1 and !l.hasEol
                    {
                        let spaceW = (pos.width - l.measure.width) / l.countSpaces
                        if spaceW < l.measure.height * format.justifyLimit do
                            x1 += spaceW
                        else do
                            x1 += c.boundRect.width
                    }
                    else do
                        x1 += c.boundRect.width
                    c.pos.y = y1
                }
            }

            y += format.font.regular.height + format.lineGap
        }
    }

    // Draw a rich string.
    // A rich string can be multiline, and accepts fileprivate formats.
    // The layout will be computed at the first call, and each time 'pos' has changed.
    mtd drawRichString(pos: Math.Rectangle, text: *RichString, format: RichStringFormat, forceCompute = false)
    {
        text.compute()
        if text.chunks.count == 0 do
            return

        // Recompute layout if rectangle has changed
        if text.layoutRect != pos or forceCompute do
            computeLayout(pos, text, format)

        // Clipping
        if format.flags & .Clip
        {
            .pushClippingRect(pos)
            if .curState.clippingRect.isEmpty()
            {
                .popClippingRect()
                return
            }
        }

        // Draw
        var brush = format.brush
        foreach &c in text.chunks
        {
            if c.isEol do
                continue

            if c.isHotUrl do
                brush.color = format.colorHotUrl
            elif c.isUrl do
                brush.color = format.colorUrl
            else do
                brush.color = format.palette[c.colorIdx]

            var under = c.under
            if c.isHotUrl do
                under = .Underline

            .drawShapedRun(c.pos.x, c.pos.y, &c.shaped, c.font, brush, under)
        }

        // Restore clipping to its previous value
        if format.flags & .Clip do
            .popClippingRect()
    }
}
