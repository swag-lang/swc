using Swag, Core

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
    for edge in edges do
        distSquared = Math.min(distSquared, edgeDistanceSquared(edge, x, y))

    return Math.sqrt(distSquared)
}

func renderCurrentOutlineSdf(slot: *GlyphSlot, spread: u32) throw
{
    let faceData = getSlotImpl(slot)
    let safeSlot = assume slot
    clearBitmap(safeSlot)

    if safeSlot.format != .Outline do
        fail(0x13)

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
    let bitmapBuffer = assume faceData.bitmapPixels.buffer
    var dst = bitmapBuffer
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

    safeSlot.bitmap.rows         = rows
    safeSlot.bitmap.width        = width
    safeSlot.bitmap.pitch        = cast(s32) width
    safeSlot.bitmap.buffer       = bitmapBuffer
    safeSlot.bitmap.pixelMode   = .Gray
    safeSlot.bitmap.grayCount    = 256
    safeSlot.bitmapLeft         = left
    safeSlot.bitmapTop          = top
}
