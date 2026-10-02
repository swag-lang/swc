#global if #command == Swag.CompilerCommand.Test

using Swag, Core

#test
{
    let identity = Matrix.Identity
    Swag.assert(identity.xx == 65536 and identity.xy == 0)
    Swag.assert(identity.yx == 0 and identity.yy == 65536)
}

#test
{
    var points:   [3] Vector = [{x: 0, y: 0}, {x: 64, y: 64}, {x: 128, y: 0}]
    var tags:     [3] u8     = [1, 0, 1]
    var contours: [1] s16    = [2]

    var outline = Outline.borrowed(&points[0], &tags[0], &contours[0], 3, 1)

    let commands = buildOutlineCommands(&outline)
    Swag.assert(commands.count == 3)
    Swag.assert(commands[0].kind == .MoveTo)
    Swag.assert(commands[1].kind == .ConicTo)
    Swag.assert(commands[2].kind == .LineTo)
}

#test
{
    var scope: FaceScope
    scope.init()
    let face = scope.face!

    discard expect face.setPixelSize(0, 18)
    discard expect face.loadChar('A')
    Swag.assert(face.glyph.outline.contourCount > 0)
    Swag.assert(face.glyph.outline.pointCount > 0)
    Swag.assert(face.glyph.advance.x > 0)

    var counter: OutlineCounter
    let commands = face.glyph.outline.decompose()
    for cmd in commands
    {
        switch cmd.kind
        {
        case .MoveTo:  counter.moves += 1
        case .LineTo:  counter.lines += 1
        case .ConicTo: counter.conics += 1
        case .CubicTo: discard cmd
        }
    }

    Swag.assert(counter.moves > 0)
    Swag.assert(counter.lines + counter.conics > 0)

    let bounds0 = getOutlineBounds(&face.glyph.outline)
    face.glyph.outline.translate(64, 0)
    let bounds1 = getOutlineBounds(&face.glyph.outline)
    Swag.assert(bounds1.xMin == bounds0.xMin + 64)
    Swag.assert(bounds1.xMax == bounds0.xMax + 64)

    discard expect face.loadChar('A')
    let transformIdx     = findPointWithNonZeroY(&face.glyph.outline)
    let transformPts     = face.glyph.outline.points!
    let beforeTransformX = transformPts[transformIdx].x
    let beforeTransformY = transformPts[transformIdx].y
    let scaleY           = Matrix{xx: 65536, yy: 131072}
    face.glyph.outline.transform(scaleY)
    Swag.assert(transformPts[transformIdx].x == beforeTransformX)
    Swag.assert(transformPts[transformIdx].y == beforeTransformY * 2)

    discard expect face.loadChar('A')
    let bounds2 = getOutlineBounds(&face.glyph.outline)
    discard expect face.glyph.outline.embolden(64)
    let bounds3 = getOutlineBounds(&face.glyph.outline)
    Swag.assert(bounds3.xMax - bounds3.xMin >= bounds2.xMax - bounds2.xMin)

    // Emboldening a glyph with a counter ('o') must add ink: the outer contour
    // grows while the inner hole shrinks. A per-contour winding bug would instead
    // grow the hole, so the total filled area would not increase.
    discard expect face.loadChar('o')
    Swag.assert(face.glyph.outline.contourCount >= 2)
    let inkBefore = Math.abs(totalOutlineSignedArea(&face.glyph.outline))
    discard expect face.glyph.outline.embolden(128)
    let inkAfter = Math.abs(totalOutlineSignedArea(&face.glyph.outline))
    Swag.assert(inkAfter > inkBefore)

    discard expect face.loadChar('A')
    let sampleIdx = findPointWithNonZeroY(&face.glyph.outline)

    // The calls above alias the outline, so the point array is unproven again here.
    let samplePts     = face.glyph.outline.points!
    let sampleBeforeX = samplePts[sampleIdx].x
    let sampleBeforeY = samplePts[sampleIdx].y
    face.glyph.oblique()
    Swag.assert(samplePts[sampleIdx].x == sampleBeforeX + cast(s32) Math.round(sampleBeforeY * 0.21256))
}

