#global if #command == Swag.CompilerCommand.Test

using Swag, Core

#test
{
    let glyphA = expect lookupCMap4(Cmap4Fixture, 'A'u32)
    @assert(glyphA == 3)

    let glyphB = expect lookupCMap4(Cmap4Fixture, 'B'u32)
    @assert(glyphB == 0)
}

#test
{
    let glyph0 = expect lookupCMap12(Cmap12Fixture, 0x00010000)
    @assert(glyph0 == 7)

    let glyph1 = expect lookupCMap12(Cmap12Fixture, 0x00010001)
    @assert(glyph1 == 0)
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
        0x00, 0x00, 0x00, 0x07,
        ]

    var faceData: FaceImpl
    faceData.fontData.add(cmap)
    faceData.tables.add({tag: TAG_CMAP, length: @countof(cmap)})

    discard expect parseCMap(&faceData)
    @assert(faceData.face.charMap.platformID == 0)
    @assert(faceData.face.charMap.encodingID == 4)
    @assert(faceData.cmapFormat == 12)
}

#test
{
    var scope: FaceScope
    scope.init()
    let face = notnull scope.face

    let glyphA       = face.glyphIndex('A')
    let glyphE       = face.glyphIndex(0x00E9)
    let glyphMissing = face.glyphIndex(0x10FFFF)

    @assert(glyphA > 0)
    @assert(glyphE > 0)
    @assert(glyphMissing == 0)
}
