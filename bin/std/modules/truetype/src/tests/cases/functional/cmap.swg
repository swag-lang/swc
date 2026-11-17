#global if #command == Swag.CompilerCommand.Test

using Swag, Core

func makeCmap8Fixture(setSupplementaryFlag: bool)->Array'u8
{
    var cmap: #returntype
    cmap.resize(12 + 8208 + 24)
    cmap[3]  = 1
    cmap[7]  = 4
    cmap[11] = 12

    let subTable = 12'u64
    cmap[subTable + 1] = 8
    writeBigU32(&cmap, subTable + 4, 8232)
    writeBigU32(&cmap, subTable + 8204, 2)

    let bmpGroup = subTable + 8208
    writeBigU32(&cmap, bmpGroup, 'A'u32)
    writeBigU32(&cmap, bmpGroup + 4, 'C'u32)
    writeBigU32(&cmap, bmpGroup + 8, 7)

    let supplementaryGroup = bmpGroup + 12
    writeBigU32(&cmap, supplementaryGroup, 0xD83D_DE00)
    writeBigU32(&cmap, supplementaryGroup + 4, 0xD83D_DE01)
    writeBigU32(&cmap, supplementaryGroup + 8, 20)

    if setSupplementaryFlag
    {
        let highSurrogate = 0xD83D'u32
        let flagOffset    = subTable + 12 + cast(u64, highSurrogate >> 3)
        let flag          = cast(u8, 0x80 >> (highSurrogate & 7))
        cmap[flagOffset] |= flag
    }

    return cmap
}

