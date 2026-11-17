#global if #command == Swag.CompilerCommand.Test

using Swag, Core

#test
{
    var faceScope: FaceScope
    faceScope.init("arial.ttf")
    let face = unwrap faceScope.face
    let faceData = getFaceData(face)
    let hmtx = expect getTableSlice(faceData, TAG_HMTX, 0x93)

    // Query before loading any outline; the active pixel size is irrelevant.
    let glyphA = face.glyphIndex('A')
    let expectedA = expect readU16(hmtx, cast(u64, glyphA) * 4)
    Swag.require(expect face.getAdvanceWidth(glyphA) == expectedA)
    Swag.require(expect face.getAdvanceWidth(glyphA) > 0)

    // Glyphs after the hhea long-metric run repeat the final advance from hmtx.
    Swag.require(face.glyphCount > faceData.numLongMetrics)
    let lastGlyph = face.glyphCount - 1
    let finalLongMetric = cast(u64, faceData.numLongMetrics - 1) * 4
    let expectedLast = expect readU16(hmtx, finalLongMetric)
    Swag.require(expect face.getAdvanceWidth(lastGlyph) == expectedLast)

    var invalid: Swag.Error
    discard catch face.getAdvanceWidth(face.glyphCount) as invalid
    Swag.require(invalid.value() != null)
}

// CFF and Type 1 advances use the widths their charstrings declare.
#test
{
    var cffBytes: Array'u8
    cffBytes.add(189'u8) // 50
    cffBytes.add(14'u8)  // endchar
    cffBytes.add(14'u8)  // zero-width endchar

    var cffFace: FaceImpl
    cffFace.face.setGlyphCount(2)
    cffFace.outlineSource = .Cff
    cffFace.cff.block = cffBytes.toSlice()
    cffFace.cff.charStrings.starts.add(0)
    cffFace.cff.charStrings.starts.add(2)
    cffFace.cff.charStrings.starts.add(3)
    expect buildCharstringMetrics(&cffFace)
    Swag.require(expect cffFace.face.getAdvanceWidth(0) == 50)
    Swag.require(expect cffFace.face.getAdvanceWidth(1) == 0)

    var type1Face: FaceImpl
    type1Face.face.setGlyphCount(2)
    type1Face.outlineSource = .Type1

    var type1Width: Array'u8
    type1Width.add(139'u8) // sidebearing 0
    type1Width.add(189'u8) // width 50
    type1Width.add(13'u8)  // hsbw
    type1Width.add(14'u8)  // endchar
    type1Face.type1.charstrings.add(type1Width)

    var type1Zero: Array'u8
    type1Zero.add(139'u8) // sidebearing 0
    type1Zero.add(139'u8) // width 0
    type1Zero.add(13'u8)  // hsbw
    type1Zero.add(14'u8)  // endchar
    type1Face.type1.charstrings.add(type1Zero)

    expect buildCharstringMetrics(&type1Face)
    Swag.require(expect type1Face.face.getAdvanceWidth(0) == 50)
    Swag.require(expect type1Face.face.getAdvanceWidth(1) == 0)
}
