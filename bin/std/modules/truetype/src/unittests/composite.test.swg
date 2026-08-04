#global if #command == Swag.CompilerCommand.Test

using Swag, Core

#test
{
    var scope: FaceScope
    scope.init()
    let face = scope.face!

    let glyphIndex = face.glyphIndex(0x00E9)
    @assert(glyphIndex > 0)

    let faceData                  = getFaceData(face)
    let glyf: #null const [..] u8 = expect getTableSlice(faceData, TAG_GLYF, 0x10)
    let glyphStart                = faceData.glyphLocations[glyphIndex]
    let glyphEnd                  = faceData.glyphLocations[glyphIndex + 1]
    let glyphData                 = expect getSlice(glyf, glyphStart, glyphEnd - glyphStart)
    let contourCount              = expect readS16(glyphData, 0)
    @assert(contourCount < 0)

    discard expect face.setPixelSize(0, 20)
    discard expect face.loadChar(0x00E9)
    @assert(face.glyph.index == glyphIndex)
    @assert(face.glyph.outline.pointCount > 0)
    @assert(face.glyph.outline.contourCount > 0)

    discard expect face.renderGlyph()
    @assert(countBitmapCoverage(&face.glyph.bitmap) > 0)
}
