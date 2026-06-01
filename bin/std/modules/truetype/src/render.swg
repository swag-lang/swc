using Swag, Core

// Accumulate the exact coverage contribution of one edge piece, already clipped to
// a single scanline band, into the per-column 'area' and 'cover' buffers.
//   - cover[x] : signed vertical extent of the edge inside column x (0..1 of the band)
//   - area[x]  : that extent weighted by the edge's average x position inside the cell
// The piece runs from (xa, ya) to (xb, yb) in pixel space with ya < yb; 's' is the
// winding sign (+1 for an upward edge, -1 for a downward one). Final per-pixel
// coverage is reconstructed as: running_cover + cover[x] - area[x].
func accumulateSpan(area, cover: [*] f64, width: s32, xa, ya, xb, yb, s: f64)
{
    let dyTotal = yb - ya
    if dyTotal <= 0.0 do
        return

    // Vertical sub-segment: a single column.
    if Math.abs(xb - xa) < 1e-9
    {
        var cx = Math.floorS32(xa)
        if cx < 0 do
            cx = 0
        if cx > width - 1 do
            cx = width - 1
        var xf = xa - cast(f64) cx
        if xf < 0.0 do
            xf = 0.0
        elif xf > 1.0 do
            xf = 1.0
        cover[cx] += s * dyTotal
        area[cx]  += s * dyTotal * xf
        return
    }

    let xL = Math.min(xa, xb)
    let xR = Math.max(xa, xb)
    var cxStart = Math.floorS32(xL)
    var cxEnd   = Math.floorS32(xR)
    if cxEnd < 0 or cxStart > width - 1 do
        return
    if cxStart < 0 do
        cxStart = 0
    if cxEnd > width - 1 do
        cxEnd = width - 1

    // x varies linearly with y along the segment, so y at a given x is exact.
    let invDx = 1.0 / (xb - xa)

    for cx in cxStart until cxEnd + 1
    {
        let cxf = cast(f64) cx
        let sx0 = Math.max(xL, cxf)
        let sx1 = Math.min(xR, cxf + 1.0)
        if sx1 <= sx0 do
            continue

        let ys0 = ya + (yb - ya) * (sx0 - xa) * invDx
        let ys1 = ya + (yb - ya) * (sx1 - xa) * invDx
        let dh  = Math.abs(ys1 - ys0)
        if dh <= 0.0 do
            continue

        var xf = (sx0 + sx1) * 0.5 - cxf
        if xf < 0.0 do
            xf = 0.0
        elif xf > 1.0 do
            xf = 1.0

        cover[cx] += s * dh
        area[cx]  += s * dh * xf
    }
}

