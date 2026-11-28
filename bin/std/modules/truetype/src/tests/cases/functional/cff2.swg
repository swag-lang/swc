#global if #command == Swag.CompilerCommand.Test

using Swag, Core

private struct Cff2GlyphReference
{
    advance:  u16
    points:   s16
    contours: s16
    checksum: u32
}

private func checkCff2Outlines(face: *Face, references: const [..] Cff2GlyphReference)
{
    Swag.require(face.glyphCount == references.count)
    expect face.setPixelSize(0, face.unitsPerEm)
    for reference, index in references
    {
        let glyph = cast(u32, index)
        Swag.require(expect face.getAdvanceWidth(glyph) == reference.advance)
        expect face.loadGlyph(glyph)

        let slot    = &face.glyph
        let outline = &slot.outline
        Swag.require(slot.advance.x == cast(s32, reference.advance) * 64)
        Swag.require(outline.pointCount == reference.points and outline.contourCount == reference.contours)
        if not reference.points
        {
            continue
        }

        let count = cast(u64, outline.pointCount)
        var checksum: Hash.Crc32
        checksum.update(Swag.makeSlice(cast(const [*] u8, unwrap outline.points), count * #sizeof(Vector)))
        checksum.update(Swag.makeSlice(unwrap outline.tags, count))
        checksum.update(Swag.makeSlice(cast(const [*] u8, unwrap outline.contours), cast(u64, outline.contourCount) * #sizeof(s16)))
        Swag.require(checksum.value() == reference.checksum)
    }
}

// Source Sans exercises local subroutines, both variation data records and
// glyph names supplied by the SFNT post table.
#test
{
    const Reference: [23] Cff2GlyphReference = [
        {624, 0, 0, 0x00000000}, {200, 0, 0, 0x00000000}, {520, 18, 2, 0x3B67E48B},
        {648, 24, 2, 0xD1A6F37E}, {540, 32, 2, 0x711176E9}, {478, 31, 1, 0xA2D85BC4},
        {520, 22, 3, 0x11886C98}, {648, 48, 4, 0x5CD8E002}, {636, 37, 1, 0xA4388639},
        {652, 34, 1, 0xE04E5376}, {682, 39, 2, 0x5FE4C814}, {794, 46, 1, 0x9166EA89},
        {924, 36, 3, 0xAC0CD1A6}, {472, 36, 3, 0x73BD1486}, {322, 32, 1, 0x1873E5F9},
        {600, 4, 1, 0x0BC04EC2}, {0, 5, 1, 0xDB34148D}, {0, 5, 1, 0x095A5BBB},
        {0, 5, 1, 0x31D6EAB9}, {0, 9, 2, 0x576F8D66}, {0, 9, 2, 0xF0201A7F},
        {0, 29, 3, 0xD953DBF6}, {0, 29, 3, 0xEAAF8DC0}]

    let source = expect FontSource.loadFile(getTestDataPath("cff2-sans-fixture.otf"))
    let face   = expect source.loadFace()
    defer face.destroy()
    Swag.require(face.isPostScript() and face.unitsPerEm == 1000)
    Swag.require(face.glyphIndex('A') == 2 and face.glyphIndex('Ω') == 9)
    Swag.require(face.glyphName(7) == "Odieresis" and face.glyphIndexByName("Odieresis") == 7)
    Swag.require(face.glyphIndexByCode(65) == 0 and face.glyphIndexByCid(9) == 0)
    checkCff2Outlines(face, Reference)

    let another = expect source.loadFace()
    defer another.destroy()
    expect another.setPixelSize(0, 32)
    expect another.loadChar('Ω', .Render)
    Swag.require(another.glyph.bitmap.width > 0 and another.glyph.bitmap.rows > 0)
}

// Source Serif selects several private dictionaries and blends across two axes.
#test
{
    const Reference: [20] Cff2GlyphReference = [
        {640, 0, 0, 0x00000000}, {233, 0, 0, 0x00000000}, {664, 25, 4, 0xC2498A54},
        {707, 24, 2, 0x1DA2B0C9}, {567, 42, 2, 0xBBA32214}, {510, 34, 1, 0xACE33CBB},
        {664, 29, 5, 0x36C373E4}, {707, 48, 4, 0x62BBE798}, {686, 64, 2, 0x93281B21},
        {820, 36, 3, 0x2606A927}, {500, 48, 3, 0x0C8FFE2C}, {359, 42, 1, 0xCC219810},
        {720, 4, 1, 0xC5A1E33A}, {0, 16, 1, 0xD126E436}, {0, 16, 1, 0x6830F9A9},
        {0, 4, 1, 0x170896A6}, {0, 24, 2, 0x2D8CBDB7}, {721, 42, 1, 0x818E6124},
        {0, 12, 1, 0xEBF5CC61}, {918, 114, 5, 0x504E48E7}]

    let bytes = loadFontBytes("cff2-serif-fixture.otf")
    let face  = expect Face.load(bytes.toSlice())
    defer face.destroy()
    Swag.require(face.glyphIndex('Ж') == 19 and face.glyphName(19) == null)
    checkCff2Outlines(face, Reference)
}

#test
{
    // Cover a count above uint16 without allocating a large charstring body.
    const Count = 65_536_u32
    var bytes: Array!{u8}
    bytes.resize(7 + Count)
    writeBigU32(&bytes, 0, Count)
    bytes[4] = 1
    for position in 5 until bytes.count - 2
    {
        bytes[position] = 1
    }

    bytes[bytes.count - 2] = 2
    bytes[bytes.count - 1] = 0xAA
    let index = expect readCffIndexWithCount!{4}(bytes.toSlice(), 0)
    Swag.require(index.count() == Count)
    Swag.require(index.item(0).count == 0 and index.item(Count - 1)[0] == 0xAA)

    var rejected: Swag.Error
    discard catch readCffIndexWithCount!{4}(bytes.toSlice()[until bytes.count - 1], 0) as rejected
    Swag.require(not rejected.isEmpty())
}

#test
{
    var bytes: Array!{u8}
    bytes.add([
        0, 80,                                           // VariationStore length
        0, 1, 0, 0, 0, 20, 0, 3,                         // Item Variation Store header, format 1
        0, 0, 0, 72, 0, 0, 0, 60, 0, 0, 0, 60,           // Unsorted and shared data offsets
        0, 2, 0, 3,                                      // Two axes, three regions
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,              // No participating axes
        0, 0, 0x20, 0, 0x40, 0, 0, 0, 0, 0, 0, 0,        // Participating positive axis
        0xE0, 0, 0x20, 0, 0x40, 0, 0, 0, 0, 0, 0, 0,     // Nonparticipating cross-zero axis
        0, 0, 0, 0, 0, 3, 0, 1, 0, 0, 0, 2,              // Order regions 1, 0, 2
        0, 0, 0, 0, 0, 1, 0, 1])                         // Only region 1
    let variations = expect readCff2VariationStore(bytes.toSlice(), 0)
    Swag.require(not variations.data[0].hasDefaultDeltas)
    Swag.require(variations.data[1].indices.buffer == variations.data[2].indices.buffer)
    var values = [777.0_f64, 10.0, -10.0, 5.0, 2.0, 3.0, 7.0, -2.0, -3.0, 2.0]
    let count  = expect blendCff2Operands(&variations, 2, values)
    Swag.require(count == 3 and values[0] == 777.0 and values[1] == 15.0 and values[2] == -15.0)

    var rejected: Swag.Error
    values[9] = -1.0
    discard catch blendCff2Operands(&variations, 2, values) as rejected
    Swag.require(not rejected.isEmpty())

    // A region reference must name an existing row.
    bytes[bytes.count - 1] = 3
    discard catch readCff2VariationStore(bytes.toSlice(), 0) as rejected
    Swag.require(not rejected.isEmpty())
    bytes[bytes.count - 1] = 1

    writeBigU32(&bytes, 18, 62)
    discard catch readCff2VariationStore(bytes.toSlice(), 0) as rejected
    Swag.require(not rejected.isEmpty())
}

#test
{
    var bytes: Array!{u8}
    bytes.add([
        4, 0, 0, 0, 2,        // Format 4 and two ranges
        0, 0, 0, 0, 1, 0,     // GID 0 through 4 use FD 256
        0, 0, 0, 5, 0, 1,     // GID 5 through 9 use FD 1
        0, 0, 0, 10])         // Sentinel
    var font: CffFont
    font.block  = bytes.toSlice()
    font.isCff2 = true
    font.charStrings.itemCount = 10
    font.fdPrivate.resize(257)
    font.fdSelect = expect readCffFdSelect(&font, 0)
    Swag.require(font.dictionaryIndex(0) == 256 and font.dictionaryIndex(4) == 256)
    Swag.require(font.dictionaryIndex(5) == 1 and font.dictionaryIndex(9) == 1)

    bytes[10] = 1
    var rejected: Swag.Error
    discard catch readCffFdSelect(&font, 0) as rejected
    Swag.require(not rejected.isEmpty())
}

#test
{
    const InvalidGlyphs: [7] const [..] u8 = [
        [28_u8, 0],               // truncated integer
        [255_u8, 0, 0, 0],        // truncated fixed-point operand
        [12_u8],                  // missing escaped opcode
        [16_u8],                  // blend without operands
        [139_u8, 15],             // vsindex without a VariationStore
        [139_u8, 139, 1, 19],     // missing mask byte for one stem
        [14_u8]]                  // explicit CFF1 endchar
    for code in InvalidGlyphs
    {
        var bytes: Array!{u8}
        bytes.add([0_u8, 0, 0, 1, 1, 1, cast(u8, code.count + 1)])
        bytes.add(code)

        var backing: FaceImpl
        backing.cff.isCff2      = true
        backing.cff.charStrings = expect readCffIndexWithCount!{4}(bytes.toSlice(), 0)
        var builder = OutlineBuilder.create(&backing, 20, 20, 1000)
        var rejected: Swag.Error
        discard catch runType2Charstring(&backing.cff, 0, &builder) as rejected
        Swag.require(not rejected.isEmpty())
    }
}

#test
{
    var bytes = loadFontBytes("cff2-serif-fixture.otf")
    let table = parseTestTableRecord(&bytes, TAG_CFF2)
    writeBigU32(&bytes, table + 12, 5)
    var rejected: Swag.Error
    discard catch Face.load(bytes.toSlice()) as rejected
    Swag.require(not rejected.isEmpty())
}

#test
{
    // These points have representable s32 coordinates at the requested size,
    // but their horizontal span does not fit a GlyphMetrics width.
    const Bytes: [19] u8 = [
        0, 0, 0, 1, 1, 1, 13,        // CFF2 INDEX with one charstring
        28, 0xE4, 0xA8, 139, 21,     // Move to (-7000, 0)
        28, 0x36, 0xB0, 139, 5,      // Line to (7000, 0)
        140, 7]     // A third point keeps the contour nonempty
    var backing: FaceImpl
    backing.cff.isCff2      = true
    backing.cff.charStrings = expect readCffIndexWithCount!{4}(Bytes, 0)
    var builder = OutlineBuilder.create(&backing, 65_535, 65_535, 16)
    var rejected: Swag.Error
    discard catch runType2Charstring(&backing.cff, 0, &builder) as rejected
    Swag.require(not rejected.isEmpty())
}
