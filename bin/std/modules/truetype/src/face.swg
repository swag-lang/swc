using Swag, Core

// Controls how a glyph is loaded into the reusable slot.
#[Swag.EnumFlags]
public enum LoadFlag
{
    Default     // Loads a scaled outline without rendering it.
    Render      // Renders a grayscale bitmap after loading.
}

// Describes style traits declared by a font face.
#[Swag.EnumFlags]
public enum StyleFlag
{
    None = 0     // The face declares no bold or italic trait.
    Italic       // The face declares an italic style.
    Bold         // The face declares a bold weight.
}

// Owns one parsed TrueType font face and its reusable glyph workspace.
//
// Create a face with [[TrueType.Face.load]] and release it exactly once with
// [[TrueType.Face.destroy]]. Metadata strings, the size, character map, glyph
// slot, outlines, and bitmaps all belong to the face.
public struct Face
{
    // The reusable slot remains mutable so its documented outline operations can
    // transform the current glyph in place.
    glyph: GlyphSlot     // Reusable slot for the current glyph.

    // Loading and glyph operations establish all face state. Callers may inspect
    // it but cannot break the relationships between its metrics and borrowed data.
    readonly
    {
        style:              StyleFlag     // Declared bold and italic traits.
        glyphCount:         u32           // Number of glyphs in the face.
        familyName:         String        // Owned font-family name.
        styleName:          String        // Owned style name such as `Regular` or `Bold`.
        bbox:               BBox          // Global bounding box in font design units.
        unitsPerEm:         u16           // Number of font design units in one em.
        ascender:           s16           // Typographic ascender in design units.
        descender:          s16           // Typographic descender in design units.
        height:             s16           // Recommended line height in design units.
        maxAdvanceWidth:    s16           // Maximum horizontal advance in design units.
        underlinePosition:  s16           // Underline center relative to the baseline.
        underlineThickness: s16           // Recommended underline thickness in design units.
        size:               Size          // Active pixel size and scaled metrics.
        charMap:            CharMap       // Selected Unicode character map.
    }
}

public impl Face
{
    internal mtd setNames(familyName, styleName: String)
    {
        .familyName = familyName
        .styleName  = styleName
    }

    internal mtd setUnderline(position, thickness: s16)
    {
        .underlinePosition  = position
        .underlineThickness = thickness
    }

    internal mtd setHeader(unitsPerEm: u16, xMin, yMin, xMax, yMax: s16)
    {
        .unitsPerEm = unitsPerEm
        .bbox       = {xMin, yMin, xMax, yMax}
    }

    internal mtd setHorizontalMetrics(ascender, descender, lineGap, maxAdvanceWidth: s16)
    {
        .ascender        = ascender
        .descender       = descender
        .height          = cast(s16) (ascender - descender + lineGap)
        .maxAdvanceWidth = maxAdvanceWidth
    }

    internal mtd setGlyphCount(glyphCount: u32)
    {
        .glyphCount = glyphCount
    }

    internal mtd setStyle(style: StyleFlag)
    {
        .style = style
    }

    internal mtd initializeRecords()
    {
        .glyph.initialize(me)
        .size.initialize(me)
        .charMap.initialize(me)
    }

    internal mtd selectCharMap(platformID, encodingID: u16)
    {
        .charMap.select(platformID, encodingID)
    }

