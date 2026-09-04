using Core

// Selects how a [[Pixel.LinePathList]] is stroked.
public enum DrawPathListMode
{
    Separate     // Stroke each path independently, including its own caps.
    Merge        // Treat compatible paths as one continuous stroke.
}

struct Context
{
    posBuffer: Array'Math.Vector2
    penSize:   f32

    // Half width the quads and the joins are laid down at: half the pen, plus the border
    // when this walk is painting one. The caps are shaped from `capSize2` instead, so a
    // border keeps the cap it belongs to and only offsets it.
    penSize2: f32
    capSize2: f32

    // Width of the border this walk paints outside the stroke; zero for the stroke itself.
    outline: f32

    // Direction of the segment last laid down, used to close the border across a butt end.
    dir:             Math.Vector2
    beginLine:       bool
    firstLine:       bool
    lastLineInvalid: bool
    normalPrev:      Math.Vector2
    normalFirst:     Math.Vector2
    normal:          Math.Vector2
    prim1, prim2:    u64
    prev:            Math.Vector2
    path:            const *LinePath = undefined
    pen:             const *Pen      = undefined
    offsetPath:      f32

    // Squared distance below which a contour point is not worth a segment of its own,
    // because the one before it already covers the same place on the device grid. Zero
    // walks every point.
    minStepSquared: f32

    // Squared distance below which the two segment ends a join would bridge are the same
    // corner to the device grid, so the join filling the sliver between them is not worth
    // its geometry.
    joinSkipSpanSquared: f32

    remainingPatternLen: f32
    patternTotalLen:     f32
    patternIndex:        s32
    error:               f32
    divError:            f32
    pattern:             const [*] f32 = undefined
    patternCount:        s32
}

impl Context
{
    // The stroke's own half-width normal, recovered from the one a border pass widened.
    //
    // A cap is shaped from the stroke it terminates and is then pushed out, so it is measured
    // against the width the stroke has rather than the width this walk is laying down.
    mtd const capNormal()->Math.Vector2
    {
        if .outline <= 0 or .penSize2 <= 0 do
            return .normal
        return .normal * (.capSize2 / .penSize2)
    }
}

// A cap is one convex outline, and this is the room the widest of them needs. Holding a cap as
// its outline is what lets a border hand the same outline back expanded by the border width,
// instead of drawing the cap a second time at a larger scale.
const MaxCapRingPoints = 4

// How far a corner of an expanded outline may reach, as a multiple of the border width. An
// arrowhead is the sharpest corner a cap has, and this leaves its border a point rather than a
// facet cut across it; a limit still keeps a degenerate outline from shooting off the drawing.
const OutlineMiterLimit = 8.0

// Expands a convex outline outward by `outline`, in place.
//
// Every edge moves out along its own normal and the corners land where the two moved edges meet,
// which is what makes the result the outline's true offset: the border keeps the width it was
// asked for along every side, whatever the angle between them. Scaling the outline instead gives
// a border that thins wherever a side is oblique, which is what an arrowhead is made of.
private func expandConvexRing(points: [..] Math.Vector2, outline: f32)
{
    let count = points.count
    if count < 3 or count > MaxCapRingPoints do
        return

    var center: Math.Vector2
    for pt in points do
        center += pt
    center /= cast(f32) count

    // Outward side of each edge, taken as the one facing away from the centre. A convex outline
    // lies on one side of every one of its edges, so this needs no winding order.
    var normals: [MaxCapRingPoints] Math.Vector2 = undefined
    for i in count
    {
        let a = points[i]
        let b = points[(i + 1) % count]
        var n = (b - a).cross(1).normalizedOrZero()
        if n.dot(((a + b) * 0.5) - center) < 0 do
            n.negate()
        normals[i] = n
    }

    var moved: [MaxCapRingPoints] Math.Vector2 = undefined
    for i in count
    {
        let n0 = normals[(i + count - 1) % count]
        let n1 = normals[i]

        // The point where the two moved edges cross, at `outline / cos(half angle)` along their
        // bisector. Two edges folded back on each other have no crossing; leave the corner on
        // one of them rather than sending it to infinity.
        let fold = 1 + n0.dot(n1)
        if fold < 0.0001
        {
            moved[i] = points[i] + n1 * outline
            continue
        }

        var m   = (n0 + n1) * (outline / fold)
        let len = m.length()
        if len > outline * OutlineMiterLimit do
            m *= (outline * OutlineMiterLimit) / len
        moved[i] = points[i] + m
    }

    for i in count do
        points[i] = moved[i]
}

impl Painter
{
    // Lays down one convex cap outline, expanded by the border width when this walk paints one.
    mtd fillCapRing(points: [..] Math.Vector2, outline: f32, pen: Pen)
    {
        let count = points.count
        if count < 3 do
            return
        if outline > 0 do
            expandConvexRing(points, outline)

        let antialiased = .curState.paintParams & .Antialiased
        let v0          = points[0]
        for i in 1 until count - 1
        {
            let v1    = points[i]
            let v2    = points[i + 1]
            let prim1 = .pushTriangle(v0, v1, v2, pen.brush.color)
            if !antialiased do
                continue

            // Only the edges of the outline itself carry a fringe; the fan's own spokes are
            // interior and a band on them would show as a seam through the cap.
            .addEdgeAA(prim1, v1, v2)
            if i == 1 do
                .addEdgeAA(prim1, v0, v1)
            if i == count - 2 do
                .addEdgeAA(prim1, v2, v0)
        }
    }

    mtd drawCapSquare(p, d: Math.Vector2, sens: f32, pen: Pen, outline: f32)
    {
        let n    = Math.Vector2{d.y * sens, -d.x * sens}
        var ring = [p + d, p - d, p - d + n, p + d + n]
        .fillCapRing(ring, outline, pen)
    }

    mtd drawCapTriangle(p, d: Math.Vector2, sens: f32, pen: Pen, outline: f32)
    {
        let n    = Math.Vector2{d.y * sens, -d.x * sens}
        var ring = [p + d, p - d, p + n]
        .fillCapRing(ring, outline, pen)
    }

