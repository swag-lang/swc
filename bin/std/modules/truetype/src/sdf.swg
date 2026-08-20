using Swag, Core

func edgeDistanceSquared(edge: Edge, x, y: f64)->f64
{
    let vx         = edge.x1 - edge.x0
    let vy         = edge.y1 - edge.y0
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
    for edge in edges do
        distSquared = Math.min(distSquared, edgeDistanceSquared(edge, x, y))

    return Math.sqrt(distSquared)
}

func closestEdgeDistances(edges: const [..] Edge, x: Math.Simd.F64x2, y: f64)->Math.Simd.F64x2
{
    var distSquared = Math.Simd.splat(Swag.F64.Max)
    for edge in edges
    {
        let vx         = edge.x1 - edge.x0
        let vy         = edge.y1 - edge.y0
        let lenSquared = vx * vx + vy * vy
        var distance: Math.Simd.F64x2
        if lenSquared <= 0.0000001
        {
            let dx = x - edge.x0
            let dy = y - edge.y0
            distance = dx * dx + dy * dy
        }
        else
        {
            let t  = Math.max(Math.Simd.splat(0.0'f64), Math.min(Math.Simd.splat(1.0'f64), ((x - edge.x0) * vx + (y - edge.y0) * vy) / lenSquared))
            let dx = x - (edge.x0 + vx * t)
            let dy = y - (edge.y0 + vy * t)
            distance = dx * dx + dy * dy
        }

        distSquared = Math.min(distSquared, distance)
    }

    return Math.sqrt(distSquared)
}

func insideMask(edges: const [..] Edge, x: Math.Simd.F64x2, y: f64)->u32
{
    var winding0 = 0
    var winding1 = 0
    for edge in edges
    {
        if y < edge.minY or y >= edge.maxY do
            continue

        let cross = (edge.x1 - edge.x0) * (y - edge.y0) - (x - edge.x0) * (edge.y1 - edge.y0)
        var mask  = 0'u32
        if edge.y0 <= y and edge.y1 > y
        {
            mask     = Math.Simd.bitmask(cross > Math.Simd.splat(0.0'f64))
            winding0 += mask & 1
            winding1 += (mask >> 1) & 1
        }
        elif edge.y1 <= y and edge.y0 > y
        {
            mask     = Math.Simd.bitmask(cross < Math.Simd.splat(0.0'f64))
            winding0 -= mask & 1
            winding1 -= (mask >> 1) & 1
        }
    }

    var result = 0'u32
    if winding0 do
        result |= 1
    if winding1 do
        result |= 2
    return result
}

func renderCurrentOutlineSdf(slot: *GlyphSlot, spread: u32) fail
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

    let edges = buildEdges(&safeSlot.outline)
    if !edges.count do
        return

    faceData.bitmapPixels.resize(cast(u64) width * rows)
    let bitmapBuffer = faceData.bitmapPixels.buffer!
    var dst          = bitmapBuffer
    let scale        = 127.0 / cast(f64) safeSpread

    for py in rows
    {
        let sampleY = top - (cast(f64) py + 0.5)
        var px      = 0
        while px + 2 <= width
        {
            let sampleX   = left + cast(f64) px + 0.5
            let samples   = cast(Math.Simd.F64x2) [sampleX, sampleX + 1.0]
            let distances = closestEdgeDistances(edges.toSlice(), samples, sampleY)
            let inside    = insideMask(edges.toSlice(), samples, sampleY)
            for lane in 2
            {
                let signedDistance = inside & (1'u32 << lane) ? distances[lane] : -distances[lane]
                let value          = Math.max(0.0, Math.min(255.0, 128.0 + signedDistance * scale))
                dst[] = cast(u8) Math.round(value)
                dst   += 1
            }

            px += 2
        }

        while px < width
        {
            let sampleX        = left + cast(f64) px + 0.5
            let distance       = closestEdgeDistance(edges.toSlice(), sampleX, sampleY)
            let signedDistance = isInside(edges.toSlice(), sampleX, sampleY) ? distance : -distance
            let value          = Math.max(0.0, Math.min(255.0, 128.0 + signedDistance * scale))
            dst[]   = cast(u8) Math.round(value)
            dst, px += 1
        }
    }

    safeSlot.setBitmap(rows, width, cast(s32) width, bitmapBuffer, .Gray, left, top)
}
