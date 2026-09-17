using Swag, Core

// Multi-channel signed distance field generation.
//
// This is a from-scratch port of the core ideas of Viktor Chlumsky's msdfgen:
//   - each outline edge is assigned one of three "colors" (a 2-bit subset of the
//     RGB channels) so that, across a corner, the two incident edges always share
//     exactly one channel,
//   - for each channel we keep the signed pseudo-distance to the nearest edge that
//     carries that channel,
//   - at render time the shader reconstructs the true distance as the median of the
//     three channels, which preserves sharp corners that a single-channel SDF rounds.
//
// Edges are flattened to line segments (reusing the same tessellation as the bitmap
// and SDF rasterizers); curve fidelity is controlled by the flattening tolerance.
//
// Distances are measured to the boundary of the outline's nonzero fill, not to its raw
// contours: contours that overlap or fold over themselves are cut and trimmed first, which
// is the work msdfgen hands to Skia's path simplification.

const MSDF_BLACK   = 0'u8
const MSDF_RED     = 1'u8
const MSDF_GREEN   = 2'u8
const MSDF_BLUE    = 4'u8
const MSDF_YELLOW  = 3'u8
const MSDF_MAGENTA = 5'u8
const MSDF_CYAN    = 6'u8
const MSDF_WHITE   = 7'u8

// One flattened outline segment, with everything the distance evaluation would otherwise
// recompute at every sample point. A glyph holds a few hundred of these and is measured at
// a few thousand points, so the derived quantities are worth their storage.
struct MsdfSeg
{
    minX, minY: f64     // Bounding box, tested first to reject a segment before any square root.
    maxX, maxY: f64
    x0, y0:     f64     // Segment start.
    abx, aby:   f64     // Start-to-end vector; the end point is the start plus this.
    ab2:        f64     // Squared length of that vector.

    // The length and its reciprocal are both kept because the distance evaluation divides by
    // one and multiplies by the other, and the two do not round alike. Deriving either from
    // the other would move the field by a unit in the last place, which is enough to swing a
    // tie between two segments and move a pixel of a corner.
    len:    f64     // Length of the start-to-end vector.
    invLen: f64     // Its reciprocal, zero for a degenerate segment.

    color: u8     // Channel subset this segment carries.
}

// One outline crossing of a sample row.
//
// Inside/outside is a property of a whole row, so the crossings are gathered once per row
// and swept across it, instead of winding the entire outline at every pixel.
struct MsdfCrossing
{
    x:   f64     // Where the segment crosses the row.
    dir: s32     // Plus one when the segment runs upwards through the row, minus one downwards.
}

struct MsdfElement
{
    firstSeg:   u32     // first segment index in the flat segment list
    segCount:   u32
    sdx0, sdy0: f64     // normalized direction at the element start
    edx1, edy1: f64     // normalized direction at the element end
    color:      u8
}

func msdfNormDir(dx, dy: f64)->{ x: f64, y: f64 }
{
    var result: retval
    let len = Math.sqrt(dx * dx + dy * dy)
    if len > 0
    {
        result.x = dx / len
        result.y = dy / len
    }

    return result
}

func msdfIsDegenerate(x0, y0, x1, y1: f64)->bool
{
    return Math.isEqualEpsilon(x0, x1, 0.000001) and Math.isEqualEpsilon(y0, y1, 0.000001)
}