func renderCurrentOutline(slot: *GlyphSlot) throw
{
    let faceData = getSlotImpl(slot)
    clearBitmap(slot)

    if slot.format != .Outline do
        fail(0x13)

    if slot.outline.pointCount <= 0 do
        return

    let bounds = computeOutlineBounds(&slot.outline)
    let left   = Math.floorS32(bounds.minX / 64.0)
    let right  = Math.ceilS32(bounds.maxX / 64.0)
    let bottom = Math.floorS32(bounds.minY / 64.0)
    let top    = Math.ceilS32(bounds.maxY / 64.0)
    let width  = Math.max(0, right - left)
    let rows   = Math.max(0, top - bottom)
    if !width or !rows do
        return

    let edges = buildEdges(&slot.outline)
    if !edges.count do
        return

    faceData.bitmapPixels.resize(cast(u64) width * rows)
    var dst = faceData.bitmapPixels.buffer

    // Per-row signed-area accumulation buffers (analytic anti-aliasing).
    var area:  Array'f64
    var cover: Array'f64
    area.resize(cast(u64) width)
    cover.resize(cast(u64) width)

    let leftF = cast(f64) left
    let topF  = cast(f64) top

    for py in rows
    {
        Memory.clear(area.buffer, area.count * #sizeof(f64))
        Memory.clear(cover.buffer, cover.count * #sizeof(f64))

        // Glyph-space y band for this row (y points up; row 0 is the top).
        let bandHi = topF - cast(f64) py
        let bandLo = bandHi - 1.0

        foreach edge in edges
        {
            // Horizontal edges carry no winding; skip non-overlapping ones.
            if edge.y0 == edge.y1 do
                continue
            if edge.maxY <= bandLo or edge.minY >= bandHi do
                continue

            let s   = edge.y1 > edge.y0 ? 1.0 : -1.0
            let elo = Math.max(edge.minY, bandLo)
            let ehi = Math.min(edge.maxY, bandHi)
            if ehi <= elo do
                continue

            let inv   = 1.0 / (edge.y1 - edge.y0)
            let xAtLo = edge.x0 + (edge.x1 - edge.x0) * (elo - edge.y0) * inv
            let xAtHi = edge.x0 + (edge.x1 - edge.x0) * (ehi - edge.y0) * inv

            accumulateSpan(area.buffer, cover.buffer, width, xAtLo - leftF, elo, xAtHi - leftF, ehi, s)
        }

        var running: f64 = 0.0
        for px in width
        {
            let val = running + cover.buffer[px] - area.buffer[px]
            running += cover.buffer[px]

            var c = Math.abs(val)
            if c > 1.0 do
                c = 1.0
            dref dst = cast(u8) (c * 255.0 + 0.5)
            dst += 1
        }
    }

    slot.bitmap.rows         = rows
    slot.bitmap.width        = width
    slot.bitmap.pitch        = cast(s32) width
    slot.bitmap.buffer       = faceData.bitmapPixels.buffer
    slot.bitmap.pixelMode   = .Gray
    slot.bitmap.grayCount    = 256
    slot.bitmapLeft         = left
    slot.bitmapTop          = top
}

func edgeDistanceSquared(edge: Edge, x, y: f64)->f64
{
    let vx = edge.x1 - edge.x0
    let vy = edge.y1 - edge.y0
    let lenSquared = vx * vx + vy * vy
    if lenSquared <= 0.0000001
    {
        let dx = x - edge.x0
        let dy = y - edge.y0
        return dx * dx + dy * dy
    }

    let t  = Math.max(0.0, Math.min(1.0, ((x - edge.x0) * vx + (y - edge.y0) * vy) / lenSquared))
    let px = edge.x0 + vx * t
    let py = edge.y0 + vy * t
    let dx = x - px
    let dy = y - py
    return dx * dx + dy * dy
}

func closestEdgeDistance(edges: const [..] Edge, x, y: f64)->f64
{
    var distSquared = Swag.F64.Max
    foreach edge in edges do
        distSquared = Math.min(distSquared, edgeDistanceSquared(edge, x, y))

    return Math.sqrt(distSquared)
}

func renderCurrentOutlineSdf(slot: *GlyphSlot, spread: u32) throw
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

    let edges = buildEdges(&slot.outline)
    if !edges.count do
        return

    faceData.bitmapPixels.resize(cast(u64) width * rows)
    var dst = faceData.bitmapPixels.buffer
    let scale = 127.0 / cast(f64) safeSpread

    for py in rows
    {
        for px in width
        {
            let sampleX = left + cast(f64) px + 0.5
            let sampleY = top - (cast(f64) py + 0.5)
            let distance = closestEdgeDistance(edges.toSlice(), sampleX, sampleY)
            let signedDistance = isInside(edges.toSlice(), sampleX, sampleY) ? distance : -distance
            let value = Math.max(0.0, Math.min(255.0, 128.0 + signedDistance * scale))
            dref dst = cast(u8) Math.round(value)
            dst += 1
        }
    }

    slot.bitmap.rows         = rows
    slot.bitmap.width        = width
    slot.bitmap.pitch        = cast(s32) width
    slot.bitmap.buffer       = faceData.bitmapPixels.buffer
    slot.bitmap.pixelMode   = .Gray
    slot.bitmap.grayCount    = 256
    slot.bitmapLeft         = left
    slot.bitmapTop          = top
}

func contourSignedArea(points: [..] Vector)->f64
{
    if @countof(points) < 3 do
        return 0

    var area: f64 = 0.0
    for @countof(points)
    {
        let p0 = points[@index]
        let p1 = points[(@index + 1) % @countof(points)]
        area += cast(f64) p0.x * cast(f64) p1.y - cast(f64) p1.x * cast(f64) p0.y
    }

    return area * 0.5
}

func applyEmboldenToContour(points: [..] Vector, strength: f64)
{
    if @countof(points) < 2 or Math.isZeroEpsilon(cast(f32) strength) do
        return

    var source: Array'Vector
    source.add(points)
    let ccw = contourSignedArea(source.toSlice()) >= 0

    for @countof(points)
    {
        let prev = source[(source.count + @index - 1) % source.count]
        let cur  = source[@index]
        let next = source[(@index + 1) % source.count]

        var e0x = cast(f64) (cur.x - prev.x)
        var e0y = cast(f64) (cur.y - prev.y)
        var e1x = cast(f64) (next.x - cur.x)
        var e1y = cast(f64) (next.y - cur.y)

        let len0 = Math.sqrt(e0x * e0x + e0y * e0y)
        let len1 = Math.sqrt(e1x * e1x + e1y * e1y)
        if Math.isZeroEpsilon(cast(f32) len0)
        {
            e0x = e1x
            e0y = e1y
        }
        if Math.isZeroEpsilon(cast(f32) len1)
        {
            e1x = e0x
            e1y = e0y
        }

        let il0 = Math.isZeroEpsilon(cast(f32) len0) ? 0.0 : 1.0 / Math.max(len0, 0.0001)
        let il1 = Math.isZeroEpsilon(cast(f32) len1) ? 0.0 : 1.0 / Math.max(len1, 0.0001)
        let n0x = ccw ? e0y * il0 : -e0y * il0
        let n0y = ccw ? -e0x * il0 : e0x * il0
        let n1x = ccw ? e1y * il1 : -e1y * il1
        let n1y = ccw ? -e1x * il1 : e1x * il1

        var dirx = n0x + n1x
        var diry = n0y + n1y
        let dirLen = Math.sqrt(dirx * dirx + diry * diry)
        if Math.isZeroEpsilon(cast(f32) dirLen)
        {
            dirx = n1x
            diry = n1y
        }
        else
        {
            dirx /= dirLen
            diry /= dirLen
        }

        let dot    = Math.abs(dirx * n1x + diry * n1y)
        let miter  = dot > 0.25 ? Math.min(4.0, 1.0 / dot) : 1.0
        points[@index].x = cast(s32) Math.round(cur.x + dirx * strength * miter)
        points[@index].y = cast(s32) Math.round(cur.y + diry * strength * miter)
    }
}
