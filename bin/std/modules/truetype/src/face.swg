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

// Owned names and normalized style information for one font face.
//
// [[TrueType.Face.metadataAt]] reads this description without loading outlines or retaining
// the source bytes. Weight ranges from 1 to 1000; 400 is regular, 600 semibold, and 700 bold.
// The fixed-pitch flag comes from `post` and defaults to false when that table is absent.
// The italic angle is signed 16.16 degrees; divide by 65536 to obtain degrees.
// Underline metrics are in font design units and default to zero without `post`.
public struct FaceMetadata
{
    public
    {
        familyName:            String           // Family name, using the same name records as [[TrueType.Face.familyNameAt]].
        styleName:             String           // Legacy subfamily name such as `Regular`, `Light`, or `Bold Italic`.
        typographicFamilyName: String           // Preferred family name (name ID 16), falling back to `familyName`.
        typographicStyleName:  String           // Preferred subfamily name (name ID 17), falling back to `styleName`.
        weight:                u16  = 400       // Weight from the font, or 400/700 when only regular/bold traits are available.
        widthClass:            u16  = 5         // Width class from 1 (ultra-condensed) to 9 (ultra-expanded); 5 is normal.
        embedding:             u16              // Embedding permission bits of the OS/2 `fsType`, as written; zero is installable, or a face without OS/2.
        style:                 StyleFlag        // Bold and italic traits declared by the style tables or subfamily name.
        isFixedPitch:          bool = false     // True when the `post` table declares a nonzero fixed-pitch value.
        italicAngle:           s32  = 0         // Signed 16.16 degrees from `post`; divide by 65536 to obtain degrees.
        underlinePosition:     s16  = 0         // Underline center relative to the baseline, in design units.
        underlineThickness:    s16  = 0         // Recommended underline thickness in design units.
    }
}

// Holds one glyph's vertical advance and top side bearing in font design units.
public struct GlyphVerticalMetrics
{
    public readonly
    {
        advanceHeight:  u16     // Vertical pen advance after drawing the glyph.
        topSideBearing: s16     // Distance from the glyph's top bound to its vertical origin.
    }
}

public impl GlyphVerticalMetrics
{
    internal mtd set(advanceHeight: u16, topSideBearing: s16)
    {
        .advanceHeight  = advanceHeight
        .topSideBearing = topSideBearing
    }
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
        isFixedPitch:       bool          // True when the `post` table declares a nonzero fixed-pitch value.
        italicAngle:        s32           // Signed 16.16 degrees from `post`; divide by 65536 to obtain degrees.
        glyphCount:         u32           // Number of glyphs in the face.
        familyName:         String        // Owned font-family name.
        styleName:          String        // Owned style name such as `Regular` or `Bold`.
        version:            String        // Version string the face declares, such as `Version 7.01`, or empty.
        designer:           String        // Name of the face's designer, or empty.
        copyright:          String        // Copyright notice the face carries, or empty.
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

// Names the container a font program is wrapped in, from its first bytes alone.
//
// A PDF hands over the font program exactly as the document stores it, which for the two
// PostScript formats is neither an sfnt file nor self-describing beyond this signature.
private func detectProgramSource(bytes: const [..] u8)->{ source: OutlineSource, sfnt: bool }
{
    var result: #returntype
    result.sfnt = true
    if bytes.count < 4 do
        return result

    // A bare CFF opens with its format version, followed by a header size of at least four
    // and an offset size of one to four; no sfnt signature can be mistaken for it.
    if bytes[0] == 1 and bytes[1] == 0 and bytes[2] >= 4 and bytes[3] >= 1 and bytes[3] <= 4
    {
        result.source = .Cff
        result.sfnt   = false
        return result
    }

    if bytes[0] == 0x80 or (bytes[0] == '%' and bytes[1] == '!')
    {
        result.source = .Type1
        result.sfnt   = false
    }

    return result
}

private func loadFaceBytes(bytes: const [..] u8, faceIndex: u32, fallbackFamilyName: string, allocator: IAllocator?, fileName: string? = null)->*Face fail
{
    let allocationAllocator = unwrap (allocator orelse Swag.getContext().allocator)
    let context = Swag.getContext()
    let previousAllocator   = context.allocator
    context.allocator = allocationAllocator
    defer context.allocator = previousAllocator

    let faceData = Memory.new'FaceImpl(allocationAllocator)
    faceData.allocationAllocator = allocationAllocator
    defer #fail Memory.delete(faceData, allocationAllocator)
    if let path = fileName do
        faceData.fontData = try File.readAllBytes(path)

    let input = fileName ? faceData.fontData.toSlice() : bytes
    if not input.count do
        try fault(0x06)

    if input.count >= 4 and try readU32(input, 0) == TAG_WOFF
    {
        if faceIndex do
            try fault(0x0F)
        var normalized = try inflateWoff(input)
        faceData.fontData = #move normalized
    }
    elif not fileName
    {
        faceData.fontData.add(input)
    }

    let detected = detectProgramSource(faceData.fontData.toSlice())
    if detected.sfnt
    {
        try parseFace(faceData, faceIndex, fallbackFamilyName)
        return &faceData.face
    }

    if faceIndex do
        try fault(0x0F)
    faceData.outlineSource = detected.source
    try parseProgramFace(faceData, fallbackFamilyName)
    return &faceData.face
}

// Converts a 26.6 point size to an integer pixels-per-em value at the requested DPI.
// A positive point size that rounds below one pixel is not a usable size.
private func pointsToPpem(pointSize: s32, dpi: u32)->u32 fail
{
    if pointSize <= 0 or not dpi do
        try fault(0x17)

    let numerator   = cast(u64, pointSize) * cast(u64, dpi)
    let denominator = 72'u64 * 64
    let ppem        = (numerator + denominator / 2) / denominator
    if not ppem or ppem > Swag.U16.Max do
        try fault(0x17)
    return cast(u32, ppem)
}

public impl Face
{
    internal mtd setNames(familyName, styleName: String)
    {
        .familyName = familyName
        .styleName  = styleName
    }

