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

struct MsdfSeg
{
    x0, y0:    f64
    x1, y1:    f64
    color:     u8
}

struct MsdfElement
{
    firstSeg:    u32       // first segment index in the flat segment list
    segCount:    u32
    sdx0, sdy0:  f64       // normalized direction at the element start
    edx1, edy1:  f64       // normalized direction at the element end
    color:       u8
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
    seg.x0 = x0
    seg.y0 = y0
    seg.x1 = x1
    seg.y1 = y1
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

// msdfgen's "switchColor": deterministically pick the next edge color.
func msdfSwitchColor(color: *u8, seed: *u64, banned: u8 = MSDF_BLACK)
{
    let combined = dref color & banned
    if combined == MSDF_RED or combined == MSDF_GREEN or combined == MSDF_BLUE
    {
        dref color = combined ^ MSDF_WHITE
        return
    }

    if dref color == MSDF_BLACK or dref color == MSDF_WHITE
    {
        let start: [3] u8 = [MSDF_CYAN, MSDF_MAGENTA, MSDF_YELLOW]
        dref color = start[dref seed % 3]
        dref seed /= 3
        return
    }

    let shifted = cast(u32) (dref color) << (1 + (dref seed & 1))
    dref color = cast(u8) ((shifted | (shifted >> 3)) & MSDF_WHITE)
    dref seed >>= 1
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
    var pdx = elements.buffer[first + count - 1].edx1
    var pdy = elements.buffer[first + count - 1].edy1
    for i in count
    {
        let e = &elements.buffer[first + i]
        if msdfIsCorner(pdx, pdy, e.sdx0, e.sdy0, crossThreshold) do
            corners.add(i)
        pdx = e.edx1
        pdy = e.edy1
    }

    // Smooth contour (no corners): a single channel set is enough, the median
    // then matches a plain single-channel SDF, which is correct for such shapes.
    if corners.count == 0
    {
        for i in count do
            elements.buffer[first + i].color = MSDF_WHITE
        return
    }

    // A single corner cannot alternate back to a distinct color, so fall back to
    // one switched color for the whole contour (these "teardrop" shapes are rare).
    if corners.count == 1
    {
        var color = MSDF_WHITE
        msdfSwitchColor(&color, seed)
        for i in count do
            elements.buffer[first + i].color = color
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
        elements.buffer[first + index].color = color
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

    foreach cmd in commands
    {
        switch cmd.kind
        {
        case MoveTo:
            contourElemStart.add(cast(u32) elements.count)
            curX = cmd.p0.x / 64.0'f64
            curY = cmd.p0.y / 64.0'f64

        case LineTo:
            let x = cmd.p0.x / 64.0'f64
            let y = cmd.p0.y / 64.0'f64

            var el: MsdfElement
            el.firstSeg = cast(u32) segs.count
            msdfAddSeg(segs, curX, curY, x, y)
            el.segCount = cast(u32) segs.count - el.firstSeg

            let (dx, dy) = msdfNormDir(x - curX, y - curY)
            el.sdx0, el.edx1 = dx
            el.sdy0, el.edy1 = dy
            elements.add(el)

            curX = x
            curY = y

        case ConicTo:
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

            let (sdx, sdy) = msdfNormDir(s0x, s0y)
            let (edx, edy) = msdfNormDir(e1x, e1y)
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

    // Propagate element colors down to their segments.
    foreach el in elements
    {
        for i in el.segCount do
            segs.buffer[el.firstSeg + i].color = el.color
    }

    // Guarantee every channel is carried by at least one segment, otherwise that
    // channel's distance would be undefined and the median would be meaningless.
    var unionColor = 0'u8
    for i in segs.count do
        unionColor |= segs.buffer[i].color
    let missing = (~unionColor) & MSDF_WHITE
    if missing
    {
        for i in segs.count do
            segs.buffer[i].color |= missing
    }
}

// Signed distance from a point to a directed segment (msdfgen LinearEdge::signedDistance).
func msdfSegSignedDistance(s: const *MsdfSeg, px, py: f64)->{ sd: f64, dt: f64, param: f64 }
{
    let abx = s.x1 - s.x0
    let aby = s.y1 - s.y0
    let aqx = px - s.x0
    let aqy = py - s.y0
    let ab2 = abx * abx + aby * aby

    var param: f64 = 0
    if ab2 > 0 do
        param = (aqx * abx + aqy * aby) / ab2

    var epx = s.x0
    var epy = s.y0
    if param > 0.5
    {
        epx = s.x1
        epy = s.y1
    }

    let eqx = epx - px
    let eqy = epy - py
    let endpointDist = Math.sqrt(eqx * eqx + eqy * eqy)

    if param > 0 and param < 1
    {
        let invLen = ab2 > 0 ? 1.0 / Math.sqrt(ab2) : 0.0
        let ortho  = (aby * aqx - abx * aqy) * invLen
        if Math.abs(ortho) < endpointDist do
            return { ortho, 0.0, param }
    }

    let crs = aqx * aby - aqy * abx
    let sgn = crs > 0 ? 1.0 : -1.0

    var dt: f64 = 0
    let ablen   = Math.sqrt(ab2)
    if ablen > 0 and endpointDist > 0 do
        dt = Math.abs((abx * eqx + aby * eqy) / (ablen * endpointDist))

    return { sgn * endpointDist, dt, param }
}

// Extend a segment's true distance to a pseudo-distance past its endpoints, so the
// field stays linear beyond the segment (this is what keeps corners sharp).
func msdfSegPseudoDistance(s: const *MsdfSeg, px, py, param, curSigned: f64)->f64
{
    let abx   = s.x1 - s.x0
    let aby   = s.y1 - s.y0
    let ablen = Math.sqrt(abx * abx + aby * aby)
    if ablen <= 0 do
        return curSigned

    let dx = abx / ablen
    let dy = aby / ablen

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
        let bqx = px - s.x1
        let bqy = py - s.y1
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

func msdfChannelDistance(segs: const [..] MsdfSeg, bit: u8, px, py: f64)->f64
{
    var bestAbs    = Swag.F64.Max
    var bestSigned = -Swag.F64.Max
    var bestDot    = Swag.F64.Max
    var bestIdx    = -1
    var bestParam: f64 = 0

    foreach &s, i in segs
    {
        if !(s.color & bit) do
            continue

        let (sd, dt, param) = msdfSegSignedDistance(s, px, py)
        let a = Math.abs(sd)
        if a < bestAbs or (a == bestAbs and dt < bestDot)
        {
            bestAbs    = a
            bestSigned = sd
            bestDot    = dt
            bestIdx    = cast(s32) i
            bestParam  = param
        }
    }

    if bestIdx < 0 do
        return bestSigned
    return msdfSegPseudoDistance(&segs[bestIdx], px, py, bestParam, bestSigned)
}

func msdfMedian(a, b, c: f64)->f64
{
    return Math.max(Math.min(a, b), Math.min(Math.max(a, b), c))
}

// Render the current glyph outline as a 3-channel (RGB) multi-channel SDF.
// The output bitmap has 3 bytes per pixel (pitch = width * 3).
func renderCurrentOutlineMsdf(slot: *GlyphSlot, spread: u32) throw
{
    let faceData = getSlotImpl(slot)
    clearBitmap(slot)

    if slot.format != .Outline do
        fail(0x13)
    if slot.outline.pointCount <= 0 do
        return

    var safeSpread = spread
    if !safeSpread do
        safeSpread = 1
    safeSpread = Math.min(safeSpread, 64)

    let padding = cast(s32) safeSpread
    let bounds  = computeOutlineBounds(&slot.outline)
    let left    = Math.floorS32(bounds.minX / 64.0) - padding
    let right   = Math.ceilS32(bounds.maxX / 64.0) + padding
    let bottom  = Math.floorS32(bounds.minY / 64.0) - padding
    let top     = Math.ceilS32(bounds.maxY / 64.0) + padding
    let width   = Math.max(0, right - left)
    let rows    = Math.max(0, top - bottom)
    if !width or !rows do
        return

    var segs: Array'MsdfSeg
    buildMsdfSegments(&slot.outline, &segs)
    if segs.count == 0 do
        return

    // Authoritative inside/outside test, used only to pick the global field sign.
    let edges = buildEdges(&slot.outline)

    var channels: Array'f32
    channels.resize(cast(u64) width * rows * 3)

    let scale = 127.0 / cast(f64) safeSpread
    var vote  = 0's64

    for py in rows
    {
        for px in width
        {
            let sampleX = left + cast(f64) px + 0.5
            let sampleY = top - (cast(f64) py + 0.5)

            let r = msdfChannelDistance(segs.toSlice(), MSDF_RED, sampleX, sampleY)
            let g = msdfChannelDistance(segs.toSlice(), MSDF_GREEN, sampleX, sampleY)
            let b = msdfChannelDistance(segs.toSlice(), MSDF_BLUE, sampleX, sampleY)

            let idx = (cast(u64) py * cast(u64) width + cast(u64) px) * 3
            channels[idx + 0] = cast(f32) r
            channels[idx + 1] = cast(f32) g
            channels[idx + 2] = cast(f32) b

            let med    = msdfMedian(r, g, b)
            let inside = isInside(edges.toSlice(), sampleX, sampleY)
            if (med > 0) == inside do
                vote += 1
            else do
                vote -= 1
        }
    }

    let flip: f64 = vote < 0 ? -1 : 1

    faceData.bitmapPixels.resize(cast(u64) width * rows * 3)
    var dst = faceData.bitmapPixels.buffer
    for i in cast(u64) width * rows * 3
    {
        let value = 128.0'f64 + flip * cast(f64) channels[i] * scale
        dst[i] = cast(u8) Math.max(0.0'f64, Math.min(255.0'f64, Math.round(value)))
    }

    slot.bitmap.rows       = rows
    slot.bitmap.width       = width
    slot.bitmap.pitch       = cast(s32) width * 3
    slot.bitmap.buffer      = faceData.bitmapPixels.buffer
    slot.bitmap.pixelMode   = .Lcd
    slot.bitmap.grayCount   = 256
    slot.bitmapLeft         = left
    slot.bitmapTop          = top
}
