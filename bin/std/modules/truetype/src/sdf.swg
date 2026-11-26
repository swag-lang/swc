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

// Each crossing contributes winding to the sample centers strictly to its left.
private func sdfWindingChanges(edges: const [..] Edge, changes: [..] s32, left, y: f64)
{
    let width = cast(s32, changes.count)
    Memory.clear(changes.buffer, changes.count * #sizeof(s32))
    for edge in edges
    {
        if y < edge.minY or y >= edge.maxY do
            continue

        let dy   = edge.y1 - edge.y0
        let x    = edge.x0 + (edge.x1 - edge.x0) * (y - edge.y0) / dy
        let stop = cast(s32, Math.ceil(x - left - 0.5))
        if stop <= 0 do
            continue

        let winding = dy > 0.0 ? 1 : -1
        changes[0] += winding
        if stop < width do
            changes[stop] -= winding
    }
}

func renderCurrentOutlineSdf(slot: *GlyphSlot, spread: u32) fail
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

    let padding = cast(s32, safeSpread)
    let bounds  = computeOutlineBounds(&safeSlot.outline)
    let left    = Math.floorS32(bounds.minX / 64.0) - padding
    let right   = Math.ceilS32(bounds.maxX / 64.0) + padding
    let bottom  = Math.floorS32(bounds.minY / 64.0) - padding
    let top     = Math.ceilS32(bounds.maxY / 64.0) + padding
    let width   = Math.max(0, right - left)
    let rows    = Math.max(0, top - bottom)
    if not width or not rows do
        return

    let edges = buildEdges(&safeSlot.outline)
    if not edges.count do
        return

    faceData.bitmapPixels.resize(cast(u64, width) * rows)
    let bitmapBuffer = faceData.bitmapPixels.storage()
    var dst          = bitmapBuffer
    let scale        = 127.0 / cast(f64, safeSpread)

    // Beyond this vertical distance both signs saturate after conversion
    // to bytes. All edges that cross the row remain available for winding.
    let distanceLimit = cast(f64, safeSpread) + 1.0
    var nearby: Array'Edge
    nearby.reserve(edges.count)
    var changes: Array's32
    changes.resize(cast(u64, width))
    let windingChanges = changes.toSlice()

    for py in rows
    {
        let sampleY = top - (cast(f64, py) + 0.5)
        let lowY    = sampleY - distanceLimit
        let highY   = sampleY + distanceLimit
        nearby.clear()
        for edge in edges where edge.maxY >= lowY and edge.minY <= highY do
            nearby.add(edge)
        let rowEdges = nearby.toSlice()
        sdfWindingChanges(rowEdges, windingChanges, left, sampleY)

        var winding = 0
        var px      = 0
        while px + 2 <= width
        {
            let sampleX   = left + cast(f64, px) + 0.5
            let samples   = cast(Math.Simd.F64x2, [sampleX, sampleX + 1.0])
            let distances = closestEdgeDistances(rowEdges, samples, sampleY)
            for lane in 2
            {
                winding += windingChanges[px + lane]
                let signedDistance = winding ? distances[lane] : -distances[lane]
                let value = Math.max(0.0, Math.min(255.0, 128.0 + signedDistance * scale))
                dst[] = cast(u8, Math.round(value))
                dst   += 1
            }

            px += 2
        }

        while px < width
        {
            let sampleX  = left + cast(f64, px) + 0.5
            let distance = closestEdgeDistance(rowEdges, sampleX, sampleY)
            winding += windingChanges[px]
            let signedDistance = winding ? distance : -distance
            let value = Math.max(0.0, Math.min(255.0, 128.0 + signedDistance * scale))
            dst[]   = cast(u8, Math.round(value))
            dst, px += 1
        }
    }

    safeSlot.setBitmap(rows, width, cast(s32, width), bitmapBuffer, .Gray, left, top)
}
