#global if #command == Swag.CompilerCommand.Test

using Swag, Core

#test
{
    var faceData: FaceImpl
    faceData.face.setGlyphCount(9)
    faceData.syntheticCMap.add('A'u32, 8)
    faceData.syntheticCMap.add('B'u32, 9)

    Swag.require(expect lookupGlyphIndex(&faceData, 'A'u32) == 8)
    Swag.require(expect lookupGlyphIndex(&faceData, 'B'u32) == 0)
}

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

func parseTestCmap(faceData: *FaceImpl, cmap: Array'u8) fail
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

// Format 4's segment arrays must fit in its declared subtable length.
#test
{
    var cmap: Array'u8
    cmap.add([
        0x00, 0x00, 0x00, 0x01,
        0x00, 0x03, 0x00, 0x01, 0x00, 0x00, 0x00, 0x0C])
    cmap.add(Cmap4Fixture)
    writeBigU16(&cmap, 14, 18)

    var faceData: FaceImpl
    faceData.fontData.add(cmap.toSlice())
    faceData.tables.add({tag: TAG_CMAP, length: cast(u32, cmap.count)})

    var rejected: Swag.Error
    discard catch parseCMap(&faceData, false) as rejected
    Swag.require(rejected.value() != null)
}

#test
{
    let glyph0 = lookupCMap12(Cmap12Fixture, 0x00010000)
    Swag.require(glyph0 == 7)

    let glyph1 = lookupCMap12(Cmap12Fixture, 0x00010001)
    Swag.require(glyph1 == 0)
}

// Format 6's glyph array must fit within the subtable's declared length.
#test
{
    var cmap: Array'u8
    cmap.add([
        0x00, 0x00, 0x00, 0x01,
        0x00, 0x03, 0x00, 0x01, 0x00, 0x00, 0x00, 0x0C])
    cmap.add(Cmap6Fixture)
    writeBigU16(&cmap, 14, 12)

    var faceData: FaceImpl
    faceData.fontData.add(cmap.toSlice())
    faceData.tables.add({tag: TAG_CMAP, length: cast(u32, cmap.count)})

    var rejected: Swag.Error
    discard catch parseCMap(&faceData, false) as rejected
    Swag.require(rejected.value() != null)
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
    faceData.face.setGlyphCount(22)

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
    unflagged.face.setGlyphCount(22)
    discard expect parseCMap(&unflagged, false)
    Swag.require(expect lookupGlyphIndex(&unflagged, 0x1F600) == 0)

    var malformedCmap = makeCmap8Fixture(true)
    writeBigU32(&malformedCmap, 12 + 8204, 3)
    var malformed: FaceImpl
    malformed.fontData.add(malformedCmap.toSlice())
    malformed.tables.add({tag: TAG_CMAP, length: cast(u32, malformedCmap.count)})
    malformed.face.setGlyphCount(22)
    var rejected: Swag.Error
    discard catch parseCMap(&malformed, false) as rejected
    Swag.require(rejected.value() != null)
}

// Format-8 groups must be ordered, encode valid BMP values or surrogate pairs,
// and map only glyphs present in the face.
#test
{
    var cmap        = makeCmap8Fixture(true)
    let groupOffset = 12'u64 + 8208 + 12

    // The second group's start overlaps the first group's end.
    writeBigU32(&cmap, groupOffset, 'C'u32)
    writeBigU32(&cmap, groupOffset + 4, 'C'u32)
    var faceData: FaceImpl
    faceData.fontData.add(cmap.toSlice())
    faceData.tables.add({tag: TAG_CMAP, length: cast(u32, cmap.count)})
    faceData.face.setGlyphCount(22)
    var rejected: Swag.Error
    discard catch parseCMap(&faceData, false) as rejected
    Swag.require(rejected.value() != null)

    cmap = makeCmap8Fixture(true)
    writeBigU32(&cmap, groupOffset + 4, 0xD83D_D800)
    var invalidPair: FaceImpl
    invalidPair.fontData.add(cmap.toSlice())
    invalidPair.tables.add({tag: TAG_CMAP, length: cast(u32, cmap.count)})
    invalidPair.face.setGlyphCount(22)
    rejected = {}
    discard catch parseCMap(&invalidPair, false) as rejected
    Swag.require(rejected.value() != null)

    cmap = makeCmap8Fixture(true)
    writeBigU32(&cmap, groupOffset + 8, 21)
    var missingGlyph: FaceImpl
    missingGlyph.fontData.add(cmap.toSlice())
    missingGlyph.tables.add({tag: TAG_CMAP, length: cast(u32, cmap.count)})
    missingGlyph.face.setGlyphCount(22)
    rejected = {}
    discard catch parseCMap(&missingGlyph, false) as rejected
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

// Group validation covers adjacent SIMD batches, the final tail, and both glyph rules.
#test
{
    const GroupCount = 9'u32
    const Records    = 28'u64
    const RecordSize = 12'u64
    for format in [12'u16, 13'u16]
    {
        var cmap: Array'u8
        cmap.add([0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x04, 0x00, 0x00, 0x00, 0x0C])
        cmap.resize(Records + GroupCount * RecordSize)
        writeBigU16(&cmap, 12, format)
        writeBigU32(&cmap, 16, 16 + GroupCount * 12)
        writeBigU32(&cmap, 24, GroupCount)
        for group in GroupCount
        {
            let record = Records + group * RecordSize
            writeBigU32(&cmap, record, cast(u32, 2 * group))
            writeBigU32(&cmap, record + 4, cast(u32, 2 * group + 1))
            writeBigU32(&cmap, record + 8, cast(u32, group + 1))
        }

        var valid: FaceImpl
        expect parseTestCmap(&valid, cmap)
        Swag.require(expect lookupGlyphIndex(&valid, 0) == 1)
        Swag.require(expect lookupGlyphIndex(&valid, 9) == (format == 12 ? 6 : 5))

        const Changes = [
            {offset: Records + 4 * RecordSize,     value: 7'u32},
            {offset: Records + 1 * RecordSize + 8, value: Swag.U32.Max},
            {offset: Records + 8 * RecordSize + 4, value: 0x110000'u32}]
        for change in Changes
        {
            var malformed = cmap
            writeBigU32(&malformed, change.offset, change.value)
            var face:     FaceImpl
            var rejected: Swag.Error
            catch parseTestCmap(&face, malformed) as rejected
            Swag.require(rejected.value() != null)
        }

        writeBigU32(&cmap, Records + 5 * RecordSize + 8, 31)
        var limit:    FaceImpl
        var rejected: Swag.Error
        catch parseTestCmap(&limit, cmap) as rejected
        Swag.require((rejected.value() != null) == (format == 12))
    }
}

// A Unicode format-13 map folds each group onto one glyph and leaves gaps unmapped.
#test
{
    var faceData: FaceImpl
    expect parseTestCmap(&faceData, makeCmap13Fixture())

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
    faceData.face.setGlyphCount(10)

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

    // A mapped index outside the face resolves to the conventional missing glyph.
    writeBigU32(&cmap, 28, 3)
    var invalidGlyph: FaceImpl
    invalidGlyph.fontData.add(cmap.toSlice())
    invalidGlyph.tables.add({tag: TAG_CMAP, length: cast(u32, cmap.count)})
    invalidGlyph.face.setGlyphCount(9)
    discard expect parseCMap(&invalidGlyph, false)
    Swag.require(expect lookupGlyphIndex(&invalidGlyph, 0x1F602) == 0)
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

// Format-14 selector records and their nested lists stay within the declared extent.
#test
{
    var malformed: Array'u8
    malformed.add(CmapVariationFixture)
    writeBigU32(&malformed, 54, 30)     // Two selector records need at least 32 bytes.

    var shortRecords: FaceImpl
    shortRecords.fontData.add(malformed.toSlice())
    shortRecords.tables.add({tag: TAG_CMAP, length: cast(u32, malformed.count)})
    var rejected: Swag.Error
    discard catch parseCMap(&shortRecords, false) as rejected
    Swag.require(rejected.value() != null)

    malformed = {}
    malformed.add(CmapVariationFixture)
    writeBigU32(&malformed, 65, 48)     // The default range count cannot fit at this offset.

    var shortList: FaceImpl
    shortList.fontData.add(malformed.toSlice())
    shortList.tables.add({tag: TAG_CMAP, length: cast(u32, malformed.count)})
    rejected = {}
    discard catch parseCMap(&shortList, false) as rejected
    Swag.require(rejected.value() != null)
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

// Two faces can share a cmap range and declare different glyph counts.
#test
{
    var cmap: Array'u8
    cmap.add([
        0x00, 0x00, 0x00, 0x01,
        0x00, 0x00, 0x00, 0x04, 0x00, 0x00, 0x00, 0x0C])
    cmap.add(Cmap12Fixture)
    let source = FontSource.copy(cmap.toSlice())

    var first: FaceImpl
    first.fontSource = source
    first.tables.add({tag: TAG_CMAP, length: cast(u32, cmap.count)})
    first.face.setGlyphCount(8)
    expect parseCMap(&first, false)
    Swag.require(first.cmapFormat == 12)
    Swag.require(expect lookupGlyphIndex(&first, 0x10000) == 7)

    var second: FaceImpl
    second.fontSource = source
    second.tables.add({tag: TAG_CMAP, length: cast(u32, cmap.count)})
    second.face.setGlyphCount(7)
    var rejected: Swag.Error
    discard catch parseCMap(&second, false) as rejected
    Swag.require(rejected.value() != null)

    second.face.setGlyphCount(8)
    expect parseCMap(&second, false)
    Swag.require(second.cmapFormat == 12)
    Swag.require(expect lookupGlyphIndex(&second, 0x10000) == 7)
}

// Visiting a grouped map skips glyph zero and the surrogate interval.
#test
{
    var cmap: Array'u8
    cmap.resize(12 + 16 + 36)
    cmap[3]  = 1
    cmap[7]  = 4
    cmap[11] = 12
    writeBigU16(&cmap, 12, 12)
    writeBigU32(&cmap, 16, 52)
    writeBigU32(&cmap, 24, 3)
    writeBigU32(&cmap, 28, 0x41)
    writeBigU32(&cmap, 32, 0x43)
    writeBigU32(&cmap, 40, 0xD7FF)
    writeBigU32(&cmap, 44, 0xE001)
    writeBigU32(&cmap, 48, 10)
    writeBigU32(&cmap, 52, 0x1F600)
    writeBigU32(&cmap, 56, 0x1F601)
    writeBigU32(&cmap, 60, 4)

    var faceData: FaceImpl
    faceData.fontData.add(cmap.toSlice())
    faceData.tables.add({tag: TAG_CMAP, length: cast(u32, cmap.count)})
    faceData.face.setGlyphCount(3000)
    expect parseCMap(&faceData, false)

    var characters: Array'rune
    var glyphs:     Array'u32
    faceData.face.visitCharacters(0, func|&characters, &glyphs|(character: rune, glyphIndex: u32)->bool
    {
        characters.add(character)
        glyphs.add(glyphIndex)
        return true
    })

    const Expected: [7] rune = ['B', 'C', cast(rune, 0xD7FF), cast(rune, 0xE000),
                                cast(rune, 0xE001), cast(rune, 0x1F600), cast(rune, 0x1F601)]
    Swag.require(Slice.equals(characters.toSlice(), cast(const [..] rune, Expected)))
    for character, index in characters do
        Swag.require(glyphs[index] == faceData.face.glyphIndex(character))

    var visited = 0'u32
    faceData.face.visitCharacters(0xD800, func|&visited|(character: rune, glyphIndex: u32)->bool
    {
        Swag.require(character == 0xE000 and glyphIndex == 2059)
        visited += 1
        return false
    })
    Swag.require(visited == 1)
}

// Format 13 visits aliases and skips groups that map to the missing glyph.
#test
{
    var faceData: FaceImpl
    expect parseTestCmap(&faceData, makeCmap13Fixture())
    var codes:  Array'rune
    var glyphs: Array'u32
    faceData.face.visitCharacters('B', func|&codes, &glyphs|(character: rune, glyphIndex: u32)->bool
    {
        codes.add(character)
        glyphs.add(glyphIndex)
        return true
    })
    const Codes:  [4] rune = ['B', 'C', 'E', 'F']
    const Glyphs: [4] u32  = [9, 9, 20, 20]
    Swag.require(Slice.equals(codes.toSlice(), cast(const [..] rune, Codes)))
    Swag.require(Slice.equals(glyphs.toSlice(), cast(const [..] u32, Glyphs)))
}

// Format-4 visitation agrees with lookup for array entries, deltas and overlapping segments.
#test
{
    const Subtable = 12'u64
    var cmap: Array'u8
    cmap.resize(Subtable + 48)
    cmap[3]  = 1
    cmap[5]  = 3
    cmap[7]  = 1
    cmap[11] = 12
    writeBigU16(&cmap, Subtable, 4)
    writeBigU16(&cmap, Subtable + 2, 48)
    writeBigU16(&cmap, Subtable + 6, 6)
    writeBigU16(&cmap, Subtable + 14, 0x44)
    writeBigU16(&cmap, Subtable + 16, 0x45)
    writeBigU16(&cmap, Subtable + 18, 0xFFFF)
    writeBigU16(&cmap, Subtable + 22, 0x41)
    writeBigU16(&cmap, Subtable + 24, 0x43)
    writeBigU16(&cmap, Subtable + 26, 0xFFFF)
    writeBigU16(&cmap, Subtable + 28, 2)
    writeBigU16(&cmap, Subtable + 30, 0xFFC6)
    writeBigU16(&cmap, Subtable + 32, 1)
    writeBigU16(&cmap, Subtable + 34, 6)
    writeBigU16(&cmap, Subtable + 40, 2)
    writeBigU16(&cmap, Subtable + 44, 4)
    writeBigU16(&cmap, Subtable + 46, 0xFFFF)

    for attempt in 2
    {
        if attempt
        {
            // Older faces can carry unusual segment order. Keep their lookup results.
            writeBigU16(&cmap, Subtable + 14, 0x45)
            writeBigU16(&cmap, Subtable + 16, 0x44)
        }

        var faceData: FaceImpl
        expect parseTestCmap(&faceData, cmap)
        var expected: Array'rune
        for code in 0x42'u32 to 0x45
        {
            let character = cast(rune, code)
            if faceData.face.glyphIndex(character) do
                expected.add(character)
        }

        if not attempt
        {
            const Codes: [3] rune = ['C', 'D', 'E']
            Swag.require(Slice.equals(expected.toSlice(), cast(const [..] rune, Codes)))
        }

        let face = &faceData.face
        var visited: Array'rune
        face.visitCharacters(0x42, func|face, &visited|(character: rune, glyphIndex: u32)->bool
        {
            Swag.require(face.glyphIndex(character) == glyphIndex)
            visited.add(character)
            return true
        })
        Swag.require(Slice.equals(visited.toSlice(), expected.toSlice()))
    }
}
