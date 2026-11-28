#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// A valid font may still contain a point whose scaled 26.6 coordinate cannot fit the outline.
#test
{
    var faceData: FaceImpl
    faceData.unitsPerEm = 1
    faceData.outlinePoints.add(Vector{x: 13, y: -4})
    faceData.outlineTags.add(CURVE_TAG_ON)
    faceData.outlineContours.add(0)

    var glyphData: Array!{u8}
    glyphData.resize(17)
    glyphData[1]  = 1        // One contour.
    glyphData[10] = 0        // End point index zero.
    glyphData[14] = 0x21     // On-curve, with a signed x delta and zero y delta.
    glyphData[15] = 0x7F
    glyphData[16] = 0xFF

    var rejected: Swag.Error
    discard catch appendSimpleGlyph(&faceData, glyphData.toSlice(), 65_535, 65_535) as rejected
    Swag.require(rejected.value() != null)
    Swag.require(faceData.outlinePoints.count == 1 and
                 faceData.outlineTags.count == 1 and
                 faceData.outlineContours.count == 1)
    Swag.require(faceData.outlinePoints[0].x == 13 and faceData.outlinePoints[0].y == -4)
    Swag.require(faceData.outlineTags[0] == CURVE_TAG_ON and faceData.outlineContours[0] == 0)
}

// Truncated glyph headers, endpoints, instructions, flags, and coordinates are rejected.
#test
{
    var faceData: FaceImpl
    faceData.unitsPerEm = 1000

    var negativeCount: Array!{u8}
    negativeCount.resize(10)
    negativeCount[0] = 0xFF
    negativeCount[1] = 0xFF

    var rejected: Swag.Error
    discard catch appendSimpleGlyph(&faceData, negativeCount.toSlice(), 16, 16) as rejected
    Swag.require(rejected.value() != null)

    var glyphData: Array!{u8}
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
    rejected      = {}
    discard catch appendSimpleGlyph(&faceData, glyphData.toSlice(), 16, 16) as rejected
    Swag.require(rejected.value() != null)
    Swag.require(faceData.outlineTags.isEmpty())

    glyphData.resize(16)
    glyphData[14] = 0x39
    glyphData[15] = 1
    rejected      = {}
    discard catch appendSimpleGlyph(&faceData, glyphData.toSlice(), 16, 16) as rejected
    Swag.require(rejected.value() != null)
    Swag.require(faceData.outlinePoints.isEmpty() and
                 faceData.outlineTags.isEmpty() and
                 faceData.outlineContours.isEmpty())
}

// Every combination of four coordinate modes decodes to the same signed deltas on both axes.
#test
{
    const PointCount = 16_u32
    const Deltas     = [-32768_s32, -249, 0, 250]
    const XFlags     = [0_u8, 0x02, 0x10, 0x12]
    const YFlags     = [0_u8, 0x04, 0x20, 0x24]
    var glyph:    Array!{u8}
    var faceData: FaceImpl
    faceData.unitsPerEm = 64000
    for key in 256
    {
        glyph.clear()
        glyph.resize(14 + PointCount)
        writeBigU16(&glyph, 0, 1)
        writeBigU16(&glyph, 10, cast(u16, PointCount - 1))

        var expected: [PointCount] Vector
        var x, y:     s32
        for point in PointCount
        {
            let shift = (point % 4) * 2
            let xMode = (key >> shift) & 3
            let yMode = ((key ^ 0xFF) >> shift) & 3
            glyph[14 + point] = XFlags[xMode] | YFlags[yMode] | cast(u8, point & 1)
            x                 += Deltas[xMode]
            y                 += Deltas[yMode]
            expected[point]   = {x: x, y: y}
        }

        for keyAxis in [key, key ^ 0xFF]
        {
            for point in PointCount
            {
                let mode = (keyAxis >> ((point % 4) * 2)) & 3
                switch mode
                {
                case 0: glyph.add([0x80_u8, 0])
                case 1: glyph.add(249_u8)
                case 3: glyph.add(250_u8)
                }
            }
        }

        // Give the final group room for its full load, independent of its encoded size.
        let end = glyph.count
        glyph.resize(end + 16)
        faceData.outlinePoints.clear()
        faceData.outlineTags.clear()
        faceData.outlineContours.clear()
        expect appendSimpleGlyph(&faceData, glyph.toSlice(), 1000, 1000)
        Swag.require(faceData.outlinePoints.count == PointCount)
        for point in PointCount
        {
            Swag.require(faceData.outlinePoints[point].x == expected[point].x)
            Swag.require(faceData.outlinePoints[point].y == expected[point].y)
            Swag.require(faceData.outlineTags[point] == (point & 1))
        }

        Swag.require(faceData.outlineContours.count == 1 and faceData.outlineContours[0] == PointCount - 1)

        glyph.resize(end - 1)
        var rejected: Swag.Error
        discard catch appendSimpleGlyph(&faceData, glyph.toSlice(), 1000, 1000) as rejected
        Swag.require(rejected.value() != null)
    }
}