    mtd drawCapSquareAnchor(p1, d1: Math.Vector2, sens: f32, pen: Pen, start: bool, outline: f32)
    {
        let sx = start ? pen.capBegScaleX : pen.capEndScaleX
        let sy = start ? pen.capBegScaleY : pen.capEndScaleY

        let d = d1 * sx
        var n = Math.Vector2{d.y * sens, -d.x * sens}
        n.setLengthOrZero(d.length() * sy)
        let p = p1 - n * 0.5

        var ring = [p + d, p - d, p - d + n, p + d + n]
        .fillCapRing(ring, outline, pen)
    }

    mtd drawCapArrowAnchor2(p1, d1: Math.Vector2, sens: f32, pen: Pen, start: bool, outline: f32)
    {
        let sx  = start ? pen.capBegScaleX : pen.capEndScaleX
        let sy  = start ? pen.capBegScaleY : pen.capEndScaleY
        let sx2 = sx * sy * 2

        let d  = d1 * sx
        let n  = Math.Vector2{d.y * sens * sy, -d.x * sens * sy}
        let n1 = n.normalized()
        let p  = p1 - n

        // Two halves meeting along the axis. Expanding each of them is exactly expanding their
        // union: growing a shape by a fixed width distributes over the pieces it is made of, and
        // the notch between the two halves closes by the same width from both sides.
        var left  = [p + d - n1 * sx2, p, p + n]
        var right = [p - d - n1 * sx2, p, p + n]
        .fillCapRing(left, outline, pen)
        .fillCapRing(right, outline, pen)
    }

    mtd drawCapArrowAnchor(p1, d1: Math.Vector2, sens: f32, pen: Pen, start: bool, outline: f32)
    {
        let sx = start ? pen.capBegScaleX : pen.capEndScaleX
        let sy = start ? pen.capBegScaleY : pen.capEndScaleY

        let d = d1 * sx
        let n = Math.Vector2{d.y * sens * sy, -d.x * sens * sy}
        let p = p1 - n

        var ring = [p + d, p - d, p + n]
        .fillCapRing(ring, outline, pen)
    }

    mtd drawCapRoundAnchor(p, d: Math.Vector2, pen: Pen, start: bool, outline: f32)
    {
        let sx = start ? pen.capBegScaleX : pen.capEndScaleX

        let angle0 = Math.atan2(-d.y, -d.x)
        let angle1 = angle0 + Math.ConstF32.TwoPi
        let radius = sx * d.length() + outline
        .drawRound(p, radius, angle0, angle1, pen)
    }

    // A round end stays round at every width.
    //
    // Below a couple of pixels of radius this used to fall back to a triangle, which made `.Round`
    // and `.Triangle` the same end on any thin stroke — a dashed hairline in a PDF, a plan, a
    // schematic — and the choice between them do nothing. The arc is subdivided against the
    // flattening tolerance, so a small one costs the two triangles the fallback drew anyway.
    mtd drawCapRound(p, d: Math.Vector2, sens: f32, pen: Pen, outline: f32)
    {
        let angle0 = Math.atan2(-d.y, -d.x)
        let angle1 = angle0 + Math.ConstF32.Pi
        let radius = (d.length() + outline) * sens
        .drawRound(p, radius, angle0, angle1, pen)
    }

    mtd drawLineCap(capStyle: LineCapStyle, p, d: Math.Vector2, sens: f32, pen: Pen, start: bool, outline: f32)
    {
        switch #complete capStyle
        {
        case .None:         return
        case .Triangle:     .drawCapTriangle(p, d, sens, pen, outline)
        case .Round:        .drawCapRound(p, d, sens, pen, outline)
        case .Square:       .drawCapSquare(p, d, sens, pen, outline)
        case .SquareAnchor: .drawCapSquareAnchor(p, d, sens, pen, start, outline)
        case .ArrowAnchor:  .drawCapArrowAnchor(p, d, sens, pen, start, outline)
        case .ArrowAnchor2: .drawCapArrowAnchor2(p, d, sens, pen, start, outline)
        case .RoundAnchor:  .drawCapRoundAnchor(p, d, pen, start, outline)
        }
    }

    // `d` is the half-width of the stroke itself, so a dash end keeps the cap it asked for and a
    // border pass offsets that cap instead of drawing a larger one.
    //
    // Every width draws its dash ends. Dropping them under three pixels of pen silently ignored
    // the style on exactly the strokes that are drawn thin — a dashed hairline of a PDF asks for
    // round dash ends and got flat ones — and made the choice do nothing.
    mtd drawDashCap(cxt: *Context, capStyle: DashCapStyle, p, d: Math.Vector2, sens: f32)
    {
        switch #complete capStyle
        {
        case .None:     break
        case .Triangle: .drawCapTriangle(p, d, sens, cxt.pen[], cxt.outline)
        case .Round:    .drawCapRound(p, d, sens, cxt.pen[], cxt.outline)
        case .Square:   .drawCapSquare(p, d, sens, cxt.pen[], cxt.outline)
        }
    }

    // Closes the border across an end the stroke stops flat at.
    //
    // The widened quad the border pass lays down covers the two sides of the stroke, but stops
    // where the stroke does, leaving that edge bare. This is the piece that squares it off, the
    // same width as the border everywhere else. `dir` points out of the stroke.
    mtd drawOutlineButt(cxt: *Context, p, dir: Math.Vector2)
    {
        let n = cxt.normal
        let e = dir * cxt.outline

        let v0 = p - n
        let v1 = p + n
        let v2 = v1 + e
        let v3 = v0 + e

        let prim1 = .pushTriangle(v0, v1, v2, cxt.pen.brush.color)
        let prim2 = .pushTriangle(v0, v2, v3, cxt.pen.brush.color)
        if .curState.paintParams & .Antialiased
        {
            .addEdgeAA(prim1, v1, v2)
            .addEdgeAA(prim2, v2, v3)
            .addEdgeAA(prim2, v3, v0)
        }
    }

    // Reports whether the border has to close the start of the run being laid down.
    //
    // A cap already covers the end it sits on, so only an end left flat needs the extra piece:
    // the beginning of the path when it carries no cap, and the beginning of every later dash
    // when the pattern asks for none.
    private func outlineOpensRun(cxt: *Context)->bool
    {
        if cxt.pen.dashStyle == .None do
            return !cxt.path.isClosed and cxt.pen.begCapStyle == .None
        if cxt.firstLine and !cxt.path.isClosed do
            return cxt.pen.begCapStyle == .None
        return cxt.pen.dashBegCapStyle == .None
    }

