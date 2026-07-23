using Swag, Core

#[Swag.EnumFlags]
public enum LoadFlag
{
    Default           = 0
    NoScale
    NoHinting
    Render
    NoBitmap
    VerticalLayout
    ForceAutoHint
    CropBitmap
    Pedantic
    AdvanceOnly
    IgnoreGlobalAdvanceWidth
    NoRecurse
    IgnoreTransform
    Monochrome
    LinearDesign
    SBitsOnly
    NoAutoHint
    Color             = 1 << 20
    ComputeMetrics    = 1 << 21
    BitmapMetricsOnly = 1 << 22
}

#[Swag.EnumFlags]
public enum StyleFlag
{
    None = 0
    Italic
    Bold
}

public enum RenderMode
{
    Normal = 0
    Light
    Mono
    Lcd
    LcdV
}

public struct Face
{
    faceCount:            s32
    faceIndex:            s32
    flags:                s32
    style:                StyleFlag
    glyphCount:           u32
    familyName:           String
    styleName:            String
    bbox:                 BBox
    unitsPerEm:           u16
    ascender:             s16
    descender:            s16
    height:               s16
    maxAdvanceWidth:      s16
    maxAdvanceHeight:     s16
    underlinePosition:    s16
    underlineThickness:   s16
    glyph:                GlyphSlot
    size:                 Size
    charMap:              CharMap
}

public impl Face
{
    // Load a face from an in-memory font file. The returned pointer aliases an
    // internal FaceImpl that owns a private copy of the bytes; release it with destroy().
    func load(bytes: const [..] u8, faceIndex: u32 = 0)->#null *Face throw
    {
        if @countof(bytes) == 0 do
            fail(0x06)
        if faceIndex != 0 do
            fail(0x07)

        let faceData = Memory.new'FaceImpl()
        faceData.fontData.resize(@countof(bytes))
        let fontData = notnull faceData.fontData.buffer
        Memory.copy(fontData, @dataof(bytes), @countof(bytes))
        parseFace(faceData)
        return &faceData.face
    }

    mtd destroy()
    {
        let faceData = cast(*FaceImpl) cast(*void) me
        Memory.delete(faceData)
    }

    mtd const isBold()->bool => .style.has(.Bold)
    mtd const isItalic()->bool => .style.has(.Italic)

    mtd setPixelSize(pixelWidth, pixelHeight: u32) throw
    {
        let faceData = getFaceImpl(me)
        if !pixelWidth and !pixelHeight do
            fail(0x17)

        var width  = pixelWidth
        var height = pixelHeight
        if !width do
            width = height
        if !height do
            height = width

        .size.metrics.xPpem      = cast(u16) width
        .size.metrics.yPpem      = cast(u16) height
        .size.metrics.xScale     = scaleFixed(width, faceData.unitsPerEm)
        .size.metrics.yScale     = scaleFixed(height, faceData.unitsPerEm)
        .size.metrics.ascender   = scale26_6(.ascender, height, faceData.unitsPerEm)
        .size.metrics.descender  = scale26_6(.descender, height, faceData.unitsPerEm)
        .size.metrics.height     = scale26_6(.height, height, faceData.unitsPerEm)
        .size.metrics.maxAdvance = scale26_6(.maxAdvanceWidth, width, faceData.unitsPerEm)
    }

    // True if the face carries any (legacy 'kern' format-0) kerning pairs. Lets callers
    // skip per-glyph-pair kerning lookups entirely for the many fonts that have none.
    mtd hasKerning()->bool throw
    {
        return getFaceImpl(me).kernPairs.count != 0
    }

    // Horizontal kerning between two glyphs, scaled to the current pixel size.
    // Returns a 26.6 fixed-point value in 'x' (FreeType-style), 0 if no pair.
    mtd getKerning(leftGlyph, rightGlyph: u32)->Vector throw
    {
        let faceData = getFaceImpl(me)
        var result: retval
        if !leftGlyph or !rightGlyph do
            return result

        let key  = (cast(u32) (leftGlyph & 0xFFFF) << 16) | cast(u32) (rightGlyph & 0xFFFF)
        let here = faceData.kernPairs.tryFind(key)
        if !here do
            return result

        result.x = roundDiv(cast(s64) here.value * .size.metrics.xScale, 65536)
        return result
    }

    mtd glyphIndex(charCode: rune)->u32
    {
        let faceData = cast(*FaceImpl) cast(*void) me
        let idx = catch lookupGlyphIndex(faceData, cast(u32) charCode)
        return @err != null ? 0 : idx
    }

    mtd loadGlyph(glyphIndex: u32, loadFlags = LoadFlag.Default) throw
    {
        loadGlyphInternal(me, glyphIndex)
        if loadFlags & .Render do
            .renderGlyph()
    }

    mtd loadChar(charCode: rune, loadFlags = LoadFlag.Default) throw
    {
        let faceData = getFaceImpl(me)
        let idx = lookupGlyphIndex(faceData, cast(u32) charCode)
        .loadGlyph(idx, loadFlags)
    }

    mtd renderGlyph(renderMode = RenderMode.Normal) throw
    {
        if renderMode != .Normal do
            fail(0x07)
        renderCurrentOutline(&.glyph)
    }

    // Vertical grid-fitting (blue zones): snap the baseline, x-height and cap-height
    // of the currently-loaded outline to whole pixels so horizontal stems stay crisp.
    // No-op when the face has no x-height (OS/2 missing). Apply before rendering the
    // bitmap; it must not be used on the size-independent SDF/MSDF atlases.
    mtd hintVertical() throw
    {
        let faceData = getFaceImpl(me)
        let o        = &.glyph.outline
        if o.pointCount <= 0 do
            return
        if faceData.xHeight <= 0 do
            return

        let yScale = .size.metrics.yScale
        let xh     = roundDiv(cast(s64) faceData.xHeight * yScale, 65536)
        if xh <= 0 do
            return
        let xhS = roundDiv(xh, 64) * 64
        if xhS <= 0 do
            return

        var ch  = 0
        var chS = 0
        if faceData.capHeight > 0
        {
            ch  = roundDiv(cast(s64) faceData.capHeight * yScale, 65536)
            chS = roundDiv(ch, 64) * 64
        }

        // Nothing to snap.
        if xhS == xh and (ch <= xh or chS == ch) do
            return

        for cast(u32) o.pointCount do
            o.points[@index].y = hintMapY(o.points[@index].y, xh, xhS, ch, chS)
    }

    mtd renderGlyphSdf(spread: u32 = 8) throw
    {
        renderCurrentOutlineSdf(&.glyph, spread)
    }

    mtd renderGlyphMsdf(spread: u32 = 8) throw
    {
        renderCurrentOutlineMsdf(&.glyph, spread)
    }
}

// Piecewise-linear vertical remap used by the blue-zone hinter (all values in 26.6,
// baseline at 0). The baseline, x-height (xh) and cap-height (ch) are anchored to
// their snapped, whole-pixel targets (xhS, chS); other heights interpolate or shift.
func hintMapY(y, xh, xhS, ch, chS: s32)->s32
{
    // No usable cap-height: single zone, uniform scale about the baseline.
    if ch <= xh or chS <= 0 do
        return roundDiv(cast(s64) y * xhS, xh)

    if y <= xh do
        return roundDiv(cast(s64) y * xhS, xh)
    if y <= ch
    {
        let num = cast(s64) xhS * (ch - y) + cast(s64) chS * (y - xh)
        return roundDiv(num, ch - xh)
    }

    // Above the cap-height (ascenders): translate by the cap-height correction.
    return y + (chS - ch)
}
