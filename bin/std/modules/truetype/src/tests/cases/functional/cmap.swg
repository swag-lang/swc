#global if #command == Swag.CompilerCommand.Test

using Swag, Core

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
