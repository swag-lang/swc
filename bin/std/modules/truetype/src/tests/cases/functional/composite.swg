#global if #command == Swag.CompilerCommand.Test

using Swag, Core

#test
{
    // Point numbers in composite arguments are unsigned. A parent anchor of 128
    // must still attach when its high bit is set in the two-byte representation.
    var childGlyph: Array'u8
    childGlyph.add([
        0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x31])

    var compositeGlyph: Array'u8
    compositeGlyph.add([
        0xFF, 0xFF, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x01, 0x00, 0x00, 0x00, 0x80, 0x00, 0x00])

    var faceData: FaceImpl
    faceData.face.setGlyphCount(1)
    faceData.unitsPerEm = 1000
    for index in 129
    {
        let point = index == 128 ? Vector{x: 100, y: 200} : Vector{}
        faceData.outlinePoints.add(point)
    }

    faceData.fontData.add(childGlyph.toSlice())
    faceData.tables.add({tag: TAG_GLYF, offset: 0, length: cast(u32, childGlyph.count)})
    faceData.glyphLocations.add(0)
    faceData.glyphLocations.add(cast(u32, childGlyph.count))

    expect appendCompositeGlyph(&faceData, compositeGlyph.toSlice(), 1, 1, 0)
    Swag.require(faceData.outlinePoints.count == 130)
    Swag.require(faceData.outlinePoints[129].x == 100)
    Swag.require(faceData.outlinePoints[129].y == 200)

    // The byte form carries the same unsigned point number in one byte.
    var byteComposite: Array'u8
    byteComposite.add([
        0xFF, 0xFF, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x80, 0x00])
    faceData.outlinePoints.clear()
    for index in 129
    {
        let point = index == 128 ? Vector{x: 100, y: 200} : Vector{}
        faceData.outlinePoints.add(point)
    }

    expect appendCompositeGlyph(&faceData, byteComposite.toSlice(), 1, 1, 0)
    Swag.require(faceData.outlinePoints.count == 130)
    Swag.require(faceData.outlinePoints[129].x == 100)
    Swag.require(faceData.outlinePoints[129].y == 200)
}

#test
{
    var faceScope: FaceScope
    faceScope.init()
    let face = unwrap faceScope.face

    let glyphIndex = face.glyphIndex(0x00E9)
    Swag.require(glyphIndex > 0)

    let faceData     = getFaceData(face)
    let glyf         = expect getTableSlice(faceData, TAG_GLYF, 0x10)
    let glyphStart   = faceData.glyphLocations[glyphIndex]
    let glyphEnd     = faceData.glyphLocations[glyphIndex + 1]
    let glyphData    = expect getSlice(glyf, glyphStart, glyphEnd - glyphStart)
    let contourCount = expect readS16(glyphData, 0)
    Swag.require(contourCount < 0)

    discard expect face.setPixelSize(0, 20)
    discard expect face.loadChar(0x00E9)
    Swag.require(face.glyph.index == glyphIndex)
    Swag.require(face.glyph.outline.pointCount > 0)
    Swag.require(face.glyph.outline.contourCount > 0)

    discard expect face.renderGlyph()
    Swag.require(countBitmapCoverage(&face.glyph.bitmap) > 0)
}