// A 3/64-pixel embolden of this captured contour lies on a half-integer boundary.
// Its fixed-point result must not change when automatic FMA is enabled in Release.
#test
{
    var points:   [12] Vector = [{272, 298}, {147, 473}, {53, 473}, {229, 239}, {48, 0}, {143, 0}, {273, 180}, {404, 0}, {498, 0}, {317, 239}, {493, 473}, {398, 473}]
    var tags:     [12] u8     = [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1]
    var contours: [1] s16     = [11]
    var outline = Outline.borrowed(&points[0], &tags[0], &contours[0], 12, 1)
    discard expect outline.embolden(3)

    let expected: [12] Vector = [{272, 301}, {148, 475}, {50, 475}, {227, 239}, {45, -2}, {144, -2}, {273, 177}, {403, -2}, {501, -2}, {319, 239}, {496, 475}, {397, 475}]
    for point, index in expected
    {
        Swag.assert(points[index].x == point.x)
        Swag.assert(points[index].y == point.y)
    }
}

// The dot product also needs separate product rounding: this two-contour outline
// crosses the lower baseline tie when either dot-product term is fused.
#test
{
    var points:   [17] Vector = [{23, 0}, {259, 652}, {356, 652}, {595, 0}, {508, 0}, {443, 182}, {174, 182}, {111, 0}, {200, 255}, {417, 255}, {370, 387}, {358, 420}, {328, 515}, {307, 585}, {287, 513}, {256, 417}, {245, 387}]
    var tags:     [17] u8     = [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 1, 0, 0, 1]
    var contours: [2] s16     = [7, 16]
    var outline = Outline.borrowed(&points[0], &tags[0], &contours[0], 17, 2)
    discard expect outline.embolden(3)

    let expected: [17] Vector = [{21, -2}, {258, 654}, {357, 654}, {597, -2}, {507, -2}, {442, 181}, {175, 181}, {112, -2}, {202, 257}, {415, 257}, {369, 386}, {357, 420}, {327, 515}, {307, 580}, {288, 513}, {257, 417}, {246, 386}]
    for point, index in expected
    {
        Swag.assert(points[index].x == point.x)
        Swag.assert(points[index].y == point.y)
    }
}

// At strength 1, rounding the Y dot-product term together with the addition moves
// the first point from just above the negative half-unit tie onto it.
#test
{
    var points:   [13] Vector = [{277, 0}, {19, 699}, {219, 699}, {336, 336}, {351, 289}, {375, 194}, {386, 146}, {397, 194}, {420, 289}, {435, 336}, {551, 699}, {748, 699}, {490, 0}]
    var tags:     [13] u8     = [1, 1, 1, 1, 0, 0, 1, 0, 0, 1, 1, 1, 1]
    var contours: [1] s16     = [12]
    var outline = Outline.borrowed(&points[0], &tags[0], &contours[0], 13, 1)
    discard expect outline.embolden(1)

    let expected: [13] Vector = [{277, 0}, {18, 700}, {219, 700}, {336, 336}, {351, 289}, {375, 194}, {386, 147}, {397, 194}, {420, 289}, {435, 336}, {551, 700}, {749, 700}, {490, -1}]
    for point, index in expected
    {
        Swag.assert(points[index].x == point.x)
        Swag.assert(points[index].y == point.y)
    }
}

// These two reduced contour neighborhoods have a final Y displacement of -2.5.
// Rounding that displacement before adding the origin preserves the +0.5 tie.
#test
{
    var points:   [6] Vector = [{58, 11}, {55, 3}, {53, 3}, {53, 3}, {52, 3}, {47, 8}]
    var tags:     [6] u8     = [1, 0, 1, 1, 0, 1]
    var contours: [2] s16    = [2, 5]
    var outline = Outline.borrowed(&points[0], &tags[0], &contours[0], 6, 2)
    discard expect outline.embolden(5)

    Swag.assert(points[1].x == 57 and points[1].y == 1)
    Swag.assert(points[4].x == 51 and points[4].y == 1)
}
