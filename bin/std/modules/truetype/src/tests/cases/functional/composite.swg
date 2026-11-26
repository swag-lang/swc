#global if #command == Swag.CompilerCommand.Test

using Swag, Core

private func setCompositeTestGlyphs(faceData: *FaceImpl, first, second: const [..] u8)
{
    faceData.face.setGlyphCount(2)
    faceData.fontData.add(first)
    faceData.fontData.add(second)
    let glyfLength = cast(u32, faceData.fontData.count)
    faceData.tables.add({tag: TAG_GLYF, offset: 0, length: glyfLength})
    faceData.fontData.resize(cast(u64, glyfLength) + 12)
    writeBigU32(&faceData.fontData, cast(u64, glyfLength) + 4, cast(u32, first.count))
    writeBigU32(&faceData.fontData, cast(u64, glyfLength) + 8, glyfLength)
    faceData.tables.add({tag: TAG_LOCA, offset: glyfLength, length: 12})
    faceData.indexToLocFormat = 1
    expect buildGlyphLocations(faceData)
}

#test
{
    // Point numbers in a nested composite are relative to that composite's own
    // points, even when its parent has already appended an unrelated component.
    var firstGlyph: Array'u8
    firstGlyph.add([
        0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x33, 0x0A])

    var secondGlyph: Array'u8
    secondGlyph.add([
        0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x33, 0x14])

    var nestedComposite: Array'u8
    nestedComposite.add([
        0xFF, 0xFF, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x23, 0x00, 0x00, 0x00, 0x0A, 0x00, 0x00,
        0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00])

    var faceData: FaceImpl
    faceData.unitsPerEm = 1000
    faceData.outlinePoints.add(Vector{x: 6400, y: 0})
    setCompositeTestGlyphs(&faceData, firstGlyph.toSlice(), secondGlyph.toSlice())

    expect appendCompositeGlyph(&faceData, nestedComposite.toSlice(), 1000, 1000, 0)
    Swag.require(faceData.outlinePoints.count == 3)
    Swag.require(faceData.outlinePoints[2].x == faceData.outlinePoints[1].x)
}

#test
{
    var parentGlyph: Array'u8
    parentGlyph.add([
        0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x33, 0x00])

    var childGlyph: Array'u8
    childGlyph.add([
        0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x33, 0x00])

    var compositeGlyph: Array'u8
    compositeGlyph.add([
        0xFF, 0xFF, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x23, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x01, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00])

    var faceData: FaceImpl
    faceData.unitsPerEm = 1000
    setCompositeTestGlyphs(&faceData, parentGlyph.toSlice(), childGlyph.toSlice())

    // The second component's parent point index is outside the assembled outline.
    var rejected: Swag.Error
    discard catch appendCompositeGlyph(&faceData, compositeGlyph.toSlice(), 16, 16, 0) as rejected
    Swag.require(rejected.value() != null)

    // A valid parent index still fails when the child point index is outside its outline.
    faceData.outlinePoints.clear()
    faceData.outlineContours.clear()
    writeBigU16(&compositeGlyph, 22, 0)
    writeBigU16(&compositeGlyph, 24, 1)
    rejected = {}
    discard catch appendCompositeGlyph(&faceData, compositeGlyph.toSlice(), 16, 16, 0) as rejected
    Swag.require(rejected.value() != null)
}

#test
{
    // Point numbers in composite arguments are unsigned. A parent anchor of 128
    // must still attach when its high bit is set in either representation.
    var parentGlyph: Array'u8
    parentGlyph.add([
        0x00, 0x01, 0x00, 0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x80, 0x00, 0x00, 0x39, 0x7F, 0x33, 0x64])

    var childGlyph: Array'u8
    childGlyph.add([
        0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x31])

    var compositeGlyph: Array'u8
    compositeGlyph.add([
        0xFF, 0xFF, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x23, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x01, 0x00, 0x01, 0x00, 0x80, 0x00, 0x00])

    var faceData: FaceImpl
    faceData.unitsPerEm = 1000
    setCompositeTestGlyphs(&faceData, parentGlyph.toSlice(), childGlyph.toSlice())

    expect appendCompositeGlyph(&faceData, compositeGlyph.toSlice(), 1000, 1000, 0)
    Swag.require(faceData.outlinePoints.count == 130)
    Swag.require(faceData.outlinePoints[129].x == 6400)
    Swag.require(faceData.outlinePoints[129].y == 0)

    // The byte form carries the same unsigned point number in one byte.
    var byteComposite: Array'u8
    byteComposite.add([
        0xFF, 0xFF, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x22, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x01, 0x80, 0x00])
    faceData.outlinePoints.clear()

    expect appendCompositeGlyph(&faceData, byteComposite.toSlice(), 1000, 1000, 0)
    Swag.require(faceData.outlinePoints.count == 130)
    Swag.require(faceData.outlinePoints[129].x == 6400)
    Swag.require(faceData.outlinePoints[129].y == 0)
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
    let range        = faceData.glyphByteRange(glyphIndex)
    let glyphData    = expect getSlice(glyf, range.start, range.stop - range.start)
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
