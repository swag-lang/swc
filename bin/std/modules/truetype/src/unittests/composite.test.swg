#global #if #command == Swag.CompilerCommand.Test
using Swag, Core

#test
{
    var scope: FaceScope
    scope.init()

    let glyphIndex = scope.face.glyphIndex(0x00E9)
    @assert(glyphIndex > 0)

    let faceData = getFaceData(scope.face)
    let glyf = catch getTableSlice(faceData, TAG_GLYF, 0x10)
    @assert(@err == null)

    let glyphStart = faceData.glyphLocations[glyphIndex]
    let glyphEnd = faceData.glyphLocations[glyphIndex + 1]
    let glyphData = catch getSlice(glyf, glyphStart, glyphEnd - glyphStart)
    @assert(@err == null)
    let contourCount = catch readS16(glyphData, 0)
    @assert(@err == null)
    @assert(contourCount < 0)

    discard catch scope.face.setPixelSize(0, 20)
    @assert(@err == null)
    discard catch scope.face.loadChar(0x00E9, .NoBitmap)
    @assert(@err == null)
    @assert(scope.face.glyph.index == glyphIndex)
    @assert(scope.face.glyph.outline.pointCount > 0)
    @assert(scope.face.glyph.outline.contourCount > 0)

    discard catch scope.face.renderGlyph()
    @assert(@err == null)
    @assert(countBitmapCoverage(&scope.face.glyph.bitmap) > 0)
}
