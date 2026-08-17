#global if #command == Swag.CompilerCommand.Test

using Swag, Core

#test
{
    var scope: FaceScope
    scope.init("arial.ttf")
    let face = scope.face!

    let glyphA = face.glyphIndex('A')
    let glyphV = face.glyphIndex('V')
    @assert(glyphA > 0)
    @assert(glyphV > 0)

    discard expect face.setPixelSize(0, 100)

    // 'AV' is a classic negative kerning pair (glyphs tucked closer together).
    let kern100 = face.getKerning(glyphA, glyphV)
    @assert(kern100.x < 0)

    // Kerning is scaled to the pixel size, so it grows with the size.
    discard catch face.setPixelSize(0, 200)
    let kern200 = face.getKerning(glyphA, glyphV)
    @assert(kern200.x < kern100.x)

    // A missing glyph yields no kerning.
    let none = face.getKerning(glyphA, 0)
    @assert(none.x == 0)
}

// Arial declares its kerning in the GPOS 'kern' feature, so that is what answers.
// The pair reaches a class-based subtable through an extension lookup, and Arial's
// legacy 'kern' table agrees with it at -152 design units.
#test
{
    var scope: FaceScope
    scope.init("arial.ttf")
    let face     = scope.face!
    let faceData = getFaceData(face)

    @assert(face.hasKerning())
    @assert(faceData.gposPairSubtables.count > 0)

    let glyphA = face.glyphIndex('A')
    let glyphV = face.glyphIndex('V')
    let units  = expect lookupGposKerning(faceData, cast(u16) glyphA, cast(u16) glyphV)
    @assert(units == -152)

    // An unkerned pair is covered by the same subtable and adjusts by nothing.
    let glyphH = face.glyphIndex('H')
    let flat   = expect lookupGposKerning(faceData, cast(u16) glyphH, cast(u16) glyphH)
    @assert(flat == 0)
}

// Segoe UI reaches explicit pair sets as well as class matrices. This Arabic pair
// sits in a format-1 subtable and moves the glyphs apart rather than together.
#test
{
    var scope: FaceScope
    scope.init("segoeui.ttf")
    let face     = scope.face!
    let faceData = getFaceData(face)

    let glyphLeft  = face.glyphIndex(0xFE84)
    let glyphRight = face.glyphIndex(0x0622)
    @assert(glyphLeft > 0)
    @assert(glyphRight > 0)

    let units = expect lookupGposKerning(faceData, cast(u16) glyphLeft, cast(u16) glyphRight)
    @assert(units == 171)

    discard expect face.setPixelSize(0, 100)
    let scaled = face.getKerning(glyphLeft, glyphRight)
    @assert(scaled.x > 0)
}

// Segoe UI states most of its pairs behind contextual lookups this module does not
// run, so its legacy 'kern' table has to keep answering for them. Dropping the
// fallback would silently unkern thousands of pairs.
#test
{
    var scope: FaceScope
    scope.init("segoeui.ttf")
    let face     = scope.face!
    let faceData = getFaceData(face)

    @assert(faceData.gposPairSubtables.count > 0)
    @assert(faceData.kernPairs.count > 0)

    discard expect face.setPixelSize(0, 100)

    // A comma tucked under a 'P' is one of 191 ASCII pairs the legacy table states
    // outright and the pair-adjustment lookups leave at zero.
    let glyphP     = face.glyphIndex('P')
    let glyphComma = face.glyphIndex(',')
    let fromGpos   = expect lookupGposKerning(faceData, cast(u16) glyphP, cast(u16) glyphComma)
    @assert(fromGpos == 0)
    @assert(face.getKerning(glyphP, glyphComma).x < 0)

    // Where both state a pair, GPOS is the one that answers.
    let glyphA   = face.glyphIndex('A')
    let glyphV   = face.glyphIndex('V')
    let bothHave = expect lookupGposKerning(faceData, cast(u16) glyphA, cast(u16) glyphV)
    @assert(bothHave != 0)
}

// A glyph index no font can hold is answered rather than truncated into a real one.
#test
{
    var scope: FaceScope
    scope.init("arial.ttf")
    let face = scope.face!

    discard expect face.setPixelSize(0, 100)
    let beyondU16 = face.getKerning(0x1_0024, face.glyphIndex('V'))
    @assert(beyondU16.x == 0)
}