    // Loads a TrueType face from an in-memory font file.
    //
    // The face owns a private copy of `bytes`, so the input may be released after
    // this call. Release the returned pointer with [[TrueType.Face.destroy]]. When
    // `allocator` is null, the allocator active at the start of the call owns the
    // face allocation.
    //
    // ```swag
    // let bytes = File.readAllBytes("Inter-Regular.ttf")
    // let face  = notnull (try TrueType.Face.load(bytes.toSlice()))
    // defer face.destroy()
    // ```
    func load(bytes: const [..] u8, allocator: #null IAllocator = null)->#null *Face fail
    {
        if @countof(bytes) == 0 do
            fault(0x06)
        let allocationAllocator = notnull (allocator orelse @getcontext().allocator)
        let faceData            = Memory.new'FaceImpl(allocationAllocator)
        faceData.allocationAllocator = allocationAllocator
        faceData.fontData.resize(@countof(bytes))
        let fontData = notnull faceData.fontData.buffer
        Memory.copy(fontData, @dataof(bytes), @countof(bytes))
        parseFace(faceData)
        return &faceData.face
    }

    // Releases this face and every resource borrowed from it.
    //
    // The pointer and all strings, outlines, and bitmaps obtained from it become
    // invalid immediately. Call this method exactly once.
    mtd destroy()
    {
        let faceData  = cast(*FaceImpl) cast(*void) me
        let allocator = faceData.allocationAllocator
        Memory.delete(faceData, allocator)
    }

    // Returns whether the font declares a bold style.
    mtd const isBold()->bool => .style.has(.Bold)

    // Returns whether the font declares an italic style.
    mtd const isItalic()->bool => .style.has(.Italic)

    // Selects the pixel dimensions used by subsequent glyph loads.
    //
    // Pass zero for one dimension to copy the other dimension. Both values cannot
    // be zero. Scaled metrics are exposed through [[TrueType.Face.size]].
    mtd setPixelSize(pixelWidth, pixelHeight: u32) fail
    {
        let faceData = getFaceImpl(me)
        if (!pixelWidth and !pixelHeight) or pixelWidth > Swag.U16.Max or pixelHeight > Swag.U16.Max do
            fault(0x17)

        var width  = pixelWidth
        var height = pixelHeight
        if !width do
            width = height
        if !height do
            height = width

        .size.setPixelMetrics(width, height)
    }

    // Returns whether the face contains supported kerning pairs.
    //
    // Only legacy `kern` format-zero pairs are currently read. Use this inexpensive
    // check to skip pair lookups for fonts without such data.
    mtd const hasKerning()->bool
    {
        let faceData = cast(const *FaceImpl) cast(const *void) me
        return faceData.kernPairs.count != 0
    }

    // Returns horizontal kerning between two glyph indices.
    //
    // The x component uses 26.6 fixed-point pixels at the active size. Both
    // components are zero when either index is missing or the pair has no adjustment.
    mtd const getKerning(leftGlyph, rightGlyph: u32)->Vector
    {
        let faceData = cast(const *FaceImpl) cast(const *void) me
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

    // Resolves a Unicode scalar value to a glyph index.
    //
    // Zero is returned when the character is absent or the character map cannot
    // be read; zero also identifies the font's conventional missing-glyph entry.
    mtd glyphIndex(charCode: rune)->u32
    {
        let faceData = cast(*FaceImpl) cast(*void) me
        let idx      = catch lookupGlyphIndex(faceData, cast(u32) charCode) as err
        return err != null ? 0 : idx
    }

    // Returns whether the selected character map contains a glyph for `charCode`.
    mtd hasChar(charCode: rune)->bool => .glyphIndex(charCode) != 0

    // Loads a glyph by index into the face's reusable slot.
    //
    // The active pixel size controls scaling. Existing outline and bitmap pointers
    // from this face are invalidated. Add `.Render` to produce a grayscale bitmap
    // in the same operation.
    mtd loadGlyph(glyphIndex: u32, loadFlags = LoadFlag.Default) fail
    {
        loadGlyphInternal(me, glyphIndex)
        if loadFlags & .Render do
            .renderGlyph()
    }

    // Resolves and loads a Unicode scalar value into the reusable slot.
    //
    // This is equivalent to combining [[TrueType.Face.glyphIndex]] and
    // [[TrueType.Face.loadGlyph]], except lookup failures are reported.
    mtd loadChar(charCode: rune, loadFlags = LoadFlag.Default) fail
    {
        let faceData = getFaceImpl(me)
        let idx      = lookupGlyphIndex(faceData, cast(u32) charCode)
        .loadGlyph(idx, loadFlags)
    }

    // Rasterizes the current outline into an 8-bit grayscale bitmap.
    //
    // The result is stored in [[TrueType.GlyphSlot.bitmap]] and replaces any
    // previous bitmap from this face.
    mtd renderGlyph() fail
    {
        renderCurrentOutline(&.glyph)
    }

    // Aligns important vertical zones of the current outline to whole pixels.
    //
    // The operation mutates the reusable outline to keep horizontal stems crisp.
    // It does nothing when the font lacks x-height data. Apply it before grayscale
    // rendering, but not before size-independent SDF or MSDF generation.
    mtd hintVertical() fail
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

        let points = notnull o.points
        for cast(u32) o.pointCount do
            points[@index].y = hintMapY(points[@index].y, xh, xhS, ch, chS)
    }

    // Renders the current outline as a single-channel signed-distance field.
    //
    // `spread` is the pixel distance mapped across the field transition and is
    // clamped to 1 through 64. The result uses [[TrueType.PixelMode.Gray]].
    mtd renderGlyphSdf(spread: u32 = 8) fail
    {
        renderCurrentOutlineSdf(&.glyph, spread)
    }

    // Renders the current outline as a multi-channel signed-distance field.
    //
    // `spread` is clamped to 1 through 64. The resulting four-byte pixels store
    // the multi-channel field in RGB and a true signed distance in alpha; the
    // bitmap reports [[TrueType.PixelMode.Rgba]].
    mtd renderGlyphMsdf(spread: u32 = 8) fail
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
