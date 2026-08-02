#global if #command == Swag.CompilerCommand.Test

using Swag, Core

#test
{
    let identity = Matrix.Identity
    @assert(identity.xx == 65536 and identity.xy == 0)
    @assert(identity.yx == 0 and identity.yy == 65536)
}

#test
{
    var points:   [3] Vector = [{x: 0, y: 0}, {x: 64, y: 64}, {x: 128, y: 0}]
    var tags:     [3] u8     = [1, 0, 1]
    var contours: [1] s16    = [2]

    var outline = Outline.borrowed(&points[0], &tags[0], &contours[0], 3, 1)

    let commands = buildOutlineCommands(&outline)
    @assert(commands.count == 3)
    @assert(commands[0].kind == .MoveTo)
    @assert(commands[1].kind == .ConicTo)
    @assert(commands[2].kind == .LineTo)
}

#test
{
    var scope: FaceScope
    scope.init()
    let face = notnull scope.face

    discard expect face.setPixelSize(0, 18)
    discard expect face.loadChar('A')
    @assert(face.glyph.outline.contourCount > 0)
    @assert(face.glyph.outline.pointCount > 0)
    @assert(face.glyph.advance.x > 0)

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

    @assert(counter.moves > 0)
    @assert(counter.lines + counter.conics > 0)

    let bounds0 = getOutlineBounds(&face.glyph.outline)
    face.glyph.outline.translate(64, 0)
    let bounds1 = getOutlineBounds(&face.glyph.outline)
    @assert(bounds1.xMin == bounds0.xMin + 64)
    @assert(bounds1.xMax == bounds0.xMax + 64)

    discard expect face.loadChar('A')
    let transformIdx     = findPointWithNonZeroY(&face.glyph.outline)
    let transformPts     = notnull face.glyph.outline.points
    let beforeTransformX = transformPts[transformIdx].x
    let beforeTransformY = transformPts[transformIdx].y
    let scaleY           = Matrix{xx: 65536, yy: 131072}
    face.glyph.outline.transform(scaleY)
    @assert(transformPts[transformIdx].x == beforeTransformX)
    @assert(transformPts[transformIdx].y == beforeTransformY * 2)

    discard expect face.loadChar('A')
    let bounds2 = getOutlineBounds(&face.glyph.outline)
    discard expect face.glyph.outline.embolden(64)
    let bounds3 = getOutlineBounds(&face.glyph.outline)
    @assert(bounds3.xMax - bounds3.xMin >= bounds2.xMax - bounds2.xMin)

    // Emboldening a glyph with a counter ('o') must add ink: the outer contour
    // grows while the inner hole shrinks. A per-contour winding bug would instead
    // grow the hole, so the total filled area would not increase.
    discard expect face.loadChar('o')
    @assert(face.glyph.outline.contourCount >= 2)
    let inkBefore = Math.abs(totalOutlineSignedArea(&face.glyph.outline))
    discard expect face.glyph.outline.embolden(128)
    let inkAfter = Math.abs(totalOutlineSignedArea(&face.glyph.outline))
    @assert(inkAfter > inkBefore)

    discard expect face.loadChar('A')
    let sampleIdx     = findPointWithNonZeroY(&face.glyph.outline)
    let samplePts     = notnull face.glyph.outline.points
    let sampleBeforeX = samplePts[sampleIdx].x
    let sampleBeforeY = samplePts[sampleIdx].y
    face.glyph.oblique()
    @assert(samplePts[sampleIdx].x == sampleBeforeX + cast(s32) Math.round(sampleBeforeY * 0.21256))
}
