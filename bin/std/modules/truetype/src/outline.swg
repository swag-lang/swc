using Swag, Core

func clearOutline(slot: *GlyphSlot)
{
    slot.outline.contourCount = 0
    slot.outline.pointCount   = 0
    slot.outline.points     = null
    slot.outline.tags       = null
    slot.outline.contours   = null
    slot.outline.flags      = 0
}

func clearBitmap(slot: *GlyphSlot)
{
    slot.bitmap.rows         = 0
    slot.bitmap.width        = 0
    slot.bitmap.pitch        = 0
    slot.bitmap.buffer       = null
    slot.bitmap.pixelMode   = .Gray
    slot.bitmap.grayCount    = 256
    slot.bitmapLeft         = 0
    slot.bitmapTop          = 0
}

func midpoint(a, b: Vector)->Vector
{
    var result: retval
    result.x = cast(s32) ((cast(s64) a.x + b.x) / 2)
    result.y = cast(s32) ((cast(s64) a.y + b.y) / 2)
    return result
}

func pointsEqual(a, b: Vector)->bool
{
    return a.x == b.x and a.y == b.y
}

func isOnCurve(tag: u8)->bool
{
    return (tag & CURVE_TAG_ON) != 0
}

func buildOutlineCommands(outline: const *Outline)->Array'OutlineCommand
{
    var commands: Array'OutlineCommand
    if !outline or outline.contourCount <= 0 or outline.pointCount <= 0 do
        return commands

    var contourStart = 0'u32
    for cast(u32) outline.contourCount
    {
        let contourEnd = cast(u32) outline.contours[@index]
        let first      = outline.points[contourStart]
        let last       = outline.points[contourEnd]
        let firstOn    = isOnCurve(outline.tags[contourStart])
        let lastOn     = isOnCurve(outline.tags[contourEnd])

        var startPoint: Vector
        var current: Vector
        var idx = contourStart

        if firstOn
        {
            startPoint = first
            current    = first
            commands.add(OutlineCommand{kind: .MoveTo, p0: first})
            idx += 1
        }
        else
        {
            startPoint = lastOn ? last : midpoint(last, first)
            current    = startPoint
            commands.add(OutlineCommand{kind: .MoveTo, p0: startPoint})
        }

        while idx <= contourEnd
        {
            let point = outline.points[idx]
            if isOnCurve(outline.tags[idx])
            {
                commands.add(OutlineCommand{kind: .LineTo, p0: point})
                current = point
                idx += 1
                continue
            }

            let nextIdx = idx == contourEnd ? contourStart : idx + 1
            let nextPt  = outline.points[nextIdx]
            if isOnCurve(outline.tags[nextIdx])
            {
                commands.add(OutlineCommand{kind: .ConicTo, p0: point, p1: nextPt})
                current = nextPt
                idx += 2
            }
            else
            {
                let mid = midpoint(point, nextPt)
                commands.add(OutlineCommand{kind: .ConicTo, p0: point, p1: mid})
                current = mid
                idx += 1
            }
        }

        if !pointsEqual(current, startPoint) do
            commands.add(OutlineCommand{kind: .LineTo, p0: startPoint})

        contourStart = contourEnd + 1
    }

    return commands
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

func computeOutlineBounds(outline: const *Outline)->{ minX: s32, minY: s32, maxX: s32, maxY: s32 }
{
    var result: retval
    if !outline or outline.pointCount <= 0 do
        return result

    result.minX = Swag.S32.Max
    result.minY = Swag.S32.Max
    result.maxX = Swag.S32.Min
    result.maxY = Swag.S32.Min

    for cast(u32) outline.pointCount
    {
        let pt = outline.points[@index]
        result.minX = Math.min(result.minX, pt.x)
        result.minY = Math.min(result.minY, pt.y)
        result.maxX = Math.max(result.maxX, pt.x)
        result.maxY = Math.max(result.maxY, pt.y)
    }

    return result
}

func updateSlotMetrics(slot: *GlyphSlot)
{
    let bounds = computeOutlineBounds(&slot.outline)
    if slot.outline.pointCount <= 0
    {
        slot.metrics = {}
        return
    }

    slot.metrics.width        = bounds.maxX - bounds.minX
    slot.metrics.height       = bounds.maxY - bounds.minY
    slot.metrics.horizontalBearingX = bounds.minX
    slot.metrics.horizontalBearingY = bounds.maxY
    slot.metrics.verticalAdvance  = 0
    slot.metrics.verticalBearingX = 0
    slot.metrics.verticalBearingY = 0
}
