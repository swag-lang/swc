#global if #command == Swag.CompilerCommand.Test

using Swag, Core

func writePairPosition(table: *Array'u8, offset: u64, xAdvance: s16)
{
    writeBigU16(table, offset + 0, 1)          // PairPos format 1.
    writeBigU16(table, offset + 2, 18)         // Coverage follows the pair set.
    writeBigU16(table, offset + 4, 0x0004)     // XAdvance in the first glyph's value record.
    writeBigU16(table, offset + 6, 0)
    writeBigU16(table, offset + 8, 1)     // One pair set.
    writeBigU16(table, offset + 10, 12)
    writeBigU16(table, offset + 12, 1)     // One pair value.
    writeBigU16(table, offset + 14, 2)     // Second glyph.
    writeBigU16(table, offset + 16, cast #bit(u16, xAdvance))
    writeBigU16(table, offset + 18, 1)     // Coverage format 1.
    writeBigU16(table, offset + 20, 1)
    writeBigU16(table, offset + 22, 1)     // First glyph.
}

func writeZeroClassPairPosition(table: *Array'u8, offset: u64)
{
    writeBigU16(table, offset + 0, 2)
    writeBigU16(table, offset + 2, 34)
    writeBigU16(table, offset + 4, 0x0004)
    writeBigU16(table, offset + 6, 0)
    writeBigU16(table, offset + 8, 18)
    writeBigU16(table, offset + 10, 26)
    writeBigU16(table, offset + 12, 1)
    writeBigU16(table, offset + 14, 1)

    writeBigU16(table, offset + 16, 0)     // The only class-pair adjustment is zero.
    writeBigU16(table, offset + 18, 1)     // First class definition, format 1.
    writeBigU16(table, offset + 20, 1)
    writeBigU16(table, offset + 22, 1)
    writeBigU16(table, offset + 24, 0)
    writeBigU16(table, offset + 26, 1)     // Second class definition, format 1.
    writeBigU16(table, offset + 28, 2)
    writeBigU16(table, offset + 30, 1)
    writeBigU16(table, offset + 32, 0)

    writeBigU16(table, offset + 34, 1)     // Coverage format 1.
    writeBigU16(table, offset + 36, 1)
    writeBigU16(table, offset + 38, 1)
}

func makeGposKernFixture()->Array'u8
{
    var table: #returntype
    table.resize(96)

    writeBigU16(&table, 0, 1)      // GPOS version 1.0.
    writeBigU16(&table, 6, 10)     // FeatureList offset.
    writeBigU16(&table, 8, 26)     // LookupList offset.

    writeBigU16(&table, 10, 1)     // One feature record.
    writeBigU32(&table, 12, TAG_KERN)
    writeBigU16(&table, 16, 8)     // Feature table offset.
    writeBigU16(&table, 18, 0)     // FeatureParams.
    writeBigU16(&table, 20, 2)     // Two lookups, deliberately listed in reverse order.
    writeBigU16(&table, 22, 1)
    writeBigU16(&table, 24, 0)

    writeBigU16(&table, 26, 2)     // Two lookups in LookupList order.
    writeBigU16(&table, 28, 6)
    writeBigU16(&table, 30, 38)

    for offset in [32, 64]
    {
        writeBigU16(&table, offset + 0, GPOS_LOOKUP_PAIR)
        writeBigU16(&table, offset + 2, 0)     // LookupFlags.
        writeBigU16(&table, offset + 4, 1)     // One subtable.
        writeBigU16(&table, offset + 6, 8)
    }

    writePairPosition(&table, 40, -60)
    writePairPosition(&table, 72, 10)
    return table
}

// Positioning adjustments from separate lookups accumulate in LookupList order.
#test
{
    var table = makeGposKernFixture()
    var faceData: FaceImpl
    faceData.fontData.add(table.toSlice())
    faceData.tables.add({tag: TAG_GPOS, offset: 0, length: cast(u32, table.count)})
    expect parseGpos(&faceData)

    Swag.require(faceData.gposPairLookups.count == 2)
    Swag.require(faceData.gposPairSubtables[0] < faceData.gposPairSubtables[1])
    Swag.require(lookupGposKerning(&faceData, 1, 2) == -50)

    table = makeGposKernFixture()
    writePairPosition(&table, 40, 30_000)
    writePairPosition(&table, 72, 10_000)
    var clampedFace: FaceImpl
    clampedFace.fontData.add(table.toSlice())
    clampedFace.tables.add({tag: TAG_GPOS, offset: 0, length: cast(u32, table.count)})
    expect parseGpos(&clampedFace)
    Swag.require(lookupGposKerning(&clampedFace, 1, 2) == Swag.S16.Max)
}

// GPOS lookup selection covers every possible u16 index without linear searches.
#test
{
    var table: Array'u8
    table.resize(26)
    writeBigU16(&table, 10, 1)     // One feature record.
    writeBigU32(&table, 12, TAG_KERN)
    writeBigU16(&table, 16, 8)     // Feature table offset.
    writeBigU16(&table, 18, 0)     // FeatureParams.
    writeBigU16(&table, 20, 2)     // Two lookup indices.
    writeBigU16(&table, 22, 0)
    writeBigU16(&table, 24, Swag.U16.Max)

    let selected = expect collectKernLookups(table.toSlice(), 10)
    Swag.require(selected.count == GPOS_LOOKUP_BITMAP_WORDS)
    Swag.require(hasKernLookup(selected.toSlice(), 0))
    Swag.require(hasKernLookup(selected.toSlice(), Swag.U16.Max))
    Swag.require(not hasKernLookup(selected.toSlice(), 1))
}

// A matching zero adjustment ends subtable selection for its lookup.
#test
{
    var table: Array'u8
    table.resize(48)
    writePairPosition(&table, 0, 0)
    writePairPosition(&table, 24, -40)

    var faceData: FaceImpl
    faceData.gposTable = table.toSlice()
    faceData.gposPairSubtables.add(0)
    faceData.gposPairSubtables.add(24)
    faceData.gposPairLookups.add({firstSubtable: 0, subtableCount: 2})

    Swag.require(lookupGposKerning(&faceData, 1, 2) == 0)
}

// A zero class-matrix adjustment also matches and ends subtable selection.
#test
{
    var table: Array'u8
    table.resize(64)
    writeZeroClassPairPosition(&table, 0)
    writePairPosition(&table, 40, -40)

    var faceData: FaceImpl
    faceData.gposTable = table.toSlice()
    faceData.gposPairSubtables.add(0)
    faceData.gposPairSubtables.add(40)
    faceData.gposPairLookups.add({firstSubtable: 0, subtableCount: 2})

    Swag.require(lookupGposKerning(&faceData, 1, 2) == 0)
}

// A format-0 kern subtable cannot read pair records beyond its declared length,
// even when the overall table contains enough trailing bytes for that record.
#test
{
    var bytes: Array'u8
    bytes.add([
        0x00, 0x00, 0x00, 0x01,     // version, subtable count
        0x00, 0x00, 0x00, 0x0E, 0x00, 0x01,      // format, length, horizontal coverage
        0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,     // one pair, search fields
        0x00, 0x01, 0x00, 0x02, 0xFF, 0x38])     // pair is outside declared length

    var faceData: FaceImpl
    faceData.fontData.add(bytes.toSlice())
    faceData.tables.add({tag: TAG_KERN, offset: 0, length: cast(u32, bytes.count)})
    expect parseKern(&faceData)
    Swag.require(not faceData.face.hasKerning())
}

#test
{
    var faceScope: FaceScope
    faceScope.init("arial.ttf")
    let face = unwrap faceScope.face

    let glyphA = face.glyphIndex('A')
    let glyphV = face.glyphIndex('V')
    Swag.require(glyphA > 0)
    Swag.require(glyphV > 0)

    // The design-unit API works before a size is selected.
    let designUnits = face.getKerningDesignUnits(glyphA, glyphV)
    Swag.require(designUnits == -152)

    discard expect face.setPixelSize(0, 100)

    // 'AV' is a classic negative kerning pair (glyphs tucked closer together).
    let kern100 = face.getKerning(glyphA, glyphV)
    Swag.require(kern100.x < 0)
    Swag.require(face.getKerningDesignUnits(glyphA, glyphV) == designUnits)

    // Kerning is scaled to the pixel size, so it grows with the size.
    discard catch face.setPixelSize(0, 200)
    let kern200 = face.getKerning(glyphA, glyphV)
    Swag.require(kern200.x < kern100.x)
    Swag.require(face.getKerningDesignUnits(glyphA, glyphV) == designUnits)

    // A missing glyph yields no kerning.
    let none = face.getKerning(glyphA, 0)
    Swag.require(none.x == 0)
    Swag.require(face.getKerningDesignUnits(glyphA, 0) == 0)
    Swag.require(face.getKerningDesignUnits(face.glyphCount, glyphV) == 0)
}

// Arial declares its kerning in the GPOS 'kern' feature, so that is what answers.
// The pair reaches a class-based subtable through an extension lookup, and Arial's
// legacy 'kern' table agrees with it at -152 design units.
#test
{
    var faceScope: FaceScope
    faceScope.init("arial.ttf")
    let face     = unwrap faceScope.face
    let faceData = getFaceData(face)

    Swag.require(face.hasKerning())
    Swag.require(not faceData.gposPairSubtables.isEmpty())

    let glyphA = face.glyphIndex('A')
    let glyphV = face.glyphIndex('V')
    let units  = lookupGposKerning(faceData, cast(u16, glyphA), cast(u16, glyphV))
    Swag.require(units == -152)

    // An unkerned pair is covered by the same subtable and adjusts by nothing.
    let glyphH = face.glyphIndex('H')
    let flat   = lookupGposKerning(faceData, cast(u16, glyphH), cast(u16, glyphH))
    Swag.require(flat == 0)
}

// Segoe UI reaches explicit pair sets as well as class matrices. This Arabic pair
// sits in a format-1 subtable and moves the glyphs apart rather than together.
#test
{
    var faceScope: FaceScope
    faceScope.init("segoeui.ttf")
    let face     = unwrap faceScope.face
    let faceData = getFaceData(face)

    let glyphLeft  = face.glyphIndex(0xFE84)
    let glyphRight = face.glyphIndex(0x0622)
    Swag.require(glyphLeft > 0)
    Swag.require(glyphRight > 0)

    let units = lookupGposKerning(faceData, cast(u16, glyphLeft), cast(u16, glyphRight))
    Swag.require(units == 171)

    discard expect face.setPixelSize(0, 100)
    let scaled = face.getKerning(glyphLeft, glyphRight)
    Swag.require(scaled.x > 0)
}

// Segoe UI states most of its pairs behind contextual lookups this module does not
// run, so its legacy 'kern' table has to keep answering for them. Dropping the
// fallback would silently unkern thousands of pairs.
#test
{
    var faceScope: FaceScope
    faceScope.init("segoeui.ttf")
    let face     = unwrap faceScope.face
    let faceData = getFaceData(face)

    Swag.require(not faceData.gposPairSubtables.isEmpty())

    // A comma tucked under a 'P' is one of 191 ASCII pairs the legacy table states
    // outright and the pair-adjustment lookups leave at zero.
    let glyphP     = face.glyphIndex('P')
    let glyphComma = face.glyphIndex(',')
    let fromGpos   = lookupGposKerning(faceData, cast(u16, glyphP), cast(u16, glyphComma))
    Swag.require(fromGpos == 0)
    let legacyUnits = lookupLegacyKerning(faceData, (glyphP << 16) | glyphComma)
    let designUnits = face.getKerningDesignUnits(glyphP, glyphComma)
    Swag.require(legacyUnits < 0 and designUnits == legacyUnits)

    discard expect face.setPixelSize(0, 100)
    let legacy100 = face.getKerning(glyphP, glyphComma)
    Swag.require(legacy100.x < 0)
    Swag.require(face.getKerningDesignUnits(glyphP, glyphComma) == designUnits)
    discard expect face.setPixelSize(0, 200)
    let legacy200 = face.getKerning(glyphP, glyphComma)
    Swag.require(legacy200.x < legacy100.x)
    Swag.require(face.getKerningDesignUnits(glyphP, glyphComma) == designUnits)

    // Where both state a pair, GPOS is the one that answers.
    let glyphA   = face.glyphIndex('A')
    let glyphV   = face.glyphIndex('V')
    let bothHave = lookupGposKerning(faceData, cast(u16, glyphA), cast(u16, glyphV))
    Swag.require(bothHave != 0)
}

// A glyph index no font can hold is answered rather than truncated into a real one.
#test
{
    var faceScope: FaceScope
    faceScope.init("arial.ttf")
    let face = unwrap faceScope.face

    discard expect face.setPixelSize(0, 100)
    let beyondU16 = face.getKerning(0x1_0024, face.glyphIndex('V'))
    Swag.require(beyondU16.x == 0)
    Swag.require(face.getKerningDesignUnits(0x1_0024, face.glyphIndex('V')) == 0)
}

// Disordered or repeated legacy pairs retain the last nonzero adjustment.
#test
{
    const Bytes: [36] u8 = [
        0, 0, 0, 1,
        0, 0, 0, 32, 0, 1,
        0, 3, 0, 0, 0, 0, 0, 0,
        0, 1, 0, 2, 0, 8,
        0, 1, 0, 1, 0, 4,
        0, 1, 0, 2, 0xFF, 0xFE]
    var faceData: FaceImpl
    faceData.fontData.add(Bytes)
    faceData.tables.add({tag: TAG_KERN, offset: 0, length: Bytes.count})
    expect parseKern(&faceData)
    Swag.require(faceData.face.hasKerning())
    Swag.require(lookupLegacyKerning(&faceData, 0x0001_0001) == 4)
    Swag.require(lookupLegacyKerning(&faceData, 0x0001_0002) == -2)
}

// Packed validation keeps key zero, tests group boundaries, and sees nonzero values in the group.
#test
{
    const Pairs     = 9'u32
    const PairStart = 18'u64
    var bytes: Array'u8
    bytes.resize(PairStart + Pairs * 6)
    writeBigU16(&bytes, 2, 1)
    writeBigU16(&bytes, 6, 14 + Pairs * 6)
    writeBigU16(&bytes, 8, 1)
    writeBigU16(&bytes, 10, Pairs)
    for index in Pairs do
        writeBigU32(&bytes, PairStart + index * 6, cast(u32, index))
    writeBigU16(&bytes, PairStart + 4, 0xFFF0)

    for duplicate in 2
    {
        if duplicate
        {
            writeBigU32(&bytes, PairStart + 4 * 6, 3)
            writeBigU16(&bytes, PairStart + 4 * 6 + 4, 9)
        }

        var faceData: FaceImpl
        faceData.fontData.add(bytes.toSlice())
        faceData.tables.add({tag: TAG_KERN, length: cast(u32, bytes.count)})
        expect parseKern(&faceData)
        if duplicate
        {
            Swag.require(faceData.kernData == null)
            Swag.require(faceData.kernPairs.getOrDefault(3, 0) == 9)
        }
        else
        {
            let packed = unwrap faceData.kernData
            Swag.require((expect readS16(packed, 4)) == -16)
            Swag.require(faceData.kernPairs.isEmpty())
        }
    }
}
