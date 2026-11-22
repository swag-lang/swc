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

// Truncated glyph headers, endpoints, instructions, flags, and coordinates are rejected.
#test
{
    var faceData: FaceImpl
    faceData.unitsPerEm = 1000

    var negativeCount: Array'u8
    negativeCount.resize(10)
    negativeCount[0] = 0xFF
    negativeCount[1] = 0xFF

    var rejected: Swag.Error
    discard catch appendSimpleGlyph(&faceData, negativeCount.toSlice(), 16, 16) as rejected
    Swag.require(rejected.value() != null)

    var glyphData: Array'u8
    glyphData.resize(9)
    glyphData[1] = 1

    discard catch appendSimpleGlyph(&faceData, glyphData.toSlice(), 16, 16) as rejected
    Swag.require(rejected.value() != null)

    glyphData.resize(10)
    rejected = {}
    discard catch appendSimpleGlyph(&faceData, glyphData.toSlice(), 16, 16) as rejected
    Swag.require(rejected.value() != null)

    glyphData.resize(14)
    writeBigU16(&glyphData, 10, Swag.U16.Max)
    writeBigU16(&glyphData, 12, 0)
    rejected = {}
    discard catch appendSimpleGlyph(&faceData, glyphData.toSlice(), 16, 16) as rejected
    Swag.require(rejected.value() != null)

    glyphData.resize(12)
    writeBigU16(&glyphData, 10, 0)
    rejected = {}
    discard catch appendSimpleGlyph(&faceData, glyphData.toSlice(), 16, 16) as rejected
    Swag.require(rejected.value() != null)

    glyphData.resize(14)
    writeBigU16(&glyphData, 12, 1)
    rejected = {}
    discard catch appendSimpleGlyph(&faceData, glyphData.toSlice(), 16, 16) as rejected
    Swag.require(rejected.value() != null)

    glyphData.resize(14)
    writeBigU16(&glyphData, 12, 0)
    rejected = {}
    discard catch appendSimpleGlyph(&faceData, glyphData.toSlice(), 16, 16) as rejected
    Swag.require(rejected.value() != null)

    glyphData.resize(15)
    glyphData[14] = 0x02
    rejected = {}
    discard catch appendSimpleGlyph(&faceData, glyphData.toSlice(), 16, 16) as rejected
    Swag.require(rejected.value() != null)
}