    mtd drawJoinBevel(p, d1, d2: Math.Vector2, pen: Pen)
    {
        var v0 = p

        var v1, v2: Math.Vector2 = undefined
        if d1.x * d2.y - d1.y * d2.x < 0
        {
            v0 += d1 * 0.25
            v0 += d2 * 0.25
            v1 = Math.Vector2{p.x - d1.x, p.y - d1.y}
            v2 = Math.Vector2{p.x - d2.x, p.y - d2.y}
        }
        else
        {
            v0 -= d1 * 0.25
            v0 -= d2 * 0.25
            v1 = Math.Vector2{p.x + d1.x, p.y + d1.y}
            v2 = Math.Vector2{p.x + d2.x, p.y + d2.y}
        }

        let prim1 = .pushTriangle(v0, v1, v2, pen.brush.color)
        if .curState.paintParams & .Antialiased do
            .addEdgeAA(prim1, v1, v2)
    }

    mtd drawRound(center: Math.Vector2, radius: f32, angle0, angle1: f32, pen: Pen)
    {
        var startPos, endPos: Math.Vector2 = undefined
        startPos.x = center.x + (Math.cos(angle0) * radius)
        startPos.y = center.y + (Math.sin(angle0) * radius)
        endPos.x   = center.x + (Math.cos(angle1) * radius)
        endPos.y   = center.y + (Math.sin(angle1) * radius)

        // Cap and join arcs follow the flattening scale like every other curve, so a zoomed
        // stroke keeps round ends round.
        let minDist = LinePath.getFlattenDistance(.curState.paintQuality) / .curFlattenScale

        // We divide a segment by half until the computed point on the curve is
        // close to the corresponding segment
        .sharedRoundTmp.clear()
        .sharedRoundTmp.add({angle0, startPos})
        .sharedRoundTmp.add({angle1, endPos})

        var point: Math.Vector2 = undefined
        for var i = 0; i < .sharedRoundTmp.count - 1; i += 1
        {
            let angle = (.sharedRoundTmp[i].factor + .sharedRoundTmp[i + 1].factor) * 0.5
            point.x = center.x + (Math.cos(angle) * radius)
            point.y = center.y + (Math.sin(angle) * radius)
            let dist = Math.Geometry.distanceFromPointToLine(point, .sharedRoundTmp[i].pos, .sharedRoundTmp[i + 1].pos)
            if dist < minDist do
                continue

            .sharedRoundTmp.insertAt(cast(u64) i + 1, {angle, point})
            i -= 1
        }

        // Every triangle of the fan meets the others on the centre, and a pixel sitting exactly
        // on that shared point can fall outside all of them: a round line end over a contrasting
        // ground showed a single hole in its middle. Pull each apex back along its own sector so
        // consecutive triangles overlap there instead of meeting on a point. What that adds is a
        // half-pixel disc around the centre, which is inside the stroke this arc turns around.
        let span     = Math.abs(radius) * 2
        let apexPull = span > 0 ? Math.min(.aaHalfPathSpace() / span, 0.25'f32) : 0

        var v1 = startPos
        for i in 1 until .sharedRoundTmp.count
        {
            let v2    = .sharedRoundTmp[i].pos
            let apex  = center - ((v1 - center) + (v2 - center)) * apexPull
            let prim1 = .pushTriangle(apex, v1, v2, pen.brush.color)
            if .curState.paintParams & .Antialiased do
                .addEdgeAA(prim1, v1, v2)
            v1 = v2
        }
    }

    mtd drawJoinRound(p, d1, d2: Math.Vector2, pen: Pen)
    {
        var angle0, angle1: f32 = undefined
        if d1.x * d2.y - d1.y * d2.x < 0
        {
            angle0 = Math.atan2(-d1.y, -d1.x)
            angle1 = Math.atan2(-d2.y, -d2.x)
        }
        else
        {
            angle0 = Math.atan2(d1.y, d1.x)
            angle1 = Math.atan2(d2.y, d2.x)
        }

        if Math.isEqualEpsilon(angle0, angle1) do
            return

        let radius = d1.length()

        if angle1 > angle0 + Math.ConstF32.Pi do
            angle1 -= Math.ConstF32.TwoPi
        elif angle1 < angle0 - Math.ConstF32.Pi do
            angle1 += Math.ConstF32.TwoPi

        .drawRound(p, radius, angle0, angle1, pen)
    }

    mtd drawJoinMiter(p, d1, d2: Math.Vector2, justMiter: bool, pen: Pen)
    {
        var a = Math.Vector2{d1.x + d2.x, d1.y + d2.y}
        let w = d1.length()
        let l = a.length()
        if Math.isZeroEpsilon(l) do
            return

        var m2 = (2 * w) / l
        if m2 > pen.joinMiterLimit
        {
            if justMiter do
                m2 = pen.joinMiterLimit
            else do
                return .drawJoinBevel(p, d1, d2, pen)
        }

        a.x = a.x / l * m2 * w
        a.y = a.y / l * m2 * w

        var v0 = p

        var v1, v2, v3: Math.Vector2 = undefined
        if d1.x * d2.y - d1.y * d2.x < 0
        {
            v0 += d1 * 0.25
            v0 += d2 * 0.25
            v1 = Math.Vector2{p.x - d1.x, p.y - d1.y}
            v2 = Math.Vector2{p.x - a.x, p.y - a.y}
            v3 = Math.Vector2{p.x - d2.x, p.y - d2.y}
        }
        else
        {
            v0 -= d1 * 0.25
            v0 -= d2 * 0.25
            v1 = Math.Vector2{p.x + d1.x, p.y + d1.y}
            v2 = Math.Vector2{p.x + a.x, p.y + a.y}
            v3 = Math.Vector2{p.x + d2.x, p.y + d2.y}
        }

        let prim1 = .pushTriangle(v0, v1, v3, pen.brush.color)
        discard .pushTriangle(v1, v3, v2, pen.brush.color)
        if .curState.paintParams & .Antialiased
        {
            .addEdgeAA(prim1, v3, v2)
            .addEdgeAA(prim1, v1, v2)
        }
    }

    mtd drawJoin(cxt: *Context, p, d1, d2: Math.Vector2)
    {
        // `d1` and `d2` are the two corners the turn leaves apart, relative to the vertex, so
        // their distance bounds the sector this join fills. A minified pass sets a span below
        // which that sector cannot reach a pixel; see 'setMinifiedStrokeLimits'.
        if (d1 - d2).lengthSquared() < cxt.joinSkipSpanSquared do
            return

        switch #complete cxt.pen.joinStyle
        {
        case .None:       break
        case .Bevel:      .drawJoinBevel(p, d1, d2, cxt.pen[])
        case .Round:      .drawJoinRound(p, d1, d2, cxt.pen[])
        case .Miter:      .drawJoinMiter(p, d1, d2, true, cxt.pen[])
        case .MiterBevel: .drawJoinMiter(p, d1, d2, false, cxt.pen[])
        }
    }

    mtd drawDashEndCap(cxt: *Context, posCap, normalCap: Math.Vector2)
    {
        if cxt.beginLine or cxt.lastLineInvalid do
            return

        // Cap is defined
        if cxt.pen.dashEndCapStyle != DashCapStyle.None
        {
            .drawDashCap(cxt, cxt.pen.dashEndCapStyle, posCap, normalCap, -1.0)
            return
        }

        // The dash stops flat here, so a border pass closes itself across that end.
        if cxt.outline > 0
        {
            .drawOutlineButt(cxt, posCap, cxt.dir)
            return
        }

        // AA end edge if no cap. Copy the positions out first: addEdgeAA appends
        // fringe geometry, which may reallocate the vertex buffer, and invalidate
        // any pointer into it.
        if .curState.paintParams & .Antialiased
        {
            let prim2p = .vertexBuffer.buffer! + cxt.prim2
            let p      = prim2p.pos
            let q      = (prim2p + 2).pos
            .addEdgeAA(cxt.prim1, p, q)
        }
    }

    func drawMoveCursor(cxt: *Context, pos: Math.Vector2)
    {
        if pos.distanceTo(cxt.path.endPoint) < 1
        {
            cxt.prev = cxt.path.endPoint
            if cxt.path.isClosed do
                cxt.beginLine = true
        }
        else
        {
            cxt.prev      = pos
            cxt.beginLine = true
        }
    }

    mtd drawLineInternal(cxt: *Context, pos: Math.Vector2)
    {
        // Compute line (half width on each side)
        let newPos = pos
        var n      = newPos - cxt.prev

        // If previous and next point are too close, we will take
        // the last normal
        if !n.isZeroEpsilon()
        {
            n.normalize()
            cxt.dir    = n
            cxt.normal = n.cross(1)
            cxt.normal *= cxt.penSize2
        }

        // If this is still invalid, there's nothing we can:
        cxt.lastLineInvalid = cxt.normal.isZeroEpsilon()
        if cxt.lastLineInvalid do
            return

        // First line cap
        var flatBegin = !cxt.path.isClosed or cxt.pen.dashStyle != .None
        if cxt.pen.dashStyle != .None and (!cxt.firstLine or cxt.path.isClosed) and cxt.beginLine and cxt.pen.dashBegCapStyle != .None
        {
            flatBegin = false
            .drawDashCap(cxt, cxt.pen.dashBegCapStyle, cxt.prev, cxt.capNormal(), 1.0)
        }

        // The run starts flat here, so a border pass closes itself across that end.
        elif cxt.outline > 0 and cxt.beginLine and outlineOpensRun(cxt) do
            .drawOutlineButt(cxt, cxt.prev, -n)

        // Joints
        if !cxt.beginLine do
            .drawJoin(cxt, cxt.prev, cxt.normalPrev, cxt.normal)

        // Draw quad
        let v0 = cxt.prev - cxt.normal
        let v1 = newPos - cxt.normal
        let v3 = cxt.prev + cxt.normal
        let v2 = newPos + cxt.normal

        let antialiased = .curState.paintParams & .Antialiased
        if antialiased and .curState.paintParams & .DistanceStrokes
        {
            // One quad reaching past the contour by the antialiasing margin, carrying the signed
            // distance to the centre line. Two triangles replace the quad and the two bands.
            var unit = cxt.normal
            unit.normalizeOrZero()
            let margin = .aaHalfPathSpace(unit)
            let extent = cxt.normal + unit * margin

            // The contour sits at the half width, expressed against the span the quad covers.
            let halfWidth = Math.max(cxt.penSize2, 0.000001'f32)
            let edge      = 0.5 * (halfWidth + margin) / halfWidth

            cxt.prim1 = .pushStrokeSegment(cxt.prev, newPos, extent, edge, cxt.pen.brush.color.argb)
            cxt.prim2 = cxt.prim1 + 3
        }
        else
        {
            cxt.prim1 = .pushTriangle(v0, v1, v3, cxt.pen.brush.color)
            cxt.prim2 = .pushTriangle(v1, v3, v2, cxt.pen.brush.color)

            // Generate AA edges.
            //
            // One band per silhouette edge, not one per triangle sharing it: the two triangles of
            // a quad are on the same side of each of its edges, so a second call for the same edge
            // resolves to the same outward direction and emits the same six vertices. A stroked
            // document is mostly this geometry, and the copy cost every one of them.
            if antialiased
            {
                // The quad puts the pen normal on one side of each long edge, so which way each
                // band extrudes is known here and neither has to be derived from the quad's
                // centroid: the near edge always extrudes away from it and the far edge toward it.
                let color = cxt.pen.brush.color.argb
                .addEdgeAAFlipped(v0, v1, true, color)
                .addEdgeAAFlipped(v3, v2, false, color)
            }
        }

        // If we are starting a line, and the line does not have a cap before, then
        // we must AA the corresponding edge. The measured quad carries no distance along the
        // segment, so its butt end needs the band just as the banded one does.
        if antialiased and flatBegin and cxt.beginLine and (!cxt.firstLine or cxt.pen.begCapStyle == .None or cxt.path.isClosed) do
            .addEdgeAA(cxt.prim1, v0, v3)

        // To draw end joint
        if cxt.firstLine do
            cxt.normalFirst = cxt.normal

        cxt.normalPrev               = cxt.normal
        cxt.prev                     = newPos
        cxt.beginLine, cxt.firstLine = false
    }

    func preparePattern(cxt: *Context)
    {
        switch #complete cxt.pen.dashStyle
        {
        case .None:
            return

        case .Pattern:
            cxt.pattern      = cast(const [*] f32) cxt.pen.pattern.buffer!
            cxt.patternCount = cast(s32) cxt.pen.pattern.count
            if cxt.patternCount != 0 do
                break
            const P = [1.0, 1.0]
            cxt.pattern      = P.buffer
            cxt.patternCount = 2

        case .Dot:
            const P = [1.0, 1.0]
            cxt.pattern      = P.buffer
            cxt.patternCount = 2

        case .Dash:
            const P = [2.0, 1.0]
            cxt.pattern      = P.buffer
            cxt.patternCount = 2

        case .DashDot:
            const P = [2.0, 1.0, 1.0, 1.0]
            cxt.pattern      = P.buffer
            cxt.patternCount = 4
        }

        cxt.patternTotalLen = 0
        for i in cxt.patternCount do
            cxt.patternTotalLen += Math.max(cxt.pattern[i], 0.01)
        cxt.patternTotalLen *= cxt.pen.size

        let repeatCount = cast(s32) (cxt.path.polygon.perimeter / cxt.patternTotalLen)
        cxt.error = cxt.path.polygon.perimeter - (repeatCount * cxt.patternTotalLen)

        // We must dispatch error at each blank in the pattern. So "divError" is the
        // number of blanks to add at each 'move', between solid patterns
        let numBlanks = repeatCount * cxt.patternCount / 2
        cxt.divError = numBlanks ? cxt.error / numBlanks : 0

        // First pattern. We start at half the size of the first pattern, in order to not
        // finish on a blank, but with half the size of the first pattern also.
        cxt.patternIndex        = 0
        cxt.remainingPatternLen = Math.max(cxt.pattern[cxt.patternIndex], 0.01)
        cxt.remainingPatternLen *= cxt.pen.size
        if !cxt.path.isClosed and cxt.pen.dashStyle != .Pattern do
            cxt.remainingPatternLen *= 0.5

        if cxt.pen.dashOffset
        {
            var phase = cxt.pen.dashOffset
            if phase < 0 do
                phase = cxt.patternTotalLen - (Math.abs(phase) - Math.floor(Math.abs(phase) / cxt.patternTotalLen) * cxt.patternTotalLen)
            else do
                phase -= Math.floor(phase / cxt.patternTotalLen) * cxt.patternTotalLen
            if phase >= cxt.patternTotalLen do
                phase = 0

            while phase >= cxt.remainingPatternLen
            {
                phase                   -= cxt.remainingPatternLen
                cxt.patternIndex        = (cxt.patternIndex + 1) % cxt.patternCount
                cxt.remainingPatternLen = Math.max(cxt.pattern[cxt.patternIndex], 0.01) * cxt.pen.size
            }

            cxt.remainingPatternLen -= phase
        }
    }

    mtd drawLine(cxt: *Context, pos: Math.Vector2)
    {
        // solid
        if cxt.pen.dashStyle == .None
        {
            .drawLineInternal(cxt, pos)
            return
        }

        var v               = pos - cxt.prev
        var remainingSegLen = v.length()
        v.normalizeOrZero()

        // True when we are "drawing" blanks
        var blankPatternIdx = cxt.patternIndex & 1 ? true : false

        for
        {
            var lengthInPattern = cxt.remainingPatternLen

            // If we are drawing a blank, take care of error adjustement
            var addBlank = 0'f32
            if cxt.divError > 0 and blankPatternIdx
            {
                addBlank        = Math.min(cxt.error, cxt.divError)
                lengthInPattern += addBlank
            }

            if blankPatternIdx do
                lengthInPattern *= cxt.pen.dashBlankScale

            // The current remaining length in the current segment is greater
            // than what's left in the current pattern. We draw to cover the
            // current pattern, and change the pattern to be the next
            if remainingSegLen > lengthInPattern
            {
                let nextp = cxt.prev + (v * lengthInPattern)
                if blankPatternIdx
                {
                    .drawDashEndCap(cxt, cxt.prev, cxt.normal)
                    drawMoveCursor(cxt, nextp)
                    cxt.error -= addBlank
                }
                else
                {
                    .drawLineInternal(cxt, nextp)
                }

                // Start a new fresh pattern index
                remainingSegLen         -= lengthInPattern
                cxt.patternIndex        = (cxt.patternIndex + 1) % cxt.patternCount
                blankPatternIdx         = blankPatternIdx ? false : true
                cxt.remainingPatternLen = Math.max(cxt.pattern[cxt.patternIndex], 0.01)
                cxt.remainingPatternLen *= cxt.pen.size
                continue
            }

            // Here the segment does not have enough remaining length to cover the current
            // pattern. So draw what remains, and exit. The next line will try to cover the rest.
            cxt.remainingPatternLen -= remainingSegLen
            if blankPatternIdx
            {
                .drawDashEndCap(cxt, cxt.prev, cxt.normal)
                drawMoveCursor(cxt, pos)
            }
            else
            {
                .drawLineInternal(cxt, pos)
            }

            break
        }
    }

    // Optimized version that returns both distance and point information
    struct AnchorSkipInfo
    {
        distance:      f32
        adjustedPoint: Math.Vector2
        pointIndex:    u64
        hasAdjustment: bool
    }

    // Enhanced function that calculates skip distance AND finds the corresponding point
    func getAnchorSkipInfo(cxt: *Context, capStyle: LineCapStyle, start: bool)->AnchorSkipInfo
    {
        var info: AnchorSkipInfo
        info.hasAdjustment = false

        // Calculate skip distance
        switch capStyle
        {
        case .ArrowAnchor:
            let scale = start ? cxt.pen.capBegScaleX : cxt.pen.capEndScaleX
            info.distance = cxt.pen.size * 0.5 * scale

        case .ArrowAnchor2:
            let scale = start ? cxt.pen.capBegScaleX : cxt.pen.capEndScaleX
            info.distance = cxt.pen.size * 0.7 * scale

        case .SquareAnchor:
            let scale = start ? cxt.pen.capBegScaleX : cxt.pen.capEndScaleX
            info.distance = cxt.pen.size * 0.5 * scale
            info.distance -= 1

        case .RoundAnchor:
            let scale = start ? cxt.pen.capBegScaleX : cxt.pen.capEndScaleX
            info.distance = cxt.pen.size * 0.5 * scale
            info.distance -= Math.max(1, info.distance * 0.2)

        default:
            info.distance = 0
            return info
        }

        // If no skip distance needed, return early
        if info.distance <= 0 do
            return info

        let pointCount = cxt.path.polygon.points.count
        if pointCount < 2 do
            return info

        var accumulatedDistance = 0'f32

        if start
        {
            let startPoint = cxt.path.polygon.offsetPointAt(0, cxt.offsetPath)
            var lastPoint  = startPoint

            for i in 1 until pointCount
            {
                let currentPoint = cxt.path.polygon.offsetPointAt(i, cxt.offsetPath)
                let segmentVec   = currentPoint - lastPoint
                let segmentLen   = segmentVec.length()

                if segmentLen > 0.01
                {
                    if accumulatedDistance + segmentLen >= info.distance
                    {
                        // Found the target segment - calculate adjusted point
                        let remainingDist = info.distance - accumulatedDistance
                        let ratio         = remainingDist / segmentLen
                        info.adjustedPoint = lastPoint + segmentVec * ratio
                        info.pointIndex    = i
                        info.hasAdjustment = true
                        return info
                    }

                    accumulatedDistance += segmentLen
                    lastPoint           = currentPoint
                }
            }
        }
        else
        {
            let endPoint  = cxt.path.polygon.offsetPointAt(pointCount - 1, cxt.offsetPath)
            var lastPoint = endPoint

            for i in rangeTo(0'u64, pointCount - 2).reversed()
            {
                let currentPoint = cxt.path.polygon.offsetPointAt(i, cxt.offsetPath)
                let segmentVec   = lastPoint - currentPoint
                let segmentLen   = segmentVec.length()

                if segmentLen > 0.01
                {
                    if accumulatedDistance + segmentLen >= info.distance
                    {
                        // Found the target segment - calculate adjusted point
                        let remainingDist = info.distance - accumulatedDistance
                        let ratio         = remainingDist / segmentLen
                        info.adjustedPoint = lastPoint - segmentVec * ratio
                        info.pointIndex    = i
                        info.hasAdjustment = true
                        return info
                    }

                    accumulatedDistance += segmentLen
                    lastPoint           = currentPoint
                }
            }
        }

        return info
    }

    // Simplified drawPath method using the optimized approach
    mtd drawPath(cxt: *Context)
    {
        if cxt.path.polygon.points.isEmpty() do
            return

        cxt.penSize    = cxt.pen.size
        cxt.offsetPath = cxt.pen.plotOffset
        cxt.capSize2   = cxt.penSize * 0.5
        cxt.penSize2   = cxt.capSize2 + cxt.outline
        cxt.beginLine  = true
        cxt.firstLine  = true

        // Get skip information for both caps in one pass
        let beginSkipInfo = getAnchorSkipInfo(cxt, cxt.pen.begCapStyle, true)
        let endSkipInfo   = getAnchorSkipInfo(cxt, cxt.pen.endCapStyle, false)

        var actualStartPoint = cxt.path.polygon.offsetPointAt(0, cxt.offsetPath)
        var actualEndPoint   = cxt.path.polygon.offsetPointAt(cxt.path.polygon.points.count - 1, cxt.offsetPath)
        var startPointIndex  = 0'u64
        var endPointIndex    = cxt.path.polygon.points.count - 1

        // Apply adjustments if needed
        if !cxt.path.isClosed and beginSkipInfo.hasAdjustment
        {
            actualStartPoint = beginSkipInfo.adjustedPoint
            startPointIndex  = beginSkipInfo.pointIndex
        }

        if !cxt.path.isClosed and endSkipInfo.hasAdjustment
        {
            actualEndPoint = endSkipInfo.adjustedPoint
            endPointIndex  = endSkipInfo.pointIndex
        }

        // Set starting position
        cxt.prev = actualStartPoint

        // Draw line caps first (if not closed)
        if !cxt.path.isClosed
        {
            // Draw begin cap
            if cxt.pen.begCapStyle != .None
            {
                let v1 = cxt.path.polygon.offsetPointAt(0, cxt.offsetPath)
                let v2 = beginSkipInfo.hasAdjustment ? actualStartPoint : cxt.path.polygon.offsetPointAt(1, cxt.offsetPath)
                var n  = v2 - v1
                n.normalizeOrZero()
                var c = n.cross(1)
                c *= cxt.capSize2
                .drawLineCap(cxt.pen.begCapStyle, v1, c, 1.0, cxt.pen[], true, cxt.outline)
            }

            // Draw end cap
            if cxt.pen.endCapStyle != .None
            {
                let v1 = cxt.path.polygon.offsetPointAt(cxt.path.polygon.points.count - 1, cxt.offsetPath)
                let v2 = endSkipInfo.hasAdjustment ? actualEndPoint : cxt.path.polygon.offsetPointAt(cxt.path.polygon.points.count - 2, cxt.offsetPath)
                var n  = v1 - v2
                n.normalizeOrZero()
                var c = n.cross(1)
                c *= cxt.capSize2
                .drawLineCap(cxt.pen.endCapStyle, v1, c, -1.0, cxt.pen[], false, cxt.outline)
            }
        }

        // Draw the line segments with proper start/end adjustment
        if cxt.path.polygon.points.count > 1
        {
            // Draw intermediate segments
            if startPointIndex < endPointIndex
            {
                // Draw from adjusted start to the appropriate next point
                if startPointIndex < cxt.path.polygon.points.count
                {
                    let nextPoint = cxt.path.polygon.offsetPointAt(startPointIndex, cxt.offsetPath)
                    let startTo   = actualStartPoint - nextPoint
                    if startTo.length() > 0.01 do
                        .drawLine(cxt, nextPoint)
                }

                for i in (startPointIndex + 1) to endPointIndex
                {
                    if i < cxt.path.polygon.points.count
                    {
                        let p = cxt.path.polygon.offsetPointAt(i, cxt.offsetPath)

                        // A contour is only accurate to its flattening tolerance, so a point
                        // that close to the one already reached describes no separate place;
                        // a whole quad, its fringes and its join for it are geometry the
                        // device grid cannot show. The last point is always kept, so the
                        // stroke still ends where the contour does.
                        if i != endPointIndex and p.distanceSquaredTo(cxt.prev) < cxt.minStepSquared do
                            continue
                        .drawLine(cxt, p)
                    }
                }

                // Draw final segment to adjusted end point if needed
                let endTo = actualEndPoint - cxt.path.polygon.offsetPointAt(endPointIndex, cxt.offsetPath)
                if endTo.length() > 0.01
                {
                    .drawLine(cxt, actualEndPoint)
                }
            }
            else
            {
                .drawLine(cxt, actualEndPoint)
            }
        }

        // The path stops flat there, so a border pass closes itself across that end. A walk that
        // finished on a blank already closed its last dash and has nothing left to end.
        let openEnd = !cxt.lastLineInvalid and !cxt.path.isClosed and cxt.pen.endCapStyle == .None
        if openEnd and cxt.outline > 0 and !cxt.beginLine
        {
            .drawOutlineButt(cxt, cxt.prev, cxt.dir)
        }

        // Handle AA and closing as before...
        elif openEnd and (.curState.paintParams & .Antialiased)
        {
            // Copy positions out before addEdgeAA: it appends geometry and may
            // reallocate the vertex buffer, invalidating pointers into it.
            let prim2p = .vertexBuffer.buffer! + cxt.prim2
            let p      = prim2p.pos
            let q      = (prim2p + 2).pos
            .addEdgeAA(cxt.prim1, p, q)
        }
        elif cxt.path.isClosed and !cxt.firstLine and !cxt.beginLine
        {
            .drawJoin(cxt, cxt.prev, cxt.normal, cxt.normalFirst)
        }
    }
}

// Reports whether `pen` asks for a border outside its stroke.
private func strokeHasOutline(pen: Pen)->bool
{
    return pen.outlineSize > 0 and pen.outlineColor.a != 0
}

// The pen the border pass strokes with: the same geometry, painted with the border's own colour.
//
// It keeps the pen's own width, dash pattern and cap styles, because the border is that stroke
// pushed outward rather than a wider one: widening the pen would stretch the dash pattern and
// enlarge every cap along with it.
private func strokeOutlinePen(pen: Pen)->Pen
{
    var result = pen
    result.brush       = Brush.createSolid(pen.outlineColor)
    result.outlineSize = 0
    return result
}

// Returns the pen a sub-pixel stroke is drawn with: exactly one device pixel wide, with
// the width it could not occupy moved into the paint opacity.
//
// A stroke thinner than a device pixel has no representation in coverage alone — the
// fringe it produces rounds away — so drawing it unchanged and dropping it look the same.
// Vector artwork shown below its authored size is mostly such strokes: a map outline, a
// plan, a schematic. Promoting them keeps the drawing legible and lets its weight fade
// with the scale instead of vanishing at a threshold.
//
// `deviceScale` is the physical pixels-per-unit ratio text resolution reads, so a hairline
// on a 125% display is already a whole device pixel and never reaches here.
private func promoteHairline(pen: Pen, deviceScale: f32)->Pen
{
    var result = pen
    result.size = 1 / deviceScale
    result.brush.multiplyOpacity(pen.size * deviceScale)

    // Dash lengths are stroke-width multiples, so widening the pen must not lengthen them.
    if result.dashStyle == .Pattern
    {
        let ratio = pen.size / result.size
        for &value in result.pattern do
            value[] *= ratio
    }

    return result
}

public impl Painter
{
    // Draw a line path.
    mtd drawPath(path: *LinePath, color: Color, penSize: f32)
    {
        let pen = Pen.createSolid(color, penSize)
        .drawPath(path, pen)
    }

    mtd drawPath(path: *LinePath, pen: Pen)
    {
        let deviceScale = .textTransformScale()
        if pen.size <= 0 or deviceScale <= 0 do
            return
        if pen.size * deviceScale >= 1
        {
            .strokePath(path, pen)
            return
        }

        .strokePath(path, promoteHairline(pen, deviceScale))
    }

    // Fills in what a minified pass is allowed to leave out of a stroke.
    //
    // Only a minified pass leaves anything out. At its own scale or above, a contour was
    // flattened for exactly the tolerance it is drawn at, every point it holds earns its
    // segment, and every join fills a wedge the grid can show; below it, the contour carries
    // the detail of a size the pass is not showing, and walking all of it spends most of a
    // stroke's geometry on places one device pixel cannot tell apart.
    //
    // The step is the tolerance the pass would have flattened with. A dashed stroke keeps
    // every point, because the pattern is laid along the segments it is given.
    private mtd setMinifiedStrokeLimits(cxt: *Context, pen: Pen)
    {
        cxt.minStepSquared, cxt.joinSkipSpanSquared = 0
        if .curFlattenScale >= 1 do
            return

        if pen.dashStyle == .None
        {
            let step = LinePath.getFlattenDistance(.curState.paintQuality) / .curFlattenScale
            cxt.minStepSquared = step * step
        }

        // A join bridges the two outer corners the turn leaves apart, so the sector it fills
        // is never wider than the distance between them. A tenth of a device pixel of that,
        // in the path units the corners are measured in.
        let deviceScale = .textTransformScale()
        if deviceScale > 0
        {
            let span = 0.1 / deviceScale
            cxt.joinSkipSpanSquared = span * span
        }
    }

    // Lays down one already-flattened path in one pass: the stroke itself when `outline` is zero,
    // the border outside it otherwise.
    private mtd strokePathPass(path: *LinePath, pen: Pen, outline: f32)
    {
        var cxt: Context
        cxt.path    = path
        cxt.pen     = &pen
        cxt.outline = outline
        .setMinifiedStrokeLimits(&cxt, pen)
        if pen.dashStyle != .None do
            preparePattern(&cxt)

        var bvMin = path.minBounds
        var bvMax = path.maxBounds
        bvMin -= pen.size / 2 + outline
        bvMax += pen.size / 2 + outline
        .setTexture0(bvMin, bvMax, pen.brush)
        .resetTextureFont()

        .startOverlapMode(pen)
        .drawPath(&cxt)
        .stopOverlapMode()
    }

    // One stroking pass over a single path, with the hairline promotion its width may need.
    private mtd strokeOnePath(path: *LinePath, pen: Pen, outline: f32)
    {
        let deviceScale = .textTransformScale()
        if pen.size <= 0 or deviceScale <= 0 do
            return

        path.flatten(.curState.paintQuality, .curFlattenScale)
        if Math.isZeroEpsilon(path.polygon.perimeter) do
            return

        if pen.size * deviceScale >= 1
        {
            .strokePathPass(path, pen, outline)
            return
        }

        .strokePathPass(path, promoteHairline(pen, deviceScale), outline)
    }

    private mtd strokePath(path: *LinePath, pen: Pen)
    {
        path.flatten(.curState.paintQuality, .curFlattenScale)
        if Math.isZeroEpsilon(path.polygon.perimeter) do
            return

        // The border is the same walk, one width wider and with every cap and dash end pushed
        // out rather than enlarged, so the stroke laid over it leaves exactly that width showing.
        if strokeHasOutline(pen) do
            .strokePathPass(path, strokeOutlinePen(pen), pen.outlineSize)
        .strokePathPass(path, pen, 0)
    }

    // Draw a list of paths.
    mtd drawPath(pathList: *LinePathList, pen: Pen, mode: DrawPathListMode = .Separate)
    {
        if !pathList.paths.count do
            return
        if mode == .Separate
        {
            // One path's border must never cover another's stroke, so the whole list is
            // bordered before any of it is stroked.
            if strokeHasOutline(pen)
            {
                let border = strokeOutlinePen(pen)
                for p in pathList.paths do
                    .strokeOnePath(p, border, pen.outlineSize)

                var plain = pen
                plain.outlineSize = 0
                for p in pathList.paths do
                    .strokeOnePath(p, plain, 0)
                return
            }

            for p in pathList.paths do
                .drawPath(p, pen)
            return
        }

        let deviceScale = .textTransformScale()
        if pen.size <= 0 or deviceScale <= 0 do
            return
        if pen.size * deviceScale >= 1
        {
            .strokePathList(pathList, pen)
            return
        }

        .strokePathList(pathList, promoteHairline(pen, deviceScale))
    }

    private mtd strokePathList(pathList: *LinePathList, pen: Pen)
    {
        pathList.flatten(.curState.paintQuality, .curFlattenScale)

        // One path's border must never cover another's stroke, so the whole list is bordered
        // before any of it is stroked.
        if strokeHasOutline(pen) do
            .strokePathListPass(pathList, strokeOutlinePen(pen), pen.outlineSize)
        .strokePathListPass(pathList, pen, 0)
    }

    private mtd strokePathListPass(pathList: *LinePathList, pen: Pen, outline: f32)
    {
        var bvMin = pathList.minBounds
        var bvMax = pathList.maxBounds
        bvMin -= pen.size / 2 + outline
        bvMax += pen.size / 2 + outline
        .setTexture0(bvMin, bvMax, pen.brush)
        .resetTextureFont()

        .startOverlapMode(pen)

        var cxt: Context
        cxt.outline = outline
        .setMinifiedStrokeLimits(&cxt, pen)
        for p in pathList.paths
        {
            cxt.path = p
            cxt.pen  = &pen
            if pen.dashStyle != .None do
                preparePattern(&cxt)
            .drawPath(&cxt)
        }

        .stopOverlapMode()
    }

    mtd drawPath(pathList: *LinePathList, color: Color, penSize: f32, mode: DrawPathListMode = .Separate)
    {
        if !pathList.paths.count do
            return

        let pen = Pen.createSolid(color, penSize)
        .drawPath(pathList, pen, mode)
    }

    // Returns the extent of a cap in the frame of the line it terminates.
    //
    // `lineSize` is the stroke width the cap is measured against, and `capScaleX`/`capScaleY` are
    // the scales the pen applies to an anchor. `w` is how far the cap stands across the line and
    // `l` how far it reaches past the point it is placed on; an arrow head answers zero for `l`,
    // because its tip is that point and its body lies back along the line.
    //
    // These are the two axes of the line, not of the drawing. A layer or a cell reserving room
    // around a cap wants [[Pixel.Painter.capStyleRadius]] instead, unless it knows which way the
    // line runs.
    func capStyleExtent(capStyle: LineCapStyle, lineSize, capScaleX: f32, capScaleY: f32 = 2)->{ w: f32, l: f32 }
    {
        let half = lineSize * 0.5
        switch #complete capStyle
        {
        case .None:         return {half, 0}
        case .Triangle:     return {half, half}
        case .Round:        return {half, half}
        case .Square:       return {half, half}
        case .ArrowAnchor:  return {half * capScaleX, 0}
        case .ArrowAnchor2: return {half * capScaleX, 0}
        case .SquareAnchor: return {half * capScaleX, half * capScaleX * capScaleY * 0.5}
        case .RoundAnchor:  return {half * capScaleX, half * capScaleX}
        }

        return {0, 0}
    }

    // Returns how far a cap reaches from the point it is placed on, in any direction.
    //
    // A cap stands across its line as well as along it, so its far corner sits at the diagonal of
    // the two and lands anywhere on the drawing depending on which way the line runs. This is the
    // radius that holds it whatever that direction is, which is what an axis-aligned box around
    // the geometry has to reserve: measured from the two axes alone, that box cuts the corner off
    // a square end or an arrow head as soon as the line stops being axis aligned.
    func capStyleRadius(capStyle: LineCapStyle, lineSize, capScaleX: f32, capScaleY: f32 = 2)->f32
    {
        func hypot(a, b: f32)->f32 => Math.sqrt(a * a + b * b)

        let half  = lineSize * 0.5
        let width = half * capScaleX
        switch #complete capStyle
        {
        case .None, .Triangle, .Round:
            return half

        case .Square:
            return hypot(half, half)

        case .SquareAnchor:
            return hypot(width, width * capScaleY * 0.5)

        case .RoundAnchor:
            return width

        case .ArrowAnchor:
            return hypot(width, width * capScaleY)

        // The alternate head pulls its two back corners further along the line than the head
        // itself reaches, by a length the scales set on their own.
        case .ArrowAnchor2:
            return hypot(width, width * capScaleY + capScaleX * capScaleY * 2)
        }

        return 0
    }
}