    internal mtd setDescription(version, designer, copyright: String)
    {
        .version   = version
        .designer  = designer
        .copyright = copyright
    }

    // Releases the owned strings even when this read-only public metadata is
    // nested in an owner with a custom destructor.
    internal mtd releaseMetadataStrings()
    {
        .familyName.opDrop()
        Swag.init(&.familyName, 1)
        .styleName.opDrop()
        Swag.init(&.styleName, 1)
        .version.opDrop()
        Swag.init(&.version, 1)
        .designer.opDrop()
        Swag.init(&.designer, 1)
        .copyright.opDrop()
        Swag.init(&.copyright, 1)
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
        .height          = cast(s16, (ascender - descender + lineGap))
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

    internal mtd setFixedPitch(value: bool)
    {
        .isFixedPitch = value
    }

    internal mtd setItalicAngle(value: s32)
    {
        .italicAngle = value
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
    // this call. Success returns a non-null face. Release the returned pointer with
    // [[TrueType.Face.destroy]]. When `allocator` is null, the allocator active at the
    // start of the call owns the face allocation. A supplied allocator must remain alive
    // until the face is destroyed.
    //
    // `bytes` may be a TrueType or OpenType file, a bare CFF or Type 1 font program,
    // or a `ttcf` collection, of which the first face is taken; use
    // [[TrueType.Face.loadAt]] to reach the others. WOFF1 data is expanded to sfnt
    // before parsing; WOFF2 is unsupported.
    //
    // ```swag
    // let bytes = try File.readAllBytes("Inter-Regular.ttf")
    // let face  = try TrueType.Face.load(bytes.toSlice())
    // defer face.destroy()
    // ```
    func load(bytes: const [..] u8, allocator: IAllocator? = null)->*Face fail => try Face.loadAt(bytes, 0, allocator)

    // Loads a rendering-only TrueType subset from an in-memory font program.
    //
    // Document formats such as PDF may legally omit the `name`, `post` and `cmap` tables that
    // an installable OpenType font requires: the document addresses such a font by glyph index
    // or through its own encoding, never by asking the font what character a glyph stands for.
    // `familyName` supplies the missing family identity; absent style and underline metadata use
    // `Regular` and zero, absent fixed-pitch metadata is false, and a face with no character map
    // answers no character lookup. All
    // outline, location, and horizontal-metric tables remain mandatory. Use
    // [[TrueType.Face.load]] for standalone font files, where missing metadata is an error.
    //
    // Ownership and cleanup match [[TrueType.Face.load]].
    func loadSubset(bytes: const [..] u8, familyName: string, allocator: IAllocator? = null)->*Face fail
    {
        if not familyName.count do
            try fault(0x06)
        return try loadFaceBytes(bytes, 0, familyName, allocator)
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
    // let bytes = try File.readAllBytes("msgothic.ttc")
    // let count = try TrueType.Face.countFaces(bytes.toSlice())
    // for index in count
    // {
    //     let face = try TrueType.Face.loadAt(bytes.toSlice(), index)
    //     defer face.destroy()
    // }
    // ```
    func loadAt(bytes: const [..] u8, faceIndex: u32, allocator: IAllocator? = null)->*Face fail => try loadFaceBytes(bytes, faceIndex, "", allocator)

    // Loads one face from a font file into storage owned by the face.
    //
    // `faceIndex` selects a zero-based collection member and defaults to the first face.
    // Later writes or removal of the file do not affect the loaded face. File errors, invalid
    // indices and unsupported or malformed font data fail. The accepted formats, allocator
    // and cleanup follow [[TrueType.Face.load]].
    func loadFile(fileName: string, faceIndex: u32 = 0, allocator: IAllocator? = null)->*Face fail =>
        try loadFaceBytes("", faceIndex, "", allocator, fileName)

    // Returns how many faces an in-memory font file holds.
    //
    // A `ttcf` collection answers its declared face count; a valid WOFF1 or other
    // standalone font answers one. WOFF1 headers and table ranges are validated
    // without inflating table data. No face is loaded. Unsupported containers fail.
    func countFaces(bytes: const [..] u8)->u32 fail => try countFacesIn(bytes)

    // Returns the family name the face at `faceIndex` declares.
    //
    // For sfnt input, only the offset table and the `name` table are read. WOFF1
    // input is reconstructed before its name table is read. No face is loaded;
    // WOFF1 also requires temporary storage for the reconstructed font. This makes
    // a collection searchable by family: a caller looking for one member reads the
    // names first, then calls [[TrueType.Face.loadAt]] once, instead of loading
    // every face to ask each one what it is called. The answer is the value
    // [[TrueType.Face.familyName]] carries once that face is loaded.
    //
    // ```swag
    // let bytes = try File.readAllBytes("msgothic.ttc")
    // let count = try TrueType.Face.countFaces(bytes.toSlice())
    // for index in count
    // {
    //     if (try TrueType.Face.familyNameAt(bytes.toSlice(), index)) == "MS PGothic" do
    //         break
    // }
    // ```
    func familyNameAt(bytes: const [..] u8, faceIndex: u32)->String fail => try familyNameIn(bytes, faceIndex)

    // Reads a face's names, weight, width class, style, and fixed-pitch flag without loading its glyphs.
    //
    // Accepts an sfnt font, WOFF1 font, or TrueType/OpenType collection. `faceIndex` is
    // zero-based; a standalone font accepts only zero. WOFF1 is reconstructed in temporary
    // storage. The result owns its strings and retains no bytes.
    // Missing style tables fall back to the subfamily name. Absent or out-of-range weight
    // values use 400/700 according to the bold trait; absent or invalid width classes use 5.
    // The fixed-pitch flag is true for any nonzero `post.isFixedPitch` value and false when
    // the `post` table is absent.
    // The italic angle is signed 16.16 degrees; divide by 65536 to obtain degrees. It is zero
    // when the `post` table is absent. Underline position and thickness are in design units
    // and default to zero when that table is absent.
    // Out-of-bounds metadata fields, unsupported containers, and invalid indices fail.
    // This inspects metadata only; it does not validate that every glyph can be loaded.
    //
    // ```swag
    // let bytes = try Core.File.readAllBytes("family.ttc")
    // let metadata = try TrueType.Face.metadataAt(bytes.toSlice(), 1)
    // Swag.print(metadata.familyName.toString(), ": ", metadata.styleName.toString())
    // ```
    func metadataAt(bytes: const [..] u8, faceIndex: u32)->FaceMetadata fail => try metadataIn(bytes, faceIndex)

    // Releases this face and every resource borrowed from it.
    //
    // The pointer and all strings, outlines, and bitmaps obtained from it become
    // invalid immediately. Call this method exactly once.
    mtd destroy()
    {
        let faceData  = cast(*FaceImpl, cast(*void, me))
        let allocator = faceData.allocationAllocator
        Memory.delete(faceData, allocator)
    }

    // Returns whether the font declares a bold style.
    mtd const isBold()->bool => .style.has(.Bold)

    // Returns whether the font declares an italic style.
    mtd const isItalic()->bool => .style.has(.Italic)

    // Selects the pixel dimensions used by subsequent glyph loads.
    //
    // Pass zero for one dimension to copy the other dimension. Fails when both are
    // zero, either exceeds 65535, or the resulting scale and metrics cannot fit their
    // 16.16 and 26.6 fields. Scaled metrics are exposed through [[TrueType.Face.size]].
    mtd setPixelSize(pixelWidth, pixelHeight: u32) fail
    {
        if (not pixelWidth and not pixelHeight) or
           pixelWidth > Swag.U16.Max or
           pixelHeight > Swag.U16.Max do
            try fault(0x17)

        var width  = pixelWidth
        var height = pixelHeight
        if not width do
            width = height
        if not height do
            height = width

        try .size.setPixelMetrics(width, height)
    }

    // Selects a character size expressed in 26.6 points at the requested resolutions.
    //
    // Each nonzero point dimension is converted to pixels per em and rounded to the
    // nearest whole pixel before scaled metrics are updated. If one point dimension is
    // zero, its ppem copies the other converted dimension; both zero dimensions fail.
    // DPI values must be nonzero, and converted ppem must fit in 16 bits. Scaled metrics
    // are exposed through [[TrueType.Face.size]].
    //
    // ```swag
    // // Twelve points at 96 DPI is 16 pixels per em.
    // try face.setCharSize(12 * 64, 12 * 64, 96, 96)
    // ```
    mtd setCharSize(charWidth26_6, charHeight26_6: s32, horizontalDpi, verticalDpi: u32) fail
    {
        if charWidth26_6 < 0 or
           charHeight26_6 < 0 or
           (not charWidth26_6 and not charHeight26_6) or
           not horizontalDpi or
           not verticalDpi do
            try fault(0x17)

        var widthPpem  = 0'u32
        var heightPpem = 0'u32
        if charWidth26_6 do
            widthPpem = try pointsToPpem(charWidth26_6, horizontalDpi)
        if charHeight26_6 do
            heightPpem = try pointsToPpem(charHeight26_6, verticalDpi)
        if not widthPpem do
            widthPpem = heightPpem
        if not heightPpem do
            heightPpem = widthPpem

        try .size.setPixelMetrics(widthPpem, heightPpem)
    }

    // Returns whether the face contains supported kerning pairs.
    //
    // Both the `GPOS` `kern` feature and the legacy `kern` table count. Use this
    // inexpensive check to skip pair lookups for faces carrying neither.
    mtd const hasKerning()->bool
    {
        let faceData = cast(const *FaceImpl, cast(const *void, me))
        return not faceData.gposPairSubtables.isEmpty() or
               faceData.kernData != null or
               not faceData.kernPairs.isEmpty()
    }

    // Returns a glyph's vertical advance and top side bearing in font design units.
    //
    // The borrowed result remains valid until the face is destroyed. It is null when
    // the face has no `vhea` and `vmtx` tables. An index outside
    // [[TrueType.Face.glyphCount]] fails with an invalid-glyph error.
    mtd const getVerticalMetrics(glyphIndex: u32)->const *GlyphVerticalMetrics? fail
    {
        if glyphIndex >= .glyphCount do
            try fault(0x10)

        let faceData = cast(const *FaceImpl, cast(const *void, me))
        if not faceData.hasVerticalMetrics do
            return null

        return &faceData.verticalGlyphMetrics[glyphIndex]
    }

    // Returns a glyph's horizontal advance in font design units without loading its outline.
    //
    // SFNT faces use `hmtx`. Bare CFF and Type 1 faces use the width prepared from their charstrings.
    // The result is independent of the selected pixel size. An index outside
    // [[TrueType.Face.glyphCount]] fails with an invalid-glyph error.
    mtd const getAdvanceWidth(glyphIndex: u32)->u16 fail
    {
        if glyphIndex >= .glyphCount do
            try fault(0x10)

        let faceData = cast(const *FaceImpl, cast(const *void, me))
        return faceData.glyphAdvance(glyphIndex)
    }

    // Returns the ordered color layers declared for a glyph by COLR version 0.
    //
    // `paletteIndex` selects a CPAL palette. Each returned layer identifies its glyph,
    // CPAL entry, and resolved color in 0xAARRGGBB form. `hasColor` is false and `argb`
    // is zero for the special COLR foreground entry (0xFFFF). The returned array is
    // owned by the caller. An absent COLR table or base glyph returns an empty array;
    // invalid glyph or palette indices and malformed or unsupported tables fail.
    mtd const getColorLayers(baseGlyph: u32, paletteIndex: u16 = 0)->Array'ColorGlyphLayer fail
    {
        let faceData = cast(const *FaceImpl, cast(const *void, me))
        return try readColorGlyphLayers(faceData, baseGlyph, paletteIndex)
    }

    // Returns horizontal kerning between two glyph indices in font design units.
    //
    // GPOS adjustments accumulate in LookupList order, with the first matching pair
    // subtable selected within each lookup. The result does not depend on pixel size
    // and can be queried before setting one. Values outside the `s16` range are clamped.
    // The legacy `kern` table fills pairs for which supported GPOS lookups return zero.
    // Missing pairs and invalid glyph indices return zero.
    mtd const getKerningDesignUnits(leftGlyph, rightGlyph: u32)->s16
    {
        let faceData = cast(const *FaceImpl, cast(const *void, me))
        return lookupKerningDesignUnits(faceData, leftGlyph, rightGlyph)
    }

    // Returns horizontal kerning between two glyph indices.
    //
    // The x component uses 26.6 fixed-point pixels at the active size. GPOS lookup
    // adjustments accumulate before scaling, with the design-unit total clamped to
    // `s16`. Both components are zero when either index is missing or the pair has no
    // adjustment.
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
        let faceData = cast(const *FaceImpl, cast(const *void, me))
        var result: #returntype
        let units    = lookupKerningDesignUnits(faceData, leftGlyph, rightGlyph)
        if not units do
            return result

        result.x = roundDiv(cast(s64, units) * .size.metrics.xScale, 65536)
        return result
    }

    // Resolves a Unicode scalar value to a glyph index.
    //
    // Zero is returned when the character is absent or the character map cannot
    // be read; zero also identifies the font's conventional missing-glyph entry.
    mtd glyphIndex(charCode: rune)->u32
    {
        let faceData = cast(*FaceImpl, cast(*void, me))
        return catch lookupGlyphIndex(faceData, cast(u32, charCode)) orelse 0
    }

    // Returns whether the selected character map contains a glyph for `charCode`.
    mtd hasChar(charCode: rune)->bool => .glyphIndex(charCode) != 0

    // Resolves a PostScript glyph name to a glyph index.
    //
    // CFF and Type 1 programs key their outlines by name, which is how a document format
    // addresses them: the encoding of such a font is a table of names, not of characters.
    // TrueType outlines use names from `post` formats 1, 2, or 2.5. Format 3 contains no
    // names. If a name appears more than once, the lowest glyph index wins. Zero is returned
    // when the name is absent; as with [[TrueType.Face.glyphIndex]], zero is also the
    // conventional missing-glyph index.
    //
    // ```swag
    // let face  = try TrueType.Face.load(bytes)
    // let glyph = face.glyphIndexByName("fi")
    // ```
    mtd glyphIndexByName(name: string)->u32
    {
        let faceData = cast(*FaceImpl, cast(*void, me))
        return faceData.glyphIndexByName(name)
    }

    // Returns the name assigned to a glyph index, or null when the font has no name for it.
    //
    // CFF and Type 1 use their charstring glyph names. TrueType outlines use names from
    // `post` formats 1, 2, or 2.5. Format 3 has no names. The returned string borrows storage
    // owned by this face and remains valid until [[TrueType.Face.destroy]]. Invalid glyph
    // indices and empty or unavailable names return null.
    //
    // ```swag
    // if let name = face.glyphName(glyphIndex) do
    //     Swag.print("glyph name: ", name)
    // ```
    mtd glyphName(glyphIndex: u32)->string?
    {
        let faceData = cast(*FaceImpl, cast(*void, me))
        return faceData.glyphName(glyphIndex)
    }

    // Resolves a code through the font program's own built-in encoding.
    //
    // This is the encoding the font file declares, not a Unicode map: a CFF states one in
    // its `Encoding` structure and a Type 1 program in its `/Encoding` array. Zero is
    // returned for a face that declares none, and for an unused code.
    mtd glyphIndexByCode(code: u32)->u32
    {
        let faceData = cast(*FaceImpl, cast(*void, me))
        return faceData.glyphIndexByCode(code)
    }

    // Resolves a character identifier through a CID-keyed CFF charset.
    //
    // Composite document fonts address a CID-keyed program by identifier rather than by
    // glyph index, and the two coincide only when the font says so. Zero is returned for
    // any face that is not CID-keyed.
    mtd glyphIndexByCid(cid: u32)->u32
    {
        let faceData = cast(*FaceImpl, cast(*void, me))
        return faceData.glyphIndexByCid(cid)
    }

    // Returns whether this face stores its outlines as PostScript charstrings.
    mtd const isPostScript()->bool
    {
        let faceData = cast(const *FaceImpl, cast(const *void, me))
        return faceData.outlineSource != .Glyf
    }

    // Resolves a Unicode scalar value qualified by a variation selector.
    //
    // A variation sequence picks between the forms of one character: a CJK regional
    // variant through `U+E0100` to `U+E01EF`, or the text and emoji presentations of
    // the same code point through `U+FE0E` and `U+FE0F`. When the face registers no
    // distinct glyph for the pair, the selector is ignored and the result is the one
    // [[TrueType.Face.glyphIndex]] gives for `charCode` alone.
    mtd glyphIndexVariant(charCode, selector: rune)->u32
    {
        let faceData = cast(*FaceImpl, cast(*void, me))
        let variant  = catch lookupVariationGlyph(faceData, cast(u32, charCode), cast(u32, selector)) orelse 0
        return variant != 0 ? variant : .glyphIndex(charCode)
    }

    // Returns whether the face registers `charCode` followed by `selector`.
    //
    // A false answer means [[TrueType.Face.glyphIndexVariant]] ignores the selector,
    // not that the character is absent. The face declares no variation sequence at
    // all when it ships no `cmap` format-14 subtable.
    mtd hasVariant(charCode, selector: rune)->bool
    {
        let faceData = cast(*FaceImpl, cast(*void, me))
        return catch hasVariationSequence(faceData, cast(u32, charCode), cast(u32, selector)) orelse false
    }

    // Loads a glyph by index into the face's reusable slot.
    //
    // The active pixel size controls scaling. Existing outline and bitmap pointers
    // from this face are invalidated. Add `.Render` to produce a grayscale bitmap
    // in the same operation.
    mtd loadGlyph(glyphIndex: u32, loadFlags = LoadFlag.Default) fail
    {
        try loadGlyphInternal(me, glyphIndex)
        if loadFlags.has(.Render) do
            try .renderGlyph()
    }

    // Resolves and loads a Unicode scalar value into the reusable slot.
    //
    // This is equivalent to combining [[TrueType.Face.glyphIndex]] and
    // [[TrueType.Face.loadGlyph]], except lookup failures are reported.
    mtd loadChar(charCode: rune, loadFlags = LoadFlag.Default) fail
    {
        let faceData = try getFaceImpl(me)
        let idx      = try lookupGlyphIndex(faceData, cast(u32, charCode))
        try .loadGlyph(idx, loadFlags)
    }

    // Loads and composites a COLR v0 glyph into an RGBA color bitmap.
    //
    // Layers are rasterized in their declared order using the active pixel size and
    // source-over alpha composition. CPAL colors use `paletteIndex`; COLR's foreground
    // entries use `foregroundArgb`, defaulting to opaque black. The slot's outline and
    // metrics describe `baseGlyph`, while its bitmap uses [[TrueType.PixelMode.ColorRgba]]
    // with bytes in red, green, blue, alpha order. This replaces the slot's current
    // outline and bitmap, like [[TrueType.Face.loadGlyph]]. It fails if the glyph has no
    // color layers.
    mtd loadColorGlyph(baseGlyph: u32, paletteIndex: u16 = 0, foregroundArgb: u32 = 0xFF000000) fail
    {
        try renderColorGlyph(me, baseGlyph, paletteIndex, foregroundArgb)
    }

    // Rasterizes the current outline into an 8-bit grayscale bitmap.
    //
    // The result is stored in [[TrueType.GlyphSlot.bitmap]] and replaces any
    // previous bitmap from this face.
    mtd renderGlyph() fail => try renderCurrentOutline(&.glyph)

    // Aligns important vertical zones of the current outline to whole pixels.
    //
    // The operation mutates the reusable outline to keep horizontal stems crisp.
    // It does nothing when the font lacks x-height data. Apply it before grayscale
    // rendering, but not before size-independent SDF or MSDF generation.
    mtd hintVertical() fail
    {
        let faceData = try getFaceImpl(me)
        let o        = &.glyph.outline
        if o.pointCount <= 0 do
            return
        if faceData.xHeight <= 0 do
            return

        let yScale = .size.metrics.yScale
        let xh     = roundDiv(cast(s64, faceData.xHeight) * yScale, 65536)
        if xh <= 0 do
            return
        let xhS = roundDiv(xh, 64) * 64
        if xhS <= 0 do
            return

        var ch  = 0
        var chS = 0
        if faceData.capHeight > 0
        {
            ch  = roundDiv(cast(s64, faceData.capHeight) * yScale, 65536)
            chS = roundDiv(ch, 64) * 64
        }

        // Nothing to snap.
        if xhS == xh and (ch <= xh or chS == ch) do
            return

        let points = unwrap o.points
        for index in cast(u32, o.pointCount) do
            points[index].y = hintMapY(points[index].y, xh, xhS, ch, chS)
    }

    // Renders the current outline as a single-channel signed-distance field.
    //
    // `spread` is the pixel distance mapped across the field transition and is
    // clamped to 1 through 64. The result uses [[TrueType.PixelMode.Gray]].
    mtd renderGlyphSdf(spread: u32 = 8) fail => try renderCurrentOutlineSdf(&.glyph, spread)

    // Renders the current outline as a multi-channel signed-distance field.
    //
    // `spread` is clamped to 1 through 64. The resulting four-byte pixels store
    // the multi-channel field in RGB and a true signed distance in alpha; the
    // bitmap reports [[TrueType.PixelMode.Rgba]].
    mtd renderGlyphMsdf(spread: u32 = 8) fail => try renderCurrentOutlineMsdf(&.glyph, spread)
}

func lookupKerningDesignUnits(faceData: const *FaceImpl, leftGlyph, rightGlyph: u32)->s16
{
    if not leftGlyph or
       not rightGlyph or
       leftGlyph >= faceData.face.glyphCount or
       rightGlyph >= faceData.face.glyphCount or
       leftGlyph > Swag.U16.Max or
       rightGlyph > Swag.U16.Max do
        return 0

    var units = 0's16
    if not faceData.gposPairSubtables.isEmpty()
    {
        units = lookupGposKerning(faceData, cast(u16, leftGlyph), cast(u16, rightGlyph))
    }

    if not units do
        units = lookupLegacyKerning(faceData, (leftGlyph << 16) | rightGlyph)

    return units
}

// Piecewise-linear vertical remap used by the blue-zone hinter (all values in 26.6,
// baseline at 0). The baseline, x-height (xh) and cap-height (ch) are anchored to
// their snapped, whole-pixel targets (xhS, chS); other heights interpolate or shift.
func hintMapY(y, xh, xhS, ch, chS: s32)->s32
{
    // No usable cap-height: single zone, uniform scale about the baseline.
    if ch <= xh or chS <= 0 do
        return roundDiv(cast(s64, y) * xhS, xh)

    if y <= xh do
        return roundDiv(cast(s64, y) * xhS, xh)
    if y <= ch
    {
        let num = cast(s64, xhS) * (ch - y) + cast(s64, chS) * (y - xh)
        return roundDiv(num, ch - xh)
    }

    // Above the cap-height (ascenders): translate by the cap-height correction.
    return y + (chS - ch)
}
