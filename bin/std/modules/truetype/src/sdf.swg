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
    for edge in edges
    {
        distSquared = Math.min(distSquared, edgeDistanceSquared(edge, x, y))
    }

    return Math.sqrt(distSquared)
}

private struct SdfRowEdge
{
    x0:         f64
    y0:         f64
    vx:         f64
    vy:         f64
    lenSquared: f64
    dotY:       f64
}

private func closestRowDistances(edges: const [..] SdfRowEdge, x: Math.Simd.F64x2, y: f64)->Math.Simd.F64x2
{
    var distSquared = Math.Simd.splat(Swag.F64.Max)
    for edge in edges
    {
        var distance: Math.Simd.F64x2
        if edge.lenSquared <= 0.0000001
        {
            let dx = x - edge.x0
            let dy = y - edge.y0
            distance = dx * dx + dy * dy
        }
        else
        {
            let t  = Math.max(Math.Simd.splat(0.0_f64), Math.min(Math.Simd.splat(1.0_f64), ((x - edge.x0) * edge.vx + edge.dotY) / edge.lenSquared))
            let dx = x - (edge.x0 + edge.vx * t)
            let dy = y - (edge.y0 + edge.vy * t)
            distance = dx * dx + dy * dy
        }

        distSquared = Math.min(distSquared, distance)
    }

    return Math.sqrt(distSquared)
}

// Collects distance geometry and winding crossings for one row. Each crossing
// contributes winding to the sample centers strictly to its left.
private func buildSdfRow(edges: const [..] Edge, geometry: *Array!{SdfRowEdge}, changes: [..] s32, left, y, limit: f64)
{
    let width = cast(s32, changes.count)
    let lowY  = y - limit
    let highY = y + limit
    geometry.clear()
    Memory.clear(changes.buffer, changes.count * #sizeof(s32))
    for edge in edges where edge.maxY >= lowY and edge.minY <= highY
    {
        let vx = edge.x1 - edge.x0
        let vy = edge.y1 - edge.y0
        let dy = y - edge.y0
        geometry.add({edge.x0, edge.y0, vx, vy, vx * vx + vy * vy, dy * vy})

        if y < edge.minY or y >= edge.maxY
        {
            continue
        }

        let x    = edge.x0 + vx * dy / vy
        let stop = cast(s32, Math.ceil(x - left - 0.5))
        if stop <= 0
        {
            continue
        }

        let winding = vy > 0.0 ? 1 : -1
        changes[0] += winding
        if stop < width
        {
            changes[stop] -= winding
        }
    }
}

func renderCurrentOutlineSdf(slot: *GlyphSlot, spread: u32) fail
{
    let faceData = try getSlotImpl(slot)
    let safeSlot = slot
    clearBitmap(safeSlot)

    if safeSlot.format != .Outline
    {
        try fault(0x13)
    }

    if safeSlot.outline.pointCount <= 0
    {
        return
    }

    var safeSpread = spread
    if not safeSpread
    {
        safeSpread = 1
    }

    safeSpread = Math.min(safeSpread, 64)

    let padding = cast(s32, safeSpread)
    let bounds  = computeOutlineBounds(&safeSlot.outline)
    let left    = Math.floorS32(bounds.minX / 64.0) - padding
    let right   = Math.ceilS32(bounds.maxX / 64.0) + padding
    let bottom  = Math.floorS32(bounds.minY / 64.0) - padding
    let top     = Math.ceilS32(bounds.maxY / 64.0) + padding
    let width   = Math.max(0, right - left)
    let rows    = Math.max(0, top - bottom)
    if not width or not rows
    {
        return
    }

    let edges = buildEdges(&safeSlot.outline)
    if not edges.count
    {
        return
    }

    faceData.bitmapPixels.resize(cast(u64, width) * rows)
    let bitmapBuffer = faceData.bitmapPixels.storage()
    var dst          = bitmapBuffer
    let scale        = 127.0 / cast(f64, safeSpread)

    // Beyond this vertical distance both signs saturate after conversion
    // to bytes. All edges that cross the row remain available for winding.
    let distanceLimit = cast(f64, safeSpread) + 1.0
    var geometry: Array!{SdfRowEdge}
    geometry.reserve(edges.count)
    var changes: Array!{s32}
    changes.resize(cast(u64, width))
    let windingChanges = changes.toSlice()
    let tileWidth      = width >= padding * 2 + 48 ? 16 : width
    var tile: Array!{SdfRowEdge}
    if tileWidth < width
    {
        tile.reserve(edges.count)
    }

    for py in rows
    {
        let sampleY = top - (cast(f64, py) + 0.5)
        buildSdfRow(edges.toSlice(), &geometry, windingChanges, left, sampleY, distanceLimit)
        let rowEdges = geometry.toSlice()

        var winding = 0
        var start   = 0
        while start < width
        {
            let stop       = Math.min(start + tileWidth, width)
            var candidates = rowEdges
            if tileWidth < width
            {
                // Both lanes in the tile saturate for edges beyond its reach.
                let minX = left + cast(f64, start) + 0.5 - distanceLimit
                let maxX = left + cast(f64, stop) - 0.5 + distanceLimit
                tile.clear()
                for edge in rowEdges
                {
                    let x1 = edge.x0 + edge.vx
                    if Math.max(edge.x0, x1) >= minX and Math.min(edge.x0, x1) <= maxX
                    {
                        tile.add(edge)
                    }
                }

                candidates = tile.toSlice()
            }

            var px = start
            while px + 2 <= stop
            {
                let sampleX   = left + cast(f64, px) + 0.5
                let samples   = cast(Math.Simd.F64x2, [sampleX, sampleX + 1.0])
                let distances = closestRowDistances(candidates, samples, sampleY)
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

            if px < stop
            {
                let sampleX  = left + cast(f64, px) + 0.5
                let distance = closestRowDistances(candidates, Math.Simd.splat(sampleX), sampleY)[0]
                winding += windingChanges[px]
                let signedDistance = winding ? distance : -distance
                let value = Math.max(0.0, Math.min(255.0, 128.0 + signedDistance * scale))
                dst[] = cast(u8, Math.round(value))
                dst   += 1
            }

            start = stop
        }
    }

    safeSlot.setBitmap(rows, width, cast(s32, width), bitmapBuffer, .Gray, left, top)
}
