using Swag, Core

const OVERSAMPLE = 4'u32

struct Edge
{
    x0:       f64
    y0:       f64
    x1:       f64
    y1:       f64
    minY:     f64
    maxY:     f64
}

func quadraticFlatEnough(p0x, p0y, p1x, p1y, p2x, p2y: f64, tolerance: f64)->bool
{
    let dx = p0x - 2.0 * p1x + p2x
    let dy = p0y - 2.0 * p1y + p2y
    return dx * dx + dy * dy <= tolerance * tolerance
}

func addEdge(edges: *Array'Edge, x0, y0, x1, y1: f64)
{
    if Math.isEqualEpsilon(x0, x1, 0.000001) and Math.isEqualEpsilon(y0, y1, 0.000001) do
        return

    var edge: Edge
    edge.x0   = x0
    edge.y0   = y0
    edge.x1   = x1
    edge.y1   = y1
    edge.minY = Math.min(y0, y1)
    edge.maxY = Math.max(y0, y1)
    edges.add(edge)
}

func flattenQuadratic(edges: *Array'Edge, x0, y0, x1, y1, x2, y2, tolerance: f64, depth: u32 = 0)
{
    if depth >= 12 or quadraticFlatEnough(x0, y0, x1, y1, x2, y2, tolerance)
    {
        addEdge(edges, x0, y0, x2, y2)
        return
    }

    let x01  = (x0 + x1) * 0.5
    let y01  = (y0 + y1) * 0.5
    let x12  = (x1 + x2) * 0.5
    let y12  = (y1 + y2) * 0.5
    let x012 = (x01 + x12) * 0.5
    let y012 = (y01 + y12) * 0.5

    flattenQuadratic(edges, x0, y0, x01, y01, x012, y012, tolerance, depth + 1)
    flattenQuadratic(edges, x012, y012, x12, y12, x2, y2, tolerance, depth + 1)
}

func buildEdges(outline: const *Outline)->Array'Edge
{
    var edges: Array'Edge
    let commands = buildOutlineCommands(outline)

    var currentX = 0.0
    var currentY = 0.0
    var havePos  = false
    let tolerance = 0.20 / OVERSAMPLE

    foreach cmd in commands
    {
        switch cmd.kind
        {
        case MoveTo:
            currentX = cmd.p0.x / 64.0
            currentY = cmd.p0.y / 64.0
            havePos  = true

        case LineTo:
            if havePos
            {
                let x = cmd.p0.x / 64.0
                let y = cmd.p0.y / 64.0
                addEdge(&edges, currentX, currentY, x, y)
                currentX = x
                currentY = y
            }

        case ConicTo:
            if havePos
            {
                let cx = cmd.p0.x / 64.0
                let cy = cmd.p0.y / 64.0
                let x  = cmd.p1.x / 64.0
                let y  = cmd.p1.y / 64.0
                flattenQuadratic(&edges, currentX, currentY, cx, cy, x, y, tolerance)
                currentX = x
                currentY = y
            }
        }
    }

    return edges
}

func isInside(edges: const [..] Edge, x, y: f64)->bool
{
    var winding = 0
    foreach edge in edges
    {
        if y < edge.minY or y >= edge.maxY do
            continue

        let cross = (edge.x1 - edge.x0) * (y - edge.y0) - (x - edge.x0) * (edge.y1 - edge.y0)
        if edge.y0 <= y and edge.y1 > y
        {
            if cross > 0 do
                winding += 1
        }
        elif edge.y1 <= y and edge.y0 > y
        {
            if cross < 0 do
                winding -= 1
        }
    }

    return winding != 0
}

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
