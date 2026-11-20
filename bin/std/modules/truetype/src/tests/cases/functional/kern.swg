#global if #command == Swag.CompilerCommand.Test

using Swag, Core

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
    Swag.require(faceData.kernPairs.isEmpty())
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
    Swag.require(not faceData.kernPairs.isEmpty())

    // A comma tucked under a 'P' is one of 191 ASCII pairs the legacy table states
    // outright and the pair-adjustment lookups leave at zero.
    let glyphP     = face.glyphIndex('P')
    let glyphComma = face.glyphIndex(',')
    let fromGpos   = lookupGposKerning(faceData, cast(u16, glyphP), cast(u16, glyphComma))
    Swag.require(fromGpos == 0)
    let legacyUnits = faceData.kernPairs.tryFind((glyphP << 16) | glyphComma)?.value orelse 0
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