func addCmap13Subtable(cmap: *Array'u8, firstGlyph, secondGlyph: u32)
{
    let base = cmap.count
    cmap.add([
        0x00, 0x0D, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x34,
        0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x03,
        0x00, 0x00, 0x00, 0x41, 0x00, 0x00, 0x00, 0x43,
        0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x45, 0x00, 0x00, 0x00, 0x46,
        0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x47, 0x00, 0x00, 0x00, 0x47,
        0x00, 0x00, 0x00, 0x00])
    writeBigU32(cmap, base + 24, firstGlyph)
    writeBigU32(cmap, base + 36, secondGlyph)
}

func makeCmap13Fixture()->Array'u8
{
    var cmap: #returntype
    cmap.add([
        0x00, 0x00, 0x00, 0x02,
        0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x14,
        0x00, 0x00, 0x00, 0x04, 0x00, 0x00, 0x00, 0x48])
    addCmap13Subtable(&cmap, 3, 20)
    addCmap13Subtable(&cmap, 9, 20)
    return cmap
}

func parseTestCmap13(faceData: *FaceImpl, cmap: Array'u8) fail
{
    faceData.fontData.add(cmap.toSlice())
    faceData.tables.add({tag: TAG_CMAP, length: cast(u32, cmap.count)})
    faceData.face.setGlyphCount(32)
    discard try parseCMap(faceData, false)
}

// Format-12 group records must name existing glyphs and leave the reserved word zero.
#test
{
    var cmap: Array'u8
    cmap.add([
        0x00, 0x00, 0x00, 0x01,
        0x00, 0x00, 0x00, 0x04, 0x00, 0x00, 0x00, 0x0C])
    cmap.add(Cmap12Fixture)
    cmap[15] = 1

    var faceData: FaceImpl
    faceData.fontData.add(cmap.toSlice())
    faceData.tables.add({tag: TAG_CMAP, length: cast(u32, cmap.count)})
    faceData.face.setGlyphCount(8)

    var rejected: Swag.Error
    discard catch parseCMap(&faceData, false) as rejected
    Swag.require(rejected.value() != null)
}

#test
{
    var cmap: Array'u8
    cmap.add([
        0x00, 0x00, 0x00, 0x01,
        0x00, 0x00, 0x00, 0x04, 0x00, 0x00, 0x00, 0x0C])
    cmap.add(Cmap12Fixture)
    writeBigU32(&cmap, 12 + 24, 8)

    var faceData: FaceImpl
    faceData.fontData.add(cmap.toSlice())
    faceData.tables.add({tag: TAG_CMAP, length: cast(u32, cmap.count)})
    faceData.face.setGlyphCount(8)

    var rejected: Swag.Error
    discard catch parseCMap(&faceData, false) as rejected
    Swag.require(rejected.value() != null)
}

#test
{
    let glyphA = lookupCMap4(Cmap4Fixture, 'A'u32)
    Swag.require(glyphA == 3)

    let glyphB = lookupCMap4(Cmap4Fixture, 'B'u32)
    Swag.require(glyphB == 0)
}

#test
{
    let glyph0 = lookupCMap12(Cmap12Fixture, 0x00010000)
    Swag.require(glyph0 == 7)

    let glyph1 = lookupCMap12(Cmap12Fixture, 0x00010001)
    Swag.require(glyph1 == 0)
}

#test
{
    // A platform-zero format-12 map must report the record that was selected,
    // rather than a hard-coded Windows BMP record.
    let cmap: [40] u8 = [
        0x00, 0x00, 0x00, 0x01,
        0x00, 0x00, 0x00, 0x04, 0x00, 0x00, 0x00, 0x0C,
        0x00, 0x0C, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x1C,
        0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x01,
        0x00, 0x01, 0x00, 0x00,
        0x00, 0x01, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x07]

    var faceData: FaceImpl
    faceData.fontData.add(cmap)
    faceData.tables.add({tag: TAG_CMAP, length: cmap.count})
    faceData.face.setGlyphCount(8)

    discard expect parseCMap(&faceData, false)
    Swag.require(faceData.face.charMap.platformID == 0)
    Swag.require(faceData.face.charMap.encodingID == 4)
    Swag.require(faceData.cmapFormat == 12)
}

// A subtable offset beyond the cmap table must fail before constructing a slice.
#test
{
    const Cmap: [12] u8 = [
        0x00, 0x00, 0x00, 0x01,
        0x00, 0x00, 0x00, 0x04, 0x00, 0x00, 0x01, 0x00]
    var faceData: FaceImpl
    faceData.fontData.add(Cmap)
    faceData.tables.add({tag: TAG_CMAP, length: Cmap.count})

    var rejected: Swag.Error
    discard catch parseCMap(&faceData, false) as rejected
    let error = rejected.value()
    Swag.require(error != null)
}

// A truncated format-12 subtable must not consume a valid-looking group that
// happens to follow its declared extent in the cmap table.
#test
{
    var cmap: Array'u8
    cmap.add([
        0x00, 0x00, 0x00, 0x01,
        0x00, 0x00, 0x00, 0x04, 0x00, 0x00, 0x00, 0x0C,
        0x00, 0x0C, 0x00, 0x00, 0x00, 0x00, 0x00, 0x10,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01,
        0x00, 0x00, 0x00, 0x41, 0x00, 0x00, 0x00, 0x41,
        0x00, 0x00, 0x00, 0x07])

    var faceData: FaceImpl
    faceData.fontData.add(cmap.toSlice())
    faceData.tables.add({tag: TAG_CMAP, length: cast(u32, cmap.count)})
    faceData.face.setGlyphCount(8)

    var rejected: Swag.Error
    discard catch parseCMap(&faceData, false) as rejected
    Swag.require(rejected.value() != null)
}

// A format-12 subtable shorter than its fixed header is rejected.
#test
{
    const Cmap: [28] u8 = [
        0x00, 0x00, 0x00, 0x01,
        0x00, 0x00, 0x00, 0x04, 0x00, 0x00, 0x00, 0x0C,
        0x00, 0x0C, 0x00, 0x00, 0x00, 0x00, 0x00, 0x0F,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]
    var faceData: FaceImpl
    faceData.fontData.add(Cmap)
    faceData.tables.add({tag: TAG_CMAP, length: Cmap.count})

    var rejected: Swag.Error
    discard catch parseCMap(&faceData, false) as rejected
    Swag.require(rejected.value() != null)
}

// Format 8 groups BMP codes and packed UTF-16 surrogate pairs for supplementary scalars.
#test
{
    var cmap = makeCmap8Fixture(true)
    var faceData: FaceImpl
    faceData.fontData.add(cmap.toSlice())
    faceData.tables.add({tag: TAG_CMAP, length: cast(u32, cmap.count)})

    discard expect parseCMap(&faceData, false)
    Swag.require(faceData.cmapFormat == 8)
    Swag.require(expect lookupGlyphIndex(&faceData, 'B'u32) == 8)
    Swag.require(expect lookupGlyphIndex(&faceData, 0x1F600) == 20)
    Swag.require(expect lookupGlyphIndex(&faceData, 0x1F601) == 21)
    Swag.require(expect lookupGlyphIndex(&faceData, 0x1F602) == 0)

    var withoutFlag = makeCmap8Fixture(false)
    var unflagged: FaceImpl
    unflagged.fontData.add(withoutFlag.toSlice())
    unflagged.tables.add({tag: TAG_CMAP, length: cast(u32, withoutFlag.count)})
    discard expect parseCMap(&unflagged, false)
    Swag.require(expect lookupGlyphIndex(&unflagged, 0x1F600) == 0)

    var malformedCmap = makeCmap8Fixture(true)
    writeBigU32(&malformedCmap, 12 + 8204, 3)
    var malformed: FaceImpl
    malformed.fontData.add(malformedCmap.toSlice())
    malformed.tables.add({tag: TAG_CMAP, length: cast(u32, malformedCmap.count)})
    var rejected: Swag.Error
    discard catch parseCMap(&malformed, false) as rejected
    Swag.require(rejected.value() != null)
}

// A declared format-12 extent may not run past the containing cmap table.
#test
{
    const Cmap: [28] u8 = [
        0x00, 0x00, 0x00, 0x01,
        0x00, 0x00, 0x00, 0x04, 0x00, 0x00, 0x00, 0x0C,
        0x00, 0x0C, 0x00, 0x00, 0x00, 0x00, 0x00, 0x11,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]
    var faceData: FaceImpl
    faceData.fontData.add(Cmap)
    faceData.tables.add({tag: TAG_CMAP, length: Cmap.count})

    var rejected: Swag.Error
    discard catch parseCMap(&faceData, false) as rejected
    Swag.require(rejected.value() != null)
}

#test
{
    var faceScope: FaceScope
    faceScope.init()
    let face = unwrap faceScope.face

    let glyphA       = face.glyphIndex('A')
    let glyphE       = face.glyphIndex(0x00E9)
    let glyphMissing = face.glyphIndex(0x10FFFF)

    Swag.require(glyphA > 0)
    Swag.require(glyphE > 0)
    Swag.require(glyphMissing == 0)
}

// Format 0 is a flat 256-entry byte map, so a code beyond a byte has no glyph.
#test
{
    var cmap: Array'u8
    cmap.resize(6 + 256)
    cmap[1]        = 0x00     // format 0
    cmap[3]        = 0x06     // length 262, high byte in cmap[2]
    cmap[2]        = 0x01
    cmap[6 + 'A']  = 3
    cmap[6 + 0xE9] = 9

    let glyphA = lookupCMap0(cmap.toSlice(), 'A'u32)
    Swag.require(glyphA == 3)

    let glyphAccent = lookupCMap0(cmap.toSlice(), 0xE9)
    Swag.require(glyphAccent == 9)

    let glyphUnmapped = lookupCMap0(cmap.toSlice(), 'B'u32)
    Swag.require(glyphUnmapped == 0)

    let glyphBeyondByte = lookupCMap0(cmap.toSlice(), 0x0100)
    Swag.require(glyphBeyondByte == 0)
}

// Format 6 covers one contiguous run and nothing on either side of it.
#test
{
    let glyphA = lookupCMap6(Cmap6Fixture, 'A'u32)
    Swag.require(glyphA == 5)

    let glyphC = lookupCMap6(Cmap6Fixture, 'C'u32)
    Swag.require(glyphC == 7)

    let glyphBelow = lookupCMap6(Cmap6Fixture, '@'u32)
    Swag.require(glyphBelow == 0)

    let glyphAbove = lookupCMap6(Cmap6Fixture, 'D'u32)
    Swag.require(glyphAbove == 0)
}

// Format 13 folds a whole range onto one glyph instead of walking it.
#test
{
    let glyphA = lookupCMap13(Cmap13Fixture, 'A'u32)
    Swag.require(glyphA == 9)

    let glyphZ = lookupCMap13(Cmap13Fixture, 'Z'u32)
    Swag.require(glyphZ == 9)

    let glyphOutside = lookupCMap13(Cmap13Fixture, 'a'u32)
    Swag.require(glyphOutside == 0)
}

// A Unicode format-13 map folds each group onto one glyph and leaves gaps unmapped.
#test
{
    var faceData: FaceImpl
    expect parseTestCmap13(&faceData, makeCmap13Fixture())

    Swag.require(faceData.cmapFormat == 13)
    Swag.require(faceData.face.charMap.platformID == 0)
    Swag.require(faceData.face.charMap.encodingID == 4)
    Swag.require(expect lookupGlyphIndex(&faceData, 'A'u32) == 9)
    Swag.require(expect lookupGlyphIndex(&faceData, 'C'u32) == 9)
    Swag.require(expect lookupGlyphIndex(&faceData, 'E'u32) == 20)
    Swag.require(expect lookupGlyphIndex(&faceData, 'F'u32) == 20)
    Swag.require(expect lookupGlyphIndex(&faceData, 'G'u32) == 0)
    Swag.require(expect lookupGlyphIndex(&faceData, 'D'u32) == 0)
    Swag.require(expect lookupGlyphIndex(&faceData, 'Z'u32) == 0)
}

// Format-13 groups must fit their extent, be sorted and non-overlapping, and name
// either glyph zero (missing) or an existing glyph.
#test
{
    var malformed = makeCmap13Fixture()
    var faceData: FaceImpl
    faceData.face.setGlyphCount(32)

    // The declared groups exceed the Unicode subtable's available records.
    writeBigU32(&malformed, 72 + 12, 4)
    faceData.fontData.add(malformed.toSlice())
    faceData.tables.add({tag: TAG_CMAP, length: cast(u32, malformed.count)})
    var rejected: Swag.Error
    discard catch parseCMap(&faceData, false) as rejected
    Swag.require(rejected.value() != null)

    malformed         = makeCmap13Fixture()
    malformed[72 + 3] = 1
    var reserved: FaceImpl
    reserved.face.setGlyphCount(32)
    reserved.fontData.add(malformed.toSlice())
    reserved.tables.add({tag: TAG_CMAP, length: cast(u32, malformed.count)})
    rejected = {}
    discard catch parseCMap(&reserved, false) as rejected
    Swag.require(rejected.value() != null)

    malformed = makeCmap13Fixture()
    writeBigU32(&malformed, 72 + 28, 0x43)
    var overlapping: FaceImpl
    overlapping.face.setGlyphCount(32)
    overlapping.fontData.add(malformed.toSlice())
    overlapping.tables.add({tag: TAG_CMAP, length: cast(u32, malformed.count)})
    rejected = {}
    discard catch parseCMap(&overlapping, false) as rejected
    Swag.require(rejected.value() != null)

    malformed = makeCmap13Fixture()
    writeBigU32(&malformed, 72 + 32, 0x110000)
    var invalidUnicode: FaceImpl
    invalidUnicode.face.setGlyphCount(32)
    invalidUnicode.fontData.add(malformed.toSlice())
    invalidUnicode.tables.add({tag: TAG_CMAP, length: cast(u32, malformed.count)})
    rejected = {}
    discard catch parseCMap(&invalidUnicode, false) as rejected
    Swag.require(rejected.value() != null)

    malformed = makeCmap13Fixture()
    writeBigU32(&malformed, 72 + 36, 32)
    var invalidGlyph: FaceImpl
    invalidGlyph.face.setGlyphCount(32)
    invalidGlyph.fontData.add(malformed.toSlice())
    invalidGlyph.tables.add({tag: TAG_CMAP, length: cast(u32, malformed.count)})
    rejected = {}
    discard catch parseCMap(&invalidGlyph, false) as rejected
    Swag.require(rejected.value() != null)

    malformed = makeCmap13Fixture()
    writeBigU32(&malformed, 72 + 4, 56)
    var truncated: FaceImpl
    truncated.face.setGlyphCount(32)
    truncated.fontData.add(malformed.toSlice())
    truncated.tables.add({tag: TAG_CMAP, length: cast(u32, malformed.count)})
    rejected = {}
    discard catch parseCMap(&truncated, false) as rejected
    Swag.require(rejected.value() != null)
}

// Format 10 maps a trimmed range in the supplementary planes through a glyph array.
#test
{
    Swag.require(lookupCMap10(Cmap10Fixture, 0x1F600) == 7)
    Swag.require(lookupCMap10(Cmap10Fixture, 0x1F601) == 0)
    Swag.require(lookupCMap10(Cmap10Fixture, 0x1F602) == 9)
    Swag.require(lookupCMap10(Cmap10Fixture, 0x1F5FF) == 0)
    Swag.require(lookupCMap10(Cmap10Fixture, 0x1F603) == 0)

    var cmap: Array'u8
    cmap.add([
        0x00, 0x00, 0x00, 0x01,
        0x00, 0x00, 0x00, 0x04, 0x00, 0x00, 0x00, 0x0C])
    cmap.add(Cmap10Fixture)

    var faceData: FaceImpl
    faceData.fontData.add(cmap.toSlice())
    faceData.tables.add({tag: TAG_CMAP, length: cast(u32, cmap.count)})

    discard expect parseCMap(&faceData, false)
    Swag.require(faceData.cmapFormat == 10)
    Swag.require(expect lookupGlyphIndex(&faceData, 0x1F602) == 9)

    // The declared glyph array must fit within the format-10 subtable extent.
    writeBigU32(&cmap, 28, 4)
    var malformed: FaceImpl
    malformed.fontData.add(cmap.toSlice())
    malformed.tables.add({tag: TAG_CMAP, length: cast(u32, cmap.count)})
    var rejected: Swag.Error
    discard catch parseCMap(&malformed, false) as rejected
    Swag.require(rejected.value() != null)
}

// The subtable format outranks the platform score, so a Macintosh format-4 record
// wins over a Windows format-0 one even though the platform prefers Windows.
#test
{
    var cmap: Array'u8
    cmap.add([
        0x00, 0x00, 0x00, 0x02,
        0x00, 0x03, 0x00, 0x01, 0x00, 0x00, 0x00, 0x14,      // Windows, format 0 below
        0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x01, 0x1A])     // Macintosh, format 4 below
    cmap.resize(20 + 6 + 256)
    cmap[20 + 3] = 0x06
    cmap[20 + 2] = 0x01
    cmap.add(Cmap4Fixture)

    var faceData: FaceImpl
    faceData.fontData.add(cmap.toSlice())
    faceData.tables.add({tag: TAG_CMAP, length: cast(u32, cmap.count)})

    discard expect parseCMap(&faceData, false)
    Swag.require(faceData.cmapFormat == 4)
    Swag.require(faceData.face.charMap.platformID == 1)
}

// A format-14 subtable supplements the selected map instead of competing with it.
#test
{
    var faceData: FaceImpl
    faceData.fontData.add(CmapVariationFixture)
    faceData.tables.add({tag: TAG_CMAP, length: CmapVariationFixture.count})

    discard expect parseCMap(&faceData, false)
    Swag.require(faceData.cmapFormat == 4)
    Swag.require(faceData.face.charMap.platformID == 3)
    Swag.require(faceData.variationCMap != null)

    // U+FE0F names a distinct glyph for U+0042 and nothing for U+0041.
    let variant = expect lookupVariationGlyph(&faceData, 0x42, 0xFE0F)
    Swag.require(variant == 42)

    let unregistered = expect lookupVariationGlyph(&faceData, 0x41, 0xFE0F)
    Swag.require(unregistered == 0)

    // U+FE0E declares U+0041 through U+0043 to keep their default glyph, so the
    // sequence exists but resolves through the ordinary map.
    let byDefault = expect lookupVariationGlyph(&faceData, 0x41, 0xFE0E)
    Swag.require(byDefault == 0)

    Swag.require(expect hasVariationSequence(&faceData, 0x41, 0xFE0E))
    Swag.require(expect hasVariationSequence(&faceData, 0x43, 0xFE0E))
    Swag.require(not expect hasVariationSequence(&faceData, 0x44, 0xFE0E))
    Swag.require(expect hasVariationSequence(&faceData, 0x42, 0xFE0F))
    Swag.require(not expect hasVariationSequence(&faceData, 0x41, 0xFF01))
}

// A face declaring no variation sequence ignores the selector rather than losing
// the character it qualifies.
#test
{
    var faceScope: FaceScope
    faceScope.init("arial.ttf")
    let face = unwrap faceScope.face

    Swag.require(not face.hasVariant('A', 0xFE0F))
    Swag.require(face.glyphIndexVariant('A', 0xFE0F) == face.glyphIndex('A'))
    Swag.require(face.glyphIndexVariant('A', 0xFE0F) > 0)
}
