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

// TextMeshPro-style text effects for MSDF fonts. They are derived from the glyph
// distance field, so a single draw produces outline, glow and bevel; the soft drop
// shadow is rendered as an offset second pass. Effects only apply when the resolved
// draw font is MSDF (an explicit .Msdf font, or an .Auto font drawn at >= 20px);
// for a bitmap font they are ignored. Distances are in distance-field units, where
// 0.5 spans roughly the atlas spread, so widths scale with the text size.
public struct TextEffect
{
    // Outline drawn under the glyph face. 0 disables it; useful range ~0.05..0.35.
    outlineWidth:    f32
    outlineColor:    Color = Color.fromArgb(Argb.Black)

    // Grows (+) or shrinks (-) the glyph face; ~ -0.3..0.3.
    faceDilate:      f32
    // Edge softness in distance-field units; 0 = crisp, > 0 = feathered.
    softness:        f32

    // Soft halo around the glyph. A fully transparent color disables it.
    glowColor:       Color
    glowOffset:      f32        // shifts the glow band outward
    glowInner:       f32 = 0.0
    glowOuter:       f32 = 0.45
    glowPower:       f32 = 1.0

    // Distance-field emboss amount, lit from the upper-left; 0 disables it (~0..1).
    bevel:           f32

    // Soft drop shadow (offset second pass). A transparent color disables it.
    shadowColor:     Color
    shadowOffset:    Math.Point
    shadowDilate:    f32 = 0.0
    shadowSoftness:  f32 = 0.35
}

public impl TextEffect
{
    // True if any single-pass face effect (outline/glow/bevel/dilate/softness) is on.
    mtd const hasFaceEffects()->bool
    {
        return .outlineWidth > 0 or .glowColor.a > 0 or .bevel > 0 or .faceDilate != 0 or .softness != 0
    }

    // True if a drop shadow must be rendered.
    mtd const hasShadow()->bool
    {
        return .shadowColor.a > 0
    }

    // Resolve the shader uniforms for the main glyph face.
    mtd const faceParams()->FontEffectParams
    {
        var r: retval
        r.enabled      = .hasFaceEffects() ? 1.0 : 0.0
        r.faceDilate   = .faceDilate
        r.faceSoftness = .softness
        r.outlineWidth = .outlineWidth
        r.outlineColor = .outlineColor
        r.glowColor    = .glowColor
        r.glowOffset   = .glowOffset
        r.glowInner    = .glowInner
        r.glowOuter    = .glowOuter
        r.glowPower    = .glowPower
        r.bevel        = .bevel
        return r
    }

    // Resolve the shader uniforms for the drop-shadow pass: a softened, dilated face
    // drawn solid in the shadow color (no outline/glow/bevel).
    mtd const shadowParams()->FontEffectParams
    {
        var r: retval
        r.enabled      = 1.0
        r.faceDilate   = .shadowDilate
        r.faceSoftness = .shadowSoftness
        r.glowOuter    = 1.0
        r.glowPower    = 1.0
        return r
    }
}

const DefaultTextTabSize: u32 = 4

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
    isTab:       bool
}

struct ShapedRun
{
    font:        *Font
    glyphs:      Array'ShapedGlyph
    metrics:     StringMetrics
    inkBounds:   Math.Rectangle
    hasInk:      bool
    tabSize:     u32 = DefaultTextTabSize
    letterSpacing: f32
}

public struct TextDrawInfo
{
    drawFont:    *Font
    snapPixels:  bool
    scale:       f32
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
    tabSize:           u32 = DefaultTextTabSize
    letterSpacing:     f32
    minLineHeight:     f32
    paragraphGap:      s32
    maxLines:          u32
}

