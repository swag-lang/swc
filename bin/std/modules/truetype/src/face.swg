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
    public glyph: GlyphSlot     // Reusable slot for the current glyph.

    // Loading and glyph operations establish all face state. Callers may inspect
    // it but cannot break the relationships between its metrics and borrowed data.
    public readonly
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
        xHeight:            s16           // Height of a lowercase `x` in design units, or zero when the face declares none.
        capHeight:          s16           // Height of an uppercase letter in design units, or zero when the face declares none.
        size:               Size          // Active pixel size and scaled metrics.
        charMap:            CharMap       // Selected Unicode character map.
    }
}

private func loadFaceBytes(bytes: const [..] u8, faceIndex: u32, fallbackFamilyName: string, allocator: #null IAllocator)->#null *Face fail
{
    if @countof(bytes) == 0 do
        fault(0x06)
    let allocationAllocator = (allocator orelse @getcontext().allocator)!
    let faceData            = Memory.new'FaceImpl(allocationAllocator)
    faceData.allocationAllocator = allocationAllocator
    defer #fail Memory.delete(faceData, allocationAllocator)
    faceData.fontData.resize(@countof(bytes))
    let fontData = faceData.fontData.buffer!
    Memory.copy(fontData, @dataof(bytes), @countof(bytes))
    parseFace(faceData, faceIndex, fallbackFamilyName)
    return &faceData.face
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

    internal mtd setVerticalZones(xHeight, capHeight: s16)
    {
        .xHeight   = xHeight
        .capHeight = capHeight
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
    // `bytes` may be a bare TrueType file or a `ttcf` collection, of which the
    // first face is taken; use [[TrueType.Face.loadAt]] to reach the others.
    // OpenType files carrying CFF outlines and WOFF containers are reported as
    // unsupported rather than as an unknown format.
    //
    // ```swag
    // let bytes = File.readAllBytes("Inter-Regular.ttf")
    // let face  = (try TrueType.Face.load(bytes.toSlice()))!
    // defer face.destroy()
    // ```
    func load(bytes: const [..] u8, allocator: #null IAllocator = null)->#null *Face fail
    {
        return Face.loadAt(bytes, 0, allocator)
    }

    // Loads a rendering-only TrueType subset from an in-memory font program.
    //
    // Document formats such as PDF may legally omit the `name` and `post` tables that an
    // installable OpenType font requires. `familyName` supplies the missing family identity;
    // absent style and underline metadata use `Regular` and zero. All outline, location, mapping,
    // and horizontal-metric tables remain mandatory. Use [[TrueType.Face.load]] for standalone
    // font files, where missing metadata is an error.
    //
    // Ownership and cleanup match [[TrueType.Face.load]].
    func loadSubset(bytes: const [..] u8, familyName: string, allocator: #null IAllocator = null)->#null *Face fail
    {
        if !@countof(familyName) do
            fault(0x06)
        return loadFaceBytes(bytes, 0, familyName, allocator)
    }

    // Loads one face of a TrueType collection by index.
    //
    // A `ttcf` collection packs several faces into one file, which is the form a
    // stock Windows installation ships many of its font families in. Indices run
    // from zero to [[TrueType.Face.countFaces]] minus one, and a bare font file
    // behaves as a collection holding its single face at index zero. Ownership and
    // cleanup match [[TrueType.Face.load]].
    //
    // ```swag
    // let bytes = File.readAllBytes("msgothic.ttc")
    // let count = try TrueType.Face.countFaces(bytes.toSlice())
    // for count
    // {
    //     let face = (try TrueType.Face.loadAt(bytes.toSlice(), @index))!
    //     defer face.destroy()
    // }
    // ```
    func loadAt(bytes: const [..] u8, faceIndex: u32, allocator: #null IAllocator = null)->#null *Face fail
    {
        return loadFaceBytes(bytes, faceIndex, "", allocator)
    }

    // Returns how many faces an in-memory font file holds.
    //
    // A `ttcf` collection answers its declared face count; every other supported
    // file answers one. The bytes are only inspected, so nothing is allocated and
    // no face is loaded. Failure is reported for a container this module cannot
    // read, which is the same diagnostic [[TrueType.Face.load]] would give.
    func countFaces(bytes: const [..] u8)->u32 fail
    {
        return countFacesIn(bytes)
    }

    // Returns the family name the face at `faceIndex` declares.
    //
    // Only the offset table and the `name` table are read, so no face is loaded
    // and nothing but the returned string is allocated. This is what makes a
    // collection searchable by family: a caller looking for one member reads the
    // names first, then calls [[TrueType.Face.loadAt]] once, instead of loading
    // every face to ask each one what it is called. The answer is the value
    // [[TrueType.Face.familyName]] carries once that face is loaded.
    //
    // ```swag
    // let bytes = File.readAllBytes("msgothic.ttc")
    // let count = try TrueType.Face.countFaces(bytes.toSlice())
    // for count
    // {
    //     if (try TrueType.Face.familyNameAt(bytes.toSlice(), @index)) == "MS PGothic" do
    //         break
    // }
    // ```
    func familyNameAt(bytes: const [..] u8, faceIndex: u32)->String fail
    {
        return familyNameIn(bytes, faceIndex)
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
    // Both the `GPOS` `kern` feature and the legacy `kern` table count. Use this
    // inexpensive check to skip pair lookups for faces carrying neither.
    mtd const hasKerning()->bool
    {
        let faceData = cast(const *FaceImpl) cast(const *void) me
        return faceData.gposPairSubtables.count != 0 or faceData.kernPairs.count != 0
    }

    // Returns horizontal kerning between two glyph indices.
    //
    // The x component uses 26.6 fixed-point pixels at the active size. Both
    // components are zero when either index is missing or the pair has no adjustment.
    //
    // The `GPOS` `kern` feature answers first, and the legacy `kern` table answers for
    // any pair it leaves at zero. `GPOS` is where a modern face states its kerning and
    // is the value its designer maintained, so it wins wherever it speaks. But this
    // module reads pair adjustment only: a face that puts most of its kerning behind
    // contextual lookups — Segoe UI states 5159 of its pairs that way — would lose it
    // entirely if the legacy table, which is the designer's own flattening of those
    // same rules, were discarded along with the rest.
    mtd const getKerning(leftGlyph, rightGlyph: u32)->Vector
    {
        let faceData = cast(const *FaceImpl) cast(const *void) me
        var result: retval
        if !leftGlyph or !rightGlyph or leftGlyph > Swag.U16.Max or rightGlyph > Swag.U16.Max do
            return result

        var units = 0's16
        if faceData.gposPairSubtables.count != 0
        {
            let value = catch lookupGposKerning(faceData, cast(u16) leftGlyph, cast(u16) rightGlyph) as err
            units = err != null ? 0's16 : value
        }

        if !units
        {
            let key  = (leftGlyph << 16) | rightGlyph
            let here = faceData.kernPairs.tryFind(key)
            if here do
                units = here.value
        }

        if !units do
            return result

        result.x = roundDiv(cast(s64) units * .size.metrics.xScale, 65536)
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

    // Resolves a Unicode scalar value qualified by a variation selector.
    //
    // A variation sequence picks between the forms of one character: a CJK regional
    // variant through `U+E0100` to `U+E01EF`, or the text and emoji presentations of
    // the same code point through `U+FE0E` and `U+FE0F`. When the face registers no
    // distinct glyph for the pair, the selector is ignored and the result is the one
    // [[TrueType.Face.glyphIndex]] gives for `charCode` alone.
    mtd glyphIndexVariant(charCode, selector: rune)->u32
    {
        let faceData = cast(*FaceImpl) cast(*void) me
        let variant  = catch lookupVariationGlyph(faceData, cast(u32) charCode, cast(u32) selector) as err
        if err == null and variant != 0 do
            return variant
        return .glyphIndex(charCode)
    }

    // Returns whether the face registers `charCode` followed by `selector`.
    //
    // A false answer means [[TrueType.Face.glyphIndexVariant]] ignores the selector,
    // not that the character is absent. The face declares no variation sequence at
    // all when it ships no `cmap` format-14 subtable.
    mtd hasVariant(charCode, selector: rune)->bool
    {
        let faceData = cast(*FaceImpl) cast(*void) me
        let found    = catch hasVariationSequence(faceData, cast(u32) charCode, cast(u32) selector) as err
        return err == null and found
    }

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

        let points = o.points!
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
