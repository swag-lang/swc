#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// A valid font may still contain a point whose scaled 26.6 coordinate cannot fit the outline.
#test
{
    var faceData: FaceImpl
    faceData.unitsPerEm = 1

    var glyphData: Array'u8
    glyphData.resize(17)
    glyphData[1]  = 1       // One contour.
    glyphData[10] = 0       // End point index zero.
    glyphData[14] = 0x21    // On-curve, with a signed x delta and zero y delta.
    glyphData[15] = 0x7F
    glyphData[16] = 0xFF

    var rejected: Swag.Error
    discard catch appendSimpleGlyph(&faceData, glyphData.toSlice(), 65_535, 65_535) as rejected
    Swag.require(rejected.value() != null)
    Swag.require(faceData.outlinePoints.isEmpty() and faceData.outlineContours.isEmpty())
}