private func appendShapedGlyph(run: *ShapedRun, font: *Font, glyphIndex: u32, cluster: u64, previousGlyphIndex: u32, customAdvanceX = 0.0'f32, isTab = false, letterSpacing = 0.0'f32)
{
    var glyph: ShapedGlyph
    glyph.desc       = font.getGlyphDescByIndex(glyphIndex)
    glyph.glyphIndex = glyphIndex
    glyph.cluster    = cluster
    glyph.advanceX   = isTab ? customAdvanceX : glyph.desc.advanceX
    glyph.advanceY   = glyph.desc.advanceY
    glyph.isTab      = isTab
    if previousGlyphIndex and !isTab do
        glyph.offsetX = font.cache.kerning(previousGlyphIndex, glyphIndex) + letterSpacing

    let glyphX = run.metrics.width + glyph.offsetX
    if glyph.desc.width != 0 and glyph.desc.height != 0
    {
        let bounds = Math.Rectangle{glyphX + glyph.desc.shiftX, glyph.offsetY - glyph.desc.shiftY, glyph.desc.width, glyph.desc.height}
        if run.hasInk do
            run.inkBounds.setUnion(bounds)
        else
        {
            run.inkBounds = bounds
            run.hasInk    = true
        }
    }

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

private func appendShapedTab(run: *ShapedRun, font: *Font, cluster: u64, tabSize: u32)
{
    let spaceGlyphIndex = font.glyphIndex(' ')
    let spaceDesc       = font.getGlyphDescByIndex(spaceGlyphIndex)
    var effectiveTabSize = tabSize
    if !effectiveTabSize do
        effectiveTabSize = 1

    var spaceAdvance = spaceDesc.advanceX
    if spaceAdvance <= 0 do
        spaceAdvance = cast(f32) font.cache.refSize * 0.25

    let tabWidth   = spaceAdvance * cast(f32) effectiveTabSize
    let nextStop   = (Math.floor(run.metrics.width / tabWidth) + 1) * tabWidth
    let tabAdvance = nextStop - run.metrics.width
    appendShapedGlyph(run, font, spaceGlyphIndex, cluster, 0, tabAdvance, true)
}

private func finishShapedRun(run: *ShapedRun, font: *Font)
{
    if run.glyphs.isEmpty() do
        return

    let sc = font.scale()
    run.metrics.ascent  *= sc
    run.metrics.descent *= sc
    run.metrics.width   *= sc
    run.metrics.height = run.metrics.ascent + run.metrics.descent
    if run.hasInk
    {
        run.inkBounds.x *= sc
        run.inkBounds.y *= sc
        run.inkBounds.width *= sc
        run.inkBounds.height *= sc
    }
}

private func snapTextPosition(value: f32, snapPixels: bool)->f32
{
    return snapPixels ? Math.round(value) : value
}

impl Painter
{
    func getTextDrawInfo(font: *Font, zoom = 1.0'f32, transformScale = 1.0'f32)->TextDrawInfo
    {
        var result: retval
        result.drawFont   = Font.resolveDrawFont(font, cast(f32) font.size * zoom * transformScale)
        result.snapPixels = !result.drawFont.cache.renderMode.isDistanceField()
        result.scale      = result.drawFont.scale() * zoom
        return result
    }

    // Scale applied to text by the current transform (max of the two axis scales).
    mtd const textTransformScale()->f32
    {
        let tr = .curState.transform
        return Math.max(Math.sqrt(tr.m11 * tr.m11 + tr.m12 * tr.m12), Math.sqrt(tr.m21 * tr.m21 + tr.m22 * tr.m22))
    }

    func advanceTextX(left, offsetX, advanceX: f32, info: TextDrawInfo, runStart = false)->{ glyphX: f32, rightX: f32 }
    {
        var result: retval
        result.glyphX = runStart and info.snapPixels ? Math.round(left) : left

        let snappedOffset = info.snapPixels ? Math.round(offsetX * info.scale) : offsetX * info.scale
        result.glyphX += snappedOffset

        let snappedAdvance = info.snapPixels ? Math.round(advanceX * info.scale) : advanceX * info.scale
        result.rightX = result.glyphX + snappedAdvance
        return result
    }

    // Shape a single-font text run into a caller-provided run, reusing its glyph
    // buffer (cleared, capacity kept) so a per-frame draw path can shape without
    // allocating. This currently preserves the legacy one-rune to one-glyph behavior,
    // but stores glyph indexes, advances and cluster positions so GSUB/GPOS, fallback
    // and bidi can be introduced at this layer.
    func shapeRunInto(result: *ShapedRun, text: string, font: *Font, tabSize: u32 = DefaultTextTabSize, letterSpacing = 0.0'f32)
    {
        Debug.assert(font != null, "invalid font")

        result.font          = font
        result.tabSize       = tabSize
        result.letterSpacing = letterSpacing
        result.hasInk        = false
        result.metrics.ascent, result.metrics.descent, result.metrics.width, result.metrics.height = 0
        result.glyphs.clear()
        result.glyphs.reserve(@countof(text))

        var count = @countof(text)
        var scan = @dataof(text)
        var byteIdx = 0'u64
        var previousGlyphIndex = 0'u32
        let letterSpacingRef = letterSpacing / font.scale()

        while count
        {
            let sl = @mkslice(scan, count)
            let (c, eat) = Utf8.decodeRune(sl)
            if eat == 0 do
                break

            if c == '\t'
            {
                appendShapedTab(result, font, byteIdx, tabSize)
                previousGlyphIndex = 0
            }
            else
            {
                let glyphIndex = font.glyphIndex(c)
                appendShapedGlyph(result, font, glyphIndex, byteIdx, previousGlyphIndex, 0.0, false, letterSpacingRef)
                previousGlyphIndex = glyphIndex
            }

            byteIdx += eat
            scan += eat
            count -= eat
        }

        finishShapedRun(result, font)
    }

    // Shape a single-font text run, returning a freshly allocated run.
    func shapeRun(text: string, font: *Font, tabSize: u32 = DefaultTextTabSize, letterSpacing = 0.0'f32)->ShapedRun
    {
        var result: retval
        shapeRunInto(&result, text, font, tabSize, letterSpacing)
        return result
    }

    // Rebuild a shaped run for another concrete font cache while preserving its
    // glyph sequence and cluster mapping.
    func shapeRunForFont(run: const *ShapedRun, font: *Font)->ShapedRun
    {
        Debug.assert(font != null, "invalid font")
        Debug.assert(run.font == null or run.font.cache.typeFace == font.cache.typeFace, "cannot reuse glyph indexes with another typeface")

        var result: retval
        result.font = font
        result.tabSize = run.tabSize
        result.letterSpacing = run.letterSpacing
        result.glyphs.reserve(run.glyphs.count)

        var previousGlyphIndex = 0'u32
        let letterSpacingRef = run.letterSpacing / font.scale()
        for glyph in run.glyphs
        {
            if glyph.isTab
            {
                appendShapedTab(&result, font, glyph.cluster, run.tabSize)
                previousGlyphIndex = 0
            }
            else
            {
                appendShapedGlyph(&result, font, glyph.glyphIndex, glyph.cluster, previousGlyphIndex, 0.0, false, letterSpacingRef)
                previousGlyphIndex = glyph.glyphIndex
            }
        }

        finishShapedRun(&result, font)
        return result
    }

    // Returns all the glyphs for a given string and font
    func getGlyphs(text: string, font: *Font)->Array'(const *GlyphDesc)
    {
        var result: retval
        result.reserve(@countof(text))
        Utf8.visitRunes(text)
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
        for c in text
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
    func measureString(text: string, font: *Font, tabSize: u32 = DefaultTextTabSize, letterSpacing = 0.0'f32)->StringMetrics
    {
        let shaped = shapeRun(text, font, tabSize, letterSpacing)
        return shaped.metrics
    }

    // Returns the metrics of an already shaped text run
    func measureString(text: *ShapedRun)->StringMetrics => text.metrics

    // Horizontal advance up to byte `atByte`, computed with the exact pixel
    // snapping and draw-font resolution `drawString` uses to render `run`. Unlike
    // `measureString().width` (which sums raw, unsnapped advances) this matches the
    // on-screen glyph positions, so carets, selection rectangles and right-aligned
    // anchoring line up with what is actually drawn. Default `atByte` measures the
    // whole run.
    func measureStringSnapped(run: const *ShapedRun, atByte: u64 = Swag.U64.Max)->f32
    {
        let info = getTextDrawInfo(run.font)

        // drawString re-shapes onto the resolved draw font; mirror that so the
        // advances use the same glyph metrics it will actually draw with.
        var drawShape: ShapedRun
        var toDraw: const *ShapedRun = run
        if run.font != info.drawFont
        {
            drawShape = shapeRunForFont(run, info.drawFont)
            toDraw    = &drawShape
        }

        var x = 0.0'f32
        for glyph, idx in toDraw.glyphs
        {
            if glyph.cluster >= atByte do
                break
            let step = advanceTextX(x, glyph.offsetX, glyph.advanceX, info, idx == 0)
            x = step.rightX
        }

        return x
    }

    // String convenience overload of `measureStringSnapped`.
    func measureStringSnapped(text: string, font: *Font, atByte: u64 = Swag.U64.Max, tabSize: u32 = DefaultTextTabSize, letterSpacing = 0.0'f32)->f32
    {
        let shaped = shapeRun(text, font, tabSize, letterSpacing)
        return measureStringSnapped(&shaped, atByte)
    }

    // Returns the bounding rectangle of a given text, scaled to the font draw size
    func measureString(text: Array'(const *GlyphDesc), font: *Font)->StringMetrics
    {
        var result: retval
        result.ascent  = Swag.F32.NegInf
        result.descent = Swag.F32.NegInf
        for refr, i in text
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

    // Emit the glyph quads of a shaped run, translated by (dx, dy) and tinted with
    // 'color'. The offset is applied after pixel snapping so a sub-pixel shadow
    // offset survives. Shared by the face pass and the drop-shadow pass.
    private mtd pushShapedGlyphs(runToDraw: *ShapedRun, drawFont: *Font, info: TextDrawInfo, startLeft, baselineY, dx, dy: f32, snapPixels: bool, color: Color)
    {
        var x = startLeft
        for glyph, idx in runToDraw.glyphs
        {
            let step   = Painter.advanceTextX(x, glyph.offsetX, glyph.advanceX, info, idx == 0)
            let glyphX = step.glyphX

            let refr = glyph.desc
            if refr.width != 0 and refr.height != 0
            {
                .setTextureFont(drawFont, refr.atlasIndex)

                let x1 = snapTextPosition(glyphX + refr.shiftX * info.scale, snapPixels) + dx
                let y1 = snapTextPosition(baselineY + glyph.offsetY * info.scale - refr.shiftY * info.scale, snapPixels) + dy
                let x2 = snapTextPosition(glyphX + (refr.shiftX * info.scale) + (refr.width * info.scale), snapPixels) + dx
                let y2 = snapTextPosition(baselineY + glyph.offsetY * info.scale - (refr.shiftY * info.scale) + (refr.height * info.scale), snapPixels) + dy

                let p1 = Math.Vector2{x1, y1}
                let p2 = Math.Vector2{x2, y1}
                let p3 = Math.Vector2{x1, y2}
                let p4 = Math.Vector2{x2, y2}

                let uv1 = Math.Vector2{refr.uv.x, refr.uv.y}
                let uv2 = Math.Vector2{refr.uv.x + refr.uv.width, refr.uv.y}
                let uv3 = Math.Vector2{refr.uv.x, refr.uv.y + refr.uv.height}
                let uv4 = Math.Vector2{refr.uv.x + refr.uv.width, refr.uv.y + refr.uv.height}

                discard .pushTriangle(p1, p2, p3, uv1, uv2, uv3, color)
                discard .pushTriangle(p3, p2, p4, uv3, uv2, uv4, color)
            }

            x = step.rightX
        }
    }

    // Draw an already shaped text run
    mtd drawShapedRun(left, top: f32, shaped: *ShapedRun, font: *Font, brush: Brush, under = UnderlineStyle.None, zoom = 1.0)
    {
        .drawShapedRun(left, top, shaped, font, brush, TextEffect{}, under, zoom)
    }

    // Draw an already shaped text run, with MSDF text effects (outline/glow/bevel/
    // shadow). Effects are ignored when the resolved draw font is not MSDF.
    mtd drawShapedRun(left, top: f32, shaped: *ShapedRun, font: *Font, brush: Brush, effect: TextEffect, under = UnderlineStyle.None, zoom = 1.0)
    {
        if shaped.glyphs.isEmpty() do
            return
        if .fake do
            return
        // Nothing visible: no face fill and no outline/glow/shadow either.
        if !brush.hasVisibleAlpha() and effect.outlineColor.a == 0 and effect.glowColor.a == 0 and !effect.hasShadow() do
            return

        let info = Painter.getTextDrawInfo(font, zoom, .textTransformScale())
        let drawFont   = info.drawFont
        let snapPixels = info.snapPixels
        let isMsdf     = drawFont.cache.renderMode == .Msdf

        var drawShape: ShapedRun
        var runToDraw: *ShapedRun = shaped
        if shaped.font != drawFont
        {
            drawShape = shapeRunForFont(shaped, drawFont)
            runToDraw = &drawShape
        }

        let drawLeft = snapTextPosition(left, snapPixels)
        let y = snapTextPosition(top + font.ascent * zoom, snapPixels)

        switch drawFont.cache.renderMode
        {
        case Msdf:
            .startMsdfFont()
        default:
            .startFont()
        }

        .updateFont(drawFont)

        // Drop shadow: an offset pass behind the text, drawn solid in the shadow
        // color (paint reset to solid). Binds the glyph atlas, so reset the font
        // texture afterwards to keep the underline (which samples a white texture).
        if isMsdf and effect.hasShadow()
        {
            .resetTexture0()
            .setFontEffect(effect.shadowParams())
            .pushShapedGlyphs(runToDraw, drawFont, info, left, y, effect.shadowOffset.x * zoom, effect.shadowOffset.y * zoom, snapPixels, effect.shadowColor)
            .resetTextureFont()
        }

        // Set brush main texture
        if brush.type != .SolidColor
        {
            let paintBounds = shaped.hasInk ? shaped.inkBounds : Math.Rectangle{0, -shaped.metrics.ascent, shaped.metrics.width, shaped.metrics.height}
            .setTexture0({drawLeft + paintBounds.x * zoom, y + paintBounds.y * zoom}, {drawLeft + paintBounds.right() * zoom, y + paintBounds.bottom() * zoom}, brush)
        }
        else do
            .resetTexture0()

        if isMsdf do
            .setFontEffect(effect.faceParams())

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
                .drawLine(drawLeft, yUnder, drawLeft + shaped.metrics.width * zoom, yUnder, pen)
            case Underline:
                let yUnder = y - font.underlinePos
                .drawLine(drawLeft, yUnder, drawLeft + shaped.metrics.width * zoom, yUnder, pen)
            }

            .canSetTexture0 = true
        }

        .pushShapedGlyphs(runToDraw, drawFont, info, left, y, 0, 0, snapPixels, brush.color)

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

        // Shape directly on the resolved draw font. For an 'Auto' font drawn small
        // this is the crisp bitmap, so we avoid rasterizing the (unused) MSDF glyph
        // and the subsequent re-shape that drawShapedRun would otherwise do. Shaping
        // into the painter's reusable scratch run avoids a per-call glyph allocation.
        let info = Painter.getTextDrawInfo(font, zoom, .textTransformScale())
        Painter.shapeRunInto(&.scratchShaped, text, info.drawFont)
        .drawShapedRun(left, top, &.scratchShaped, font, brush, under, zoom)
    }

    // Draw a simple string with MSDF text effects (outline/glow/bevel/shadow).
    mtd drawString(left, top: f32, text: string, font: *Font, color: Color, effect: TextEffect, under = UnderlineStyle.None, zoom = 1.0)
    {
        if @countof(text) == 0 do
            return
        let brush = Brush.createSolid(color)
        .drawString(left, top, text, font, brush, effect, under, zoom)
    }

    // Draw a simple string with a brush and MSDF text effects.
    mtd drawString(left, top: f32, text: string, font: *Font, brush: Brush, effect: TextEffect, under = UnderlineStyle.None, zoom = 1.0)
    {
        if @countof(text) == 0 do
            return
        if .fake do
            return

        let info = Painter.getTextDrawInfo(font, zoom, .textTransformScale())
        Painter.shapeRunInto(&.scratchShaped, text, info.drawFont)
        .drawShapedRun(left, top, &.scratchShaped, font, brush, effect, under, zoom)
    }

    // Recompute the layout for a given rectangle
    func computeLayout(pos: Math.Rectangle, text: *RichString, format: RichStringFormat)
    {
        Debug.assert(format.font.regular != null, "invalid default font")
        text.layoutRect = pos

        struct OneLine
        {
            measure:         StringMetrics
            height:          f32
            fontAscent:      f32
            fontDescent:     f32
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
        let defaultLineHeight = format.font.regular.height
        for &resetChunk in text.chunks do
            resetChunk.visible = false

        for &c, idx in text.chunks
        {
            // Attributes
            let fs = c.hasFontStyle ? c.fontStyle : format.fontStyle
            c.font = format.font.getFont(fs)

            // Measure
            c.shaped = shapeRun(c.slice, c.font, format.tabSize, format.letterSpacing)
            let ms = c.shaped.metrics
            c.boundRect = {0, 0, ms.width, ms.height}

            // User eol
            if c.isEol
            {
                line.start  = startLine
                line.end    = cast(s32) idx
                line.height = Math.max(defaultLineHeight, Math.max(line.measure.height, line.fontAscent - line.fontDescent))
                if format.minLineHeight > 0 do
                    line.height = Math.max(line.height, format.minLineHeight)
                line.hasEol = true
                lines.add(line)

                startLine = line.end + 1
                line.measure.width, line.measure.height = 0
                line.measure.ascent, line.measure.descent = 0
                line.height = 0
                line.fontAscent, line.fontDescent = 0
                line.countSpaces = 0
                line.whiteSpaces = 0
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

                        line.height = Math.max(defaultLineHeight, Math.max(line.measure.height, line.fontAscent - line.fontDescent))
                        if format.minLineHeight > 0 do
                            line.height = Math.max(line.height, format.minLineHeight)
                        lines.add(line)
                    }

                    startLine = cast(s32) idx
                    line.measure.width, line.measure.height = 0
                    line.measure.ascent, line.measure.descent = 0
                    line.height = 0
                    line.fontAscent, line.fontDescent = 0
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
                        line.fontAscent      = Math.max(line.fontAscent, c.font.ascent)
                        line.fontDescent     = Math.min(line.fontDescent, c.font.descent)
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
            line.fontAscent      = Math.max(line.fontAscent, c.font.ascent)
            line.fontDescent     = Math.min(line.fontDescent, c.font.descent)

            c.boundRect.height = Math.max(c.font.height, ms.height)
        }

        if startLine != text.chunks.count
        {
            line.start = startLine
            line.end   = cast(s32) text.chunks.count
            line.height = Math.max(defaultLineHeight, Math.max(line.measure.height, line.fontAscent - line.fontDescent))
            if format.minLineHeight > 0 do
                line.height = Math.max(line.height, format.minLineHeight)
            lines.add(line)
        }

        if format.maxLines and lines.count > format.maxLines
        {
            lines.resize(cast(u64) format.maxLines)
            lines[lines.count - 1].hasEol = false
        }

        let x = text.layoutRect.x
        var y = text.layoutRect.y

        // Vertical
        var totalHeight: f32

        let singleLine = lines.count == 1
        if lines.count > 1
        {
            totalHeight = 0
            for &l, idxLine in lines
            {
                totalHeight += l.height
                if idxLine != lines.count - 1
                {
                    totalHeight += cast(f32) format.lineGap
                    if l.hasEol do
                        totalHeight += cast(f32) format.paragraphGap
                }
            }
        }
        elif singleLine
        {
            if format.flags & .DontAdaptSingleLineHeight
            {
                totalHeight = defaultLineHeight
                if format.minLineHeight > 0 do
                    totalHeight = Math.max(totalHeight, format.minLineHeight)
            }
            else
            {
                totalHeight = lines[0].measure.height
                if format.minLineHeight > 0 do
                    totalHeight = Math.max(totalHeight, format.minLineHeight)
            }
        }

        switch format.vertAlignment
        {
        case Bottom:
            y = pos.bottom() - totalHeight
        case Center:
            y = pos.vertCenter() - (totalHeight * 0.5)
        }

        // Y correction if single line
        if singleLine and !(format.flags & .DontAdaptSingleLineHeight) do
            y -= (lines[0].fontAscent - lines[0].measure.ascent)

        text.boundRect.x      = Swag.F32.Max
        text.boundRect.y      = y
        text.boundRect.width  = 0
        text.boundRect.height = totalHeight
        var boundRight        = Swag.F32.NegInf

        // Layout
        for &l, idxLine in lines
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

            if l.end > l.start
            {
                for idx in l.start until l.end
                {
                    let c = &text.chunks[idx]
                    c.visible = true
                    c.pos.x = x1
                    c.pos.y = y1 + (l.fontAscent - c.font.ascent)

                    text.boundRect.x = Math.min(text.boundRect.x, c.pos.x)
                    boundRight       = Math.max(boundRight, c.pos.x + c.boundRect.width)

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
                }
            }

            y += l.height
            if idxLine != lines.count - 1
            {
                y += cast(f32) format.lineGap
                if l.hasEol do
                    y += cast(f32) format.paragraphGap
            }
        }

        if text.boundRect.x == Swag.F32.Max
        {
            text.boundRect.x = x
            boundRight       = x
        }

        text.boundRect.width = boundRight - text.boundRect.x
    }

    // Draw a rich string.
    // A rich string can be multiline, and accepts private formats.
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
        for &c in text.chunks
        {
            if c.isEol or !c.visible do
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
