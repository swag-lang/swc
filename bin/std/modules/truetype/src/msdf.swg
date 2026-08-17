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

func msdfAddSeg(segs: *Array'MsdfSeg, x0, y0, x1, y1: f64)
{
    if Math.isEqualEpsilon(x0, x1, 0.000001) and Math.isEqualEpsilon(y0, y1, 0.000001) do
        return

    var seg: MsdfSeg
    seg.x0  = x0
    seg.y0  = y0
    seg.abx = x1 - x0
    seg.aby = y1 - y0
    seg.ab2 = seg.abx * seg.abx + seg.aby * seg.aby
    seg.len = Math.sqrt(seg.ab2)
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
    let ebuf = elements.buffer!
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
func buildMsdfSegments(outline: const *Outline, segs: *Array'MsdfSeg)
{
    let commands  = buildOutlineCommands(outline)
    let tolerance = 0.20 / OVERSAMPLE

    var elements:         Array'MsdfElement
    var contourElemStart: Array'u32

    var curX: f64 = 0
    var curY: f64 = 0

    for cmd in commands
    {
        switch cmd.kind
        {
        case .MoveTo:
            contourElemStart.add(cast(u32) elements.count)
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

    var seed = 0'u64
    for c in contourElemStart.count - 1
    {
        let first = contourElemStart[c]
        let count = contourElemStart[c + 1] - first
        if count == 0 do
            continue
        msdfColorContour(&elements, first, count, &seed)
    }

    if !segs.count do
        return
    let sbuf = segs.buffer!

    // Propagate element colors down to their segments.
    for el in elements
    {
        for i in el.segCount do
            sbuf[el.firstSeg + i].color = el.color
    }

    // Guarantee every channel is carried by at least one segment, otherwise that
    // channel's distance would be undefined and the median would be meaningless.
    var unionColor = 0'u8
    for i in segs.count do
        unionColor |= sbuf[i].color
    let missing = (~unionColor) & MSDF_WHITE
    if missing
    {
        for i in segs.count do
            sbuf[i].color |= missing
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

    let eqx          = epx - px
    let eqy          = epy - py
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
        .dot[0], .dot[1], .dot[2]          = Swag.F64.Max
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
        let a               = Math.abs(sd)

        var won = false
        if a < .allAbs or (a == .allAbs and index < .allIdx)
        {
            .allAbs = a
            .allIdx = index
            won     = true
        }

        for ch in 3
        {
            if !(s.color & cast(u8) (1 << ch)) do
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
    segs:           const *Array'MsdfSeg
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
        let {r, g, b, trueDist} = msdfChannelDistances(segsS, sampleX, sampleY, &seed)
        let trueSd              = inside ? trueDist : -trueDist

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
    let faceData = getSlotImpl(slot)
    let safeSlot = slot!
    clearBitmap(safeSlot)

    if safeSlot.format != .Outline do
        fault(0x13)
    if safeSlot.outline.pointCount <= 0 do
        return

    var safeSpread = spread
    if !safeSpread do
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
    if !width or !rows do
        return

    var segs: Array'MsdfSeg
    buildMsdfSegments(&safeSlot.outline, &segs)
    if segs.isEmpty() do
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

    let channelsBuffer = channels.buffer!
    let rowVotesBuffer = rowVotes.buffer!

    var ctx = MsdfRowCtx{
        segs: &segs,
        channels: channelsBuffer,
        rowVotes: rowVotesBuffer,
        crossings: crossings.buffer!,
        crossingStride: crossingStride,
        width: width,
        left: left,
        top: top}

    let samples = cast(u64) width * cast(u64) rows
    if rows >= 2 and samples >= MsdfParallelMinSamples and !Jobs.isSynchronous()
    {
        Jobs.parallelFor(cast(u32) rows, &ctx) #code(py, data)
        {
            let safeData = data!
            msdfProcessRow(cast(*MsdfRowCtx) safeData, py)
        }
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
    var dst = faceData.bitmapPixels.buffer!
    for i in count
    {
        let src = i * 4

        // RGB: multi-channel field, corrected by the global sign vote.
        for c in 3
        {
            let value = 128.0'f64 + flip * cast(f64) channelsBuffer[src + c] * scale
            dst[src + c] = cast(u8) Math.max(0.0'f64, Math.min(255.0'f64, Math.round(value)))
        }

        // A: true signed distance (already signed by the per-pixel inside test).
        let av = 128.0'f64 + cast(f64) channelsBuffer[src + 3] * scale
        dst[src + 3] = cast(u8) Math.max(0.0'f64, Math.min(255.0'f64, Math.round(av)))
    }

    safeSlot.setBitmap(rows, width, cast(s32) width * 4, dst, .Rgba, left, top)
}