func msdfAddSeg(segs: *Array'MsdfSeg, x0, y0, x1, y1: f64, color = MSDF_BLACK)
{
    if msdfIsDegenerate(x0, y0, x1, y1) do
        return

    var seg: MsdfSeg
    seg.color = color
    seg.x0    = x0
    seg.y0    = y0
    seg.abx   = x1 - x0
    seg.aby   = y1 - y0
    seg.ab2   = seg.abx * seg.abx + seg.aby * seg.aby
    seg.len   = Math.sqrt(seg.ab2)
    if seg.ab2 > 0 do
        seg.invLen = 1.0 / seg.len

    seg.minX = Math.min(x0, x1)
    seg.maxX = Math.max(x0, x1)
    seg.minY = Math.min(y0, y1)
    seg.maxY = Math.max(y0, y1)
    segs.add(seg)
}

func msdfFlattenQuadratic(segs: *Array'MsdfSeg, x0, y0, x1, y1, x2, y2, tolerance: f64, depth: u32 = 0)
{
    if depth >= 12 or quadraticFlatEnough(x0, y0, x1, y1, x2, y2, tolerance)
    {
        msdfAddSeg(segs, x0, y0, x2, y2)
        return
    }

    let x01  = (x0 + x1) * 0.5
    let y01  = (y0 + y1) * 0.5
    let x12  = (x1 + x2) * 0.5
    let y12  = (y1 + y2) * 0.5
    let x012 = (x01 + x12) * 0.5
    let y012 = (y01 + y12) * 0.5

    msdfFlattenQuadratic(segs, x0, y0, x01, y01, x012, y012, tolerance, depth + 1)
    msdfFlattenQuadratic(segs, x012, y012, x12, y12, x2, y2, tolerance, depth + 1)
}

func msdfFlattenCubic(segs: *Array'MsdfSeg, x0, y0, x1, y1, x2, y2, x3, y3, tolerance: f64, depth: u32 = 0)
{
    if depth >= 16 or cubicFlatEnough(x0, y0, x1, y1, x2, y2, x3, y3, tolerance)
    {
        msdfAddSeg(segs, x0, y0, x3, y3)
        return
    }

    let x01   = (x0 + x1) * 0.5
    let y01   = (y0 + y1) * 0.5
    let x12   = (x1 + x2) * 0.5
    let y12   = (y1 + y2) * 0.5
    let x23   = (x2 + x3) * 0.5
    let y23   = (y2 + y3) * 0.5
    let x012  = (x01 + x12) * 0.5
    let y012  = (y01 + y12) * 0.5
    let x123  = (x12 + x23) * 0.5
    let y123  = (y12 + y23) * 0.5
    let x0123 = (x012 + x123) * 0.5
    let y0123 = (y012 + y123) * 0.5

    msdfFlattenCubic(segs, x0, y0, x01, y01, x012, y012, x0123, y0123, tolerance, depth + 1)
    msdfFlattenCubic(segs, x0123, y0123, x123, y123, x23, y23, x3, y3, tolerance, depth + 1)
}

// msdfgen's "switchColor": deterministically pick the next edge color.
func msdfSwitchColor(color: *u8, seed: *u64, banned: u8 = MSDF_BLACK)
{
    let combined = color[] & banned
    if combined == MSDF_RED or combined == MSDF_GREEN or combined == MSDF_BLUE
    {
        color[] = combined ^ MSDF_WHITE
        return
    }

    if color[] == MSDF_BLACK or color[] == MSDF_WHITE
    {
        let start: [3] u8 = [MSDF_CYAN, MSDF_MAGENTA, MSDF_YELLOW]
        color[] = start[seed[] % 3]
        seed[]  /= 3
        return
    }

    let shifted = cast(u32) color[] << (1 + (seed[] & 1))
    color[] = cast(u8) ((shifted | (shifted >> 3)) & MSDF_WHITE)
    seed[]  >>= 1
}

func msdfIsCorner(ax, ay, bx, by, crossThreshold: f64)->bool
{
    let dot = ax * bx + ay * by
    let crs = ax * by - ay * bx
    return dot <= 0 or Math.abs(crs) > crossThreshold
}

// Color all elements of one contour so that incident edges across a corner differ.
func msdfColorContour(elements: *Array'MsdfElement, first, count: u32, seed: *u64)
{
    // sin(3 degrees): direction changes beyond this angle are treated as corners.
    let crossThreshold = 0.05233595624294383'f64

    var corners: Array'u32
    let ebuf = elements.storage()
    var pdx  = ebuf[first + count - 1].edx1
    var pdy  = ebuf[first + count - 1].edy1
    for i in count
    {
        let e = &ebuf[first + i]
        if msdfIsCorner(pdx, pdy, e.sdx0, e.sdy0, crossThreshold) do
            corners.add(i)
        pdx = e.edx1
        pdy = e.edy1
    }

    // Smooth contour (no corners): a single channel set is enough, the median
    // then matches a plain single-channel SDF, which is correct for such shapes.
    if corners.isEmpty()
    {
        for i in count do
            ebuf[first + i].color = MSDF_WHITE
        return
    }

    // A single corner cannot alternate back to a distinct color, so fall back to
    // one switched color for the whole contour (these "teardrop" shapes are rare).
    if corners.count == 1
    {
        var color = MSDF_WHITE
        msdfSwitchColor(&color, seed)
        for i in count do
            ebuf[first + i].color = color
        return
    }

    let cornerCount = cast(u32) corners.count
    var spline      = 0'u32
    let start       = corners[0]
    var color       = MSDF_WHITE
    msdfSwitchColor(&color, seed)
    let initialColor = color

    for i in count
    {
        let index = (start + i) % count
        if spline + 1 < cornerCount and corners[spline + 1] == index
        {
            spline += 1
            let banned = spline == cornerCount - 1 ? initialColor : MSDF_BLACK
            msdfSwitchColor(&color, seed, banned)
        }

        ebuf[first + index].color = color
    }
}

// Build colored line segments from a glyph outline, in font pixel units (y up).
//
// `segs` receives every segment of the outline, whose nonzero winding is the glyph's fill.
// `edges` receives the boundary of that fill, which is what distances are measured to.
func buildMsdfSegments(outline: const *Outline, segs, edges: *Array'MsdfSeg)
{
    let commands  = buildOutlineCommands(outline)
    let tolerance = 0.20 / OVERSAMPLE

    var elements:         Array'MsdfElement
    var contourElemStart: Array'u32
    var contourSegStart:  Array'u32

    var curX: f64 = 0
    var curY: f64 = 0

    for cmd in commands
    {
        switch cmd.kind
        {
        case .MoveTo:
            contourElemStart.add(cast(u32) elements.count)
            contourSegStart.add(cast(u32) segs.count)
            curX = cmd.p0.x / 64.0'f64
            curY = cmd.p0.y / 64.0'f64

        case .LineTo:
            let x = cmd.p0.x / 64.0'f64
            let y = cmd.p0.y / 64.0'f64

            var el: MsdfElement
            el.firstSeg = cast(u32) segs.count
            msdfAddSeg(segs, curX, curY, x, y)
            el.segCount = cast(u32) segs.count - el.firstSeg

            let {dx, dy} = msdfNormDir(x - curX, y - curY)
            el.sdx0, el.edx1 = dx
            el.sdy0, el.edy1 = dy
            elements.add(el)

            curX = x
            curY = y

        case .ConicTo:
            let cx = cmd.p0.x / 64.0'f64
            let cy = cmd.p0.y / 64.0'f64
            let x  = cmd.p1.x / 64.0'f64
            let y  = cmd.p1.y / 64.0'f64

            var el: MsdfElement
            el.firstSeg = cast(u32) segs.count
            msdfFlattenQuadratic(segs, curX, curY, cx, cy, x, y, tolerance)
            el.segCount = cast(u32) segs.count - el.firstSeg

            var s0x = cx - curX
            var s0y = cy - curY
            if Math.isZeroEpsilon(cast(f32) s0x) and Math.isZeroEpsilon(cast(f32) s0y)
            {
                s0x = x - curX
                s0y = y - curY
            }

            var e1x = x - cx
            var e1y = y - cy
            if Math.isZeroEpsilon(cast(f32) e1x) and Math.isZeroEpsilon(cast(f32) e1y)
            {
                e1x = x - curX
                e1y = y - curY
            }

            let {sdx, sdy} = msdfNormDir(s0x, s0y)
            let {edx, edy} = msdfNormDir(e1x, e1y)
            el.sdx0 = sdx
            el.sdy0 = sdy
            el.edx1 = edx
            el.edy1 = edy
            elements.add(el)

            curX = x
            curY = y

        case .CubicTo:
            let c0x = cmd.p0.x / 64.0'f64
            let c0y = cmd.p0.y / 64.0'f64
            let c1x = cmd.p1.x / 64.0'f64
            let c1y = cmd.p1.y / 64.0'f64
            let x   = cmd.p2.x / 64.0'f64
            let y   = cmd.p2.y / 64.0'f64

            var el: MsdfElement
            el.firstSeg = cast(u32) segs.count
            msdfFlattenCubic(segs, curX, curY, c0x, c0y, c1x, c1y, x, y, tolerance)
            el.segCount = cast(u32) segs.count - el.firstSeg

            // A control point coincident with its endpoint carries no direction; the
            // next-best tangent is the one the other control or the chord gives.
            var s0x = c0x - curX
            var s0y = c0y - curY
            if Math.isZeroEpsilon(cast(f32) s0x) and Math.isZeroEpsilon(cast(f32) s0y)
            {
                s0x = c1x - curX
                s0y = c1y - curY
            }

            if Math.isZeroEpsilon(cast(f32) s0x) and Math.isZeroEpsilon(cast(f32) s0y)
            {
                s0x = x - curX
                s0y = y - curY
            }

            var e1x = x - c1x
            var e1y = y - c1y
            if Math.isZeroEpsilon(cast(f32) e1x) and Math.isZeroEpsilon(cast(f32) e1y)
            {
                e1x = x - c0x
                e1y = y - c0y
            }

            if Math.isZeroEpsilon(cast(f32) e1x) and Math.isZeroEpsilon(cast(f32) e1y)
            {
                e1x = x - curX
                e1y = y - curY
            }

            let {sdx, sdy} = msdfNormDir(s0x, s0y)
            let {edx, edy} = msdfNormDir(e1x, e1y)
            el.sdx0 = sdx
            el.sdy0 = sdy
            el.edx1 = edx
            el.edy1 = edy
            elements.add(el)

            curX = x
            curY = y
        }
    }

    contourElemStart.add(cast(u32) elements.count)
    contourSegStart.add(cast(u32) segs.count)

    var seed = 0'u64
    for c in contourElemStart.count - 1
    {
        let first = contourElemStart[c]
        let count = contourElemStart[c + 1] - first
        if count == 0 do
            continue
        msdfColorContour(&elements, first, count, &seed)
    }

    if not segs.count do
        return
    let sbuf = segs.storage()

    // Propagate element colors down to their segments.
    for el in elements
    {
        for i in el.segCount do
            sbuf[el.firstSeg + i].color = el.color
    }

    msdfResolveBoundary(segs.toSlice(), contourSegStart.toSlice(), edges)
    if edges.isEmpty() do
        return

    // Guarantee every channel is carried by at least one edge, otherwise that
    // channel's distance would be undefined and the median would be meaningless.
    let ebuf       = edges.storage()
    var unionColor = 0'u8
    for i in edges.count do
        unionColor |= ebuf[i].color
    let missing = (~unionColor) & MSDF_WHITE
    if missing
    {
        for i in edges.count do
            ebuf[i].color |= missing
    }
}

// Where one segment is crossed by another, and has to be cut in two.
struct MsdfCut
{
    seg:  u32     // The segment that is cut.
    t:    f64     // Where along it, from 0 at its start to 1 at its end.
    x, y: f64     // The point itself, shared by every segment that meets there.
}

// A segment's vertical start, to sweep the outline from the bottom up.
struct MsdfSweep
{
    minY: f64
    seg:  u32
}

// How far inside its ends a crossing has to fall to cut a segment. A crossing at an end is
// where the segment meets its neighbor, and cuts nothing.
const MsdfCutMargin: f64 = 0.000000001

// Below this sine two segments are parallel, and only cross by overlapping on one line.
const MsdfParallelSine: f64 = 0.000000000001

// How far off a segment's line, in pixels, a parallel segment still lies on it.
const MsdfCollinearDist: f64 = 0.000000001

// How far on either side of a segment, in pixels, the fill is probed.
const MsdfSideProbe: f64 = 0.0001

// Winding number of the outline around a point, counted over a ray cast to the right with the
// same half-open rule as a sample row.
func msdfWindingAt(segs: const [..] MsdfSeg, px, py: f64)->s32
{
    var winding = 0's32
    for &s in segs where py >= s.minY and py < s.maxY
    {
        if s.x0 + s.abx * (py - s.y0) / s.aby > px do
            winding += s.aby > 0 ? 1 : -1
    }

    return winding
}

// Which side of a line the fill of `segs` lies on: 1 on its right, which is the side its
// signed distance counts as positive, -1 on its left, and 0 when the fill lies on both sides
// or on neither, so that the line is no boundary.
func msdfFillSide(segs: const [..] MsdfSeg, x0, y0, x1, y1: f64)->s32
{
    let dx      = x1 - x0
    let dy      = y1 - y0
    let probe   = MsdfSideProbe / Math.sqrt(dx * dx + dy * dy)
    let toLeftX = -dy * probe
    let toLeftY = dx * probe
    let midX    = (x0 + x1) * 0.5
    let midY    = (y0 + y1) * 0.5
    let left    = msdfWindingAt(segs, midX + toLeftX, midY + toLeftY) != 0
    let right   = msdfWindingAt(segs, midX - toLeftX, midY - toLeftY) != 0
    if left == right do
        return 0
    return right ? 1 : -1
}

// Cuts `s` at a point already known to lie on its line, when the point falls inside it.
func msdfCutAt(s: const *MsdfSeg, index: u32, x, y: f64, cuts: *Array'MsdfCut)
{
    let t = ((x - s.x0) * s.abx + (y - s.y0) * s.aby) / s.ab2
    if t > MsdfCutMargin and t < 1 - MsdfCutMargin do
        cuts.add(MsdfCut{index, t, x, y})
}

// Records the cuts two segments make in each other.
func msdfCutPair(a, b: const *MsdfSeg, ia, ib: u32, cuts: *Array'MsdfCut)
{
    let qpx   = b.x0 - a.x0
    let qpy   = b.y0 - a.y0
    let cross = a.abx * b.aby - a.aby * b.abx

    // Parallel segments only meet by overlapping on one line, and then each is cut where the
    // other ends.
    if Math.abs(cross) <= MsdfParallelSine * a.len * b.len
    {
        if Math.abs(qpx * a.aby - qpy * a.abx) > MsdfCollinearDist * a.len do
            return
        msdfCutAt(a, ia, b.x0, b.y0, cuts)
        msdfCutAt(a, ia, b.x0 + b.abx, b.y0 + b.aby, cuts)
        msdfCutAt(b, ib, a.x0, a.y0, cuts)
        msdfCutAt(b, ib, a.x0 + a.abx, a.y0 + a.aby, cuts)
        return
    }

    let ta = (qpx * b.aby - qpy * b.abx) / cross
    let tb = (qpx * a.aby - qpy * a.abx) / cross
    if ta < -MsdfCutMargin or ta > 1 + MsdfCutMargin or tb < -MsdfCutMargin or tb > 1 + MsdfCutMargin do
        return

    // A crossing at the end of one segment is that end, exactly: the piece cut from the other
    // segment must start where the first one does.
    let insideA = ta > MsdfCutMargin and ta < 1 - MsdfCutMargin
    let insideB = tb > MsdfCutMargin and tb < 1 - MsdfCutMargin
    var x       = a.x0 + ta * a.abx
    var y       = a.y0 + ta * a.aby
    if not insideA
    {
        x = ta < 0.5 ? a.x0 : a.x0 + a.abx
        y = ta < 0.5 ? a.y0 : a.y0 + a.aby
    }
    elif not insideB
    {
        x = tb < 0.5 ? b.x0 : b.x0 + b.abx
        y = tb < 0.5 ? b.y0 : b.y0 + b.aby
    }

    if insideA do
        cuts.add(MsdfCut{ia, ta, x, y})
    if insideB do
        cuts.add(MsdfCut{ib, tb, x, y})
}

// Collects the boundary of the fill of `segs` into `edges`.
//
// A distance field is only as good as the edges it measures. An outline whose contours
// overlap, or fold over themselves — as a synthetic bold does wherever it closes a narrow
// notch — has segments running through the inside of its ink. A channel that picks one of
// them takes the inside for the outside and opens a hole beside it. Every segment is therefore
// cut where another one crosses it, and a piece is kept only when the fill lies on exactly one
// side of it, turned so that the fill lies on its right.
//
// A clean outline is its own boundary, and `edges` then receives `segs` unchanged.
func msdfResolveBoundary(segs: const [..] MsdfSeg, contourStarts: const [..] u32, edges: *Array'MsdfSeg)
{
    var sweep: Array'MsdfSweep
    sweep.reserve(segs.count)
    for &s, i in segs do
        sweep.add(MsdfSweep{s.minY, cast(u32) i})
    sweep.sort(func||(l, r) { return l.minY <=> r.minY })

    var cuts: Array'MsdfCut
    for i in sweep.count
    {
        let a = &segs[sweep[i].seg]
        for j in i + 1 until sweep.count
        {
            let b = &segs[sweep[j].seg]
            if b.minY > a.maxY do
                break
            if b.minX > a.maxX or a.minX > b.maxX do
                continue
            msdfCutPair(a, b, sweep[i].seg, sweep[j].seg, &cuts)
        }
    }

    // Nothing crosses, so the fill cannot change sides along a contour, and its longest
    // segment answers for all of it.
    if cuts.isEmpty()
    {
        var side  = 0's32
        var clean = true
        for c in contourStarts.count - 1
        {
            let first = contourStarts[c]
            let end   = contourStarts[c + 1]
            if first == end do
                continue

            var longest = first
            for k in first + 1 until end where segs[k].ab2 > segs[longest].ab2 do
                longest = k

            let s = &segs[longest]
            let contourSide = msdfFillSide(segs, s.x0, s.y0, s.x0 + s.abx, s.y0 + s.aby)
            if contourSide == 0 or (side != 0 and contourSide != side)
            {
                clean = false
                break
            }

            side = contourSide
        }

        if clean
        {
            edges.add(segs)
            return
        }
    }

    cuts.sort(func||(l, r) { return l.seg == r.seg ? l.t <=> r.t : l.seg <=> r.seg })

    var nextCut = 0'u64
    for &s, i in segs
    {
        var x0   = s.x0
        var y0   = s.y0
        var x1, y1: f64
        var more = true
        while more
        {
            more = nextCut < cuts.count and cuts[nextCut].seg == i
            if more
            {
                x1      = cuts[nextCut].x
                y1      = cuts[nextCut].y
                nextCut += 1
            }
            else
            {
                x1 = s.x0 + s.abx
                y1 = s.y0 + s.aby
            }

            if not msdfIsDegenerate(x0, y0, x1, y1)
            {
                let side = msdfFillSide(segs, x0, y0, x1, y1)
                if side > 0 do
                    msdfAddSeg(edges, x0, y0, x1, y1, s.color)
                elif side < 0 do
                    msdfAddSeg(edges, x1, y1, x0, y0, s.color)
            }

            x0 = x1
            y0 = y1
        }
    }
}

// Signed distance from a point to a directed segment (msdfgen LinearEdge::signedDistance).
func msdfSegSignedDistance(s: const *MsdfSeg, px, py: f64)->{ sd: f64, dt: f64, param: f64 }
{
    let aqx = px - s.x0
    let aqy = py - s.y0

    var param: f64 = 0
    if s.ab2 > 0 do
        param = (aqx * s.abx + aqy * s.aby) / s.ab2

    var epx = s.x0
    var epy = s.y0
    if param > 0.5
    {
        epx += s.abx
        epy += s.aby
    }

    let eqx = epx - px
    let eqy = epy - py
    let endpointDist = Math.sqrt(eqx * eqx + eqy * eqy)

    if param > 0 and param < 1
    {
        let ortho = (s.aby * aqx - s.abx * aqy) * s.invLen
        if Math.abs(ortho) < endpointDist do
            return {ortho, 0.0, param}
    }

    let crs = aqx * s.aby - aqy * s.abx
    let sgn = crs > 0 ? 1.0 : -1.0

    var dt: f64 = 0
    if s.len > 0 and endpointDist > 0 do
        dt = Math.abs((s.abx * eqx + s.aby * eqy) / (s.len * endpointDist))

    return {sgn * endpointDist, dt, param}
}

// Extend a segment's true distance to a pseudo-distance past its endpoints, so the
// field stays linear beyond the segment (this is what keeps corners sharp).
func msdfSegPseudoDistance(s: const *MsdfSeg, px, py, param, curSigned: f64)->f64
{
    if s.len <= 0 do
        return curSigned

    let dx = s.abx / s.len
    let dy = s.aby / s.len

    if param < 0
    {
        let aqx = px - s.x0
        let aqy = py - s.y0
        let ts  = aqx * dx + aqy * dy
        if ts < 0
        {
            let pseudo = aqx * dy - aqy * dx
            if Math.abs(pseudo) <= Math.abs(curSigned) do
                return pseudo
        }
    }
    elif param > 1
    {
        let bqx = px - s.x0 - s.abx
        let bqy = py - s.y0 - s.aby
        let ts  = bqx * dx + bqy * dy
        if ts > 0
        {
            let pseudo = bqx * dy - bqy * dx
            if Math.abs(pseudo) <= Math.abs(curSigned) do
                return pseudo
        }
    }

    return curSigned
}

// How much slack the squared rejection reach carries.
//
// The reach is a distance that came out of a square root, and squaring it back lands a
// couple of units in the last place below the exact sum of squares it has to compare equal
// to — which is precisely the case of a segment tying with the current winner and beating it
// on perpendicularity. The slack is far above that rounding and far below anything the
// quantized field can tell apart, so it costs nothing and keeps the search exact.
const MsdfReachSlack: f64 = 1.000001

// The nearest segments found at one sample point.
//
// One search keeps four winners: one per MSDF channel, plus the nearest segment of all,
// which is the unsigned distance the MTSDF alpha channel carries. Folding them together
// means a segment is measured once instead of once per channel it belongs to.
struct MsdfBest
{
    abs:    [3] f64     // Distance to the winner of each channel.
    signed: [3] f64     // Its signed distance.
    dot:    [3] f64     // How perpendicular the contact is; it breaks ties between equal distances.
    param:  [3] f64     // Where the contact falls along the winner.
    idx:    [3] s32     // The winner itself, or -1 when the channel has no candidate yet.

    allAbs: f64     // Distance to the nearest segment of all, whatever channel it carries.
    allIdx: s32     // That segment, or -1.

    // Squared reach a segment has to come within to be worth measuring, indexed by the
    // channel subset it carries. A segment only competes on the channels it belongs to, so
    // the reach is the widest distance standing on those — held per subset rather than
    // recomputed per segment, because the rejection test runs far more often than a win.
    reach2: [8] f64
}

// The winning segments of the previous sample, carried over to the next one.
//
// Neighbouring samples resolve to the same segments nearly always, so measuring the
// previous winners first opens a search with a tight bound instead of infinity — which is
// what makes the rejection below reject anything at all on the first segments it sees.
struct MsdfSeed
{
    channel: [3] s32     // Previous winner per channel, or -1.
    nearest: s32         // Previous nearest segment of all, or -1.
}

impl MsdfSeed
{
    // Forgets the previous winners, at the start of a row.
    mtd clear()
    {
        .channel[0], .channel[1], .channel[2], .nearest = -1
    }
}

impl MsdfBest
{
    mtd start()
    {
        .abs[0], .abs[1], .abs[2], .allAbs = Swag.F64.Max
        .signed[0], .signed[1], .signed[2] = -Swag.F64.Max
        .dot[0], .dot[1], .dot[2] = Swag.F64.Max
        .idx[0], .idx[1], .idx[2], .allIdx = -1
        for i in 8 do
            .reach2[i] = Swag.F64.Max
    }

    // Refreshes the rejection reaches after a win changed one of the distances.
    private mtd updateReach()
    {
        var reach: [8] f64
        reach[0] = .allAbs
        reach[1] = .abs[0]
        reach[2] = .abs[1]
        reach[3] = Math.max(.abs[0], .abs[1])
        reach[4] = .abs[2]
        reach[5] = Math.max(.abs[0], .abs[2])
        reach[6] = Math.max(.abs[1], .abs[2])
        reach[7] = Math.max(reach[3], .abs[2])

        for i in 8 do
            .reach2[i] = reach[i] * reach[i] * MsdfReachSlack
    }

    // Measures one segment and keeps it wherever it wins.
    mtd fold(s: const *MsdfSeg, index: s32, px, py: f64)
    {
        let {sd, dt, param} = msdfSegSignedDistance(s, px, py)
        let a = Math.abs(sd)

        var won = false
        if a < .allAbs or (a == .allAbs and index < .allIdx)
        {
            .allAbs = a
            .allIdx = index
            won     = true
        }

        for ch in 3
        {
            if not (s.color & cast(u8) (1 << ch)) do
                continue

            // An exact tie goes to the more perpendicular contact, which is what keeps a
            // corner from picking whichever of its two edges happens to come first. Two
            // contacts as perpendicular as each other go to the earlier segment, so that
            // the field does not depend on the order the search happened to visit them —
            // the search starts from the previous sample's winners, not from the top.
            if a < .abs[ch] or (a == .abs[ch] and (dt < .dot[ch] or (dt == .dot[ch] and index < .idx[ch])))
            {
                .abs[ch]    = a
                .signed[ch] = sd
                .dot[ch]    = dt
                .param[ch]  = param
                .idx[ch]    = index
                won         = true
            }
        }

        // Most measured segments win nothing; only a win can tighten the reaches.
        if won do
            .updateReach()
    }
}

// Signed pseudo-distance for the three MSDF channels at one sample point, plus the true
// unsigned distance to the nearest segment.
//
// `seed` carries the previous sample's winners in and this sample's winners out.
func msdfChannelDistances(segs: const [..] MsdfSeg, px, py: f64, seed: *MsdfSeed)->{ r, g, b, trueDist: f64 }
{
    var best: MsdfBest
    best.start()

    for k in 4
    {
        let index = k < 3 ? seed.channel[k] : seed.nearest
        if index >= 0 do
            best.fold(&segs[index], index, px, py)
    }

    for &s, i in segs
    {
        // The distance to the segment's bounding box bounds its real distance from below,
        // for a handful of comparisons and no square root. A segment that cannot reach the
        // widest winner cannot win anything. Ties still go through, because it is the exact
        // distance that decides them.
        let bx = Math.max(Math.max(s.minX - px, px - s.maxX), 0.0'f64)
        let by = Math.max(Math.max(s.minY - py, py - s.maxY), 0.0'f64)
        if bx * bx + by * by > best.reach2[s.color] do
            continue

        best.fold(s, cast(s32) i, px, py)
    }

    seed.channel[0] = best.idx[0]
    seed.channel[1] = best.idx[1]
    seed.channel[2] = best.idx[2]
    seed.nearest    = best.allIdx

    var d: [3] f64
    for ch in 3
    {
        d[ch] = best.signed[ch]
        if best.idx[ch] >= 0 do
            d[ch] = msdfSegPseudoDistance(&segs[best.idx[ch]], px, py, best.param[ch], best.signed[ch])
    }

    var result: retval
    result.r        = d[0]
    result.g        = d[1]
    result.b        = d[2]
    result.trueDist = best.allAbs
    return result
}

func msdfMedian(a, b, c: f64)->f64
{
    return Math.max(Math.min(a, b), Math.min(Math.max(a, b), c))
}

struct MsdfRowCtx
{
    segs:           const *Array'MsdfSeg     // The whole outline, which decides inside from outside.
    edges:          const *Array'MsdfSeg     // Its boundary, which distances are measured to.
    channels:       [*] f32
    rowVotes:       [*] s64
    crossings:      [*] MsdfCrossing     // Per-row scratch, one span of 'crossingStride' entries per row.
    crossingStride: u64
    width:          s32
    left:           s32
    top:            s32
}

// Collect the outline crossings of one sample row, sorted by ascending x.
//
// A segment crosses the row when the row falls in its half-open vertical span. A horizontal
// segment spans nothing and therefore never crosses, which is what keeps the winding well
// defined on a sample that lands exactly on a vertex.
func msdfRowCrossings(segs: const [..] MsdfSeg, out: [*] MsdfCrossing, sampleY: f64)->u32
{
    var count = 0'u32
    for &s in segs
    {
        if sampleY < s.minY or sampleY >= s.maxY do
            continue

        var crossing: MsdfCrossing
        crossing.x   = s.x0 + s.abx * (sampleY - s.y0) / s.aby
        crossing.dir = s.aby > 0 ? 1 : -1

        // A row meets a handful of segments, and the sweep below needs them in order.
        var i = count
        while i > 0 and out[i - 1].x > crossing.x
        {
            out[i] = out[i - 1]
            i      -= 1
        }

        out[i] = crossing
        count  += 1
    }

    return count
}

// Fill one output row of the MSDF field and accumulate that row's sign vote.
func msdfProcessRow(c: *MsdfRowCtx, py: u32)
{
    let segsS   = c.segs.toSlice()
    let edgesS  = c.edges.toSlice()
    let sampleY = cast(f64) c.top - (cast(f64) py + 0.5)

    // Inside/outside is a ray cast to the right, so a pixel is inside when the crossings
    // still ahead of it wind to something other than zero. That makes it a property of the
    // row: gathering the crossings once and sweeping them costs one pass over the outline
    // per row instead of one per pixel.
    let crossings  = c.crossings + cast(u64) py * c.crossingStride
    let crossCount = msdfRowCrossings(segsS, crossings, sampleY)

    var winding = 0's32
    for i in crossCount do
        winding += crossings[i].dir

    var seed: MsdfSeed
    seed.clear()

    var passed    = 0'u32
    var localVote = 0's64
    for px in c.width
    {
        let sampleX = cast(f64) c.left + cast(f64) px + 0.5
        while passed < crossCount and crossings[passed].x <= sampleX
        {
            winding -= crossings[passed].dir
            passed  += 1
        }

        let inside = winding != 0

        // The 4th channel carries the true signed distance to the nearest contour (MTSDF).
        // The RGB median keeps sharp corners for the glyph face, but its sub-edge field has
        // corner-ray artifacts; the true SDF is smooth there, so outer effects (glow,
        // outline outer edge, soft shadow) sample it instead.
        let {r, g, b, trueDist} = msdfChannelDistances(edgesS, sampleX, sampleY, &seed)
        let trueSd = inside ? trueDist : -trueDist

        let idx = (cast(u64) py * cast(u64) c.width + cast(u64) px) * 4
        c.channels[idx + 0] = cast(f32) r
        c.channels[idx + 1] = cast(f32) g
        c.channels[idx + 2] = cast(f32) b
        c.channels[idx + 3] = cast(f32) trueSd

        // Sparse sign sampling (every other pixel on both axes) is enough for a robust
        // global majority, and keeps the median off the hot path.
        if (px & 1) == 0 and (py & 1) == 0
        {
            let med = msdfMedian(r, g, b)
            localVote += (med > 0) == inside ? 1 : -1
        }
    }

    c.rowVotes[py] = localVote
}

// Fork the per-row work across the job pool only above this many output samples;
// below it (small punctuation glyphs) the fork/join latency outweighs the win.
// MSDF glyphs always rasterize at the reference em size, so a typical letter sits
// well above this and is parallelised, while commas/periods stay serial.
const MsdfParallelMinSamples: u64 = 2000

// Render the current glyph outline as a 3-channel (RGB) multi-channel SDF.
// The output bitmap has 3 bytes per pixel (pitch = width * 3).
func renderCurrentOutlineMsdf(slot: *GlyphSlot, spread: u32) fail
{
    let faceData = try getSlotImpl(slot)
    let safeSlot = slot
    clearBitmap(safeSlot)

    if safeSlot.format != .Outline do
        try fault(0x13)
    if safeSlot.outline.pointCount <= 0 do
        return

    var safeSpread = spread
    if not safeSpread do
        safeSpread = 1
    safeSpread = Math.min(safeSpread, 64)

    let padding = cast(s32) safeSpread
    let bounds  = computeOutlineBounds(&safeSlot.outline)
    let left    = Math.floorS32(bounds.minX / 64.0) - padding
    let right   = Math.ceilS32(bounds.maxX / 64.0) + padding
    let bottom  = Math.floorS32(bounds.minY / 64.0) - padding
    let top     = Math.ceilS32(bounds.maxY / 64.0) + padding
    let width   = Math.max(0, right - left)
    let rows    = Math.max(0, top - bottom)
    if not width or not rows do
        return

    var segs, edges: Array'MsdfSeg
    buildMsdfSegments(&safeSlot.outline, &segs, &edges)
    if edges.isEmpty() do
        return

    var channels: Array'f32
    channels.resize(cast(u64) width * rows * 4)

    let scale = 127.0 / cast(f64) safeSpread

    // Per-row sign votes, summed afterwards. The vote only decides the single global
    // sign of the field, so it is sampled on a sparse grid (every other pixel) — that
    // is hundreds of authoritative inside/outside tests, plenty for a robust majority.
    var rowVotes: Array's64
    rowVotes.resize(cast(u64) rows)

    // A row can meet each segment at most once, which bounds its crossing list. Every row
    // owns its own span so that the rows below can run in parallel without sharing scratch.
    let crossingStride = segs.count
    var crossings: Array'MsdfCrossing
    crossings.resize(cast(u64) rows * crossingStride)

    let channelsBuffer = channels.storage()
    let rowVotesBuffer = rowVotes.storage()

    var ctx = MsdfRowCtx{
        segs: &segs,
        edges: &edges,
        channels: channelsBuffer,
        rowVotes: rowVotesBuffer,
        crossings: crossings.storage(),
        crossingStride: crossingStride,
        width: width,
        left: left,
        top: top}

    let samples = cast(u64) width * cast(u64) rows
    if rows >= 2 and samples >= MsdfParallelMinSamples and Swag.workerCount() > 1
    {
        parallel for |&ctx| py in rows do
            msdfProcessRow(&ctx, cast(u32) py)
    }
    else
    {
        for py in rows do
            msdfProcessRow(&ctx, cast(u32) py)
    }

    var vote = 0's64
    for i in rows do
        vote += rowVotes[i]

    let flip: f64 = vote < 0 ? -1 : 1

    let count = cast(u64) width * rows
    faceData.bitmapPixels.resize(count * 4)
    var dst = faceData.bitmapPixels.storage()
    for i in count
    {
        let src = i * 4

        // A: true signed distance (already signed by the per-pixel inside test).
        let trueSd = cast(f64) channelsBuffer[src + 3]

        // RGB: multi-channel field, corrected by the global sign vote. A texel whose median
        // still disagrees with the fill lies near a sliver thinner than the boundary cutting
        // can resolve, and its channels would print a speck of the wrong side into the glyph.
        // It takes the true distance on all three channels instead, and becomes a plain
        // single-channel texel: msdfgen's own answer to a texel it cannot trust.
        var rgb: [3] f64
        for c in 3 do
            rgb[c] = flip * cast(f64) channelsBuffer[src + c]
        let median = msdfMedian(rgb[0], rgb[1], rgb[2])
        if (trueSd > 0 and median < 0) or (trueSd < 0 and median > 0) do
            rgb[0], rgb[1], rgb[2] = trueSd

        for c in 3
        {
            let value = 128.0'f64 + rgb[c] * scale
            dst[src + c] = cast(u8) Math.max(0.0'f64, Math.min(255.0'f64, Math.round(value)))
        }

        let av = 128.0'f64 + trueSd * scale
        dst[src + 3] = cast(u8) Math.max(0.0'f64, Math.min(255.0'f64, Math.round(av)))
    }

    safeSlot.setBitmap(rows, width, cast(s32) width * 4, dst, .Rgba, left, top)
}
