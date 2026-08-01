using Swag, Core

// Identifies one operation in a decomposed glyph contour.
public enum OutlineCommandKind
{
    MoveTo      // Starts a new contour at `p0`.
    LineTo      // Adds a straight segment ending at `p0`.
    ConicTo     // Adds a quadratic Bézier with control `p0` and endpoint `p1`.
    CubicTo     // Adds a cubic Bézier with controls `p0`, `p1` and endpoint `p2`.
}

// Represents one path operation produced by [[TrueType.Outline.decompose]].
//
// Coordinates use 26.6 fixed-point pixels. The fields used by the command depend
// on `kind`; unused points remain zero.
public struct OutlineCommand
{
    kind: OutlineCommandKind     // Operation represented by this value.
    p0:   Vector                 // Destination or first control point.
    p1:   Vector                 // Destination or second control point when required.
    p2:   Vector                 // Cubic destination when required.
}

// Exposes the borrowed contours of the current scalable glyph.
//
// Points use 26.6 fixed-point pixels with y growing upward. `contours` stores the
// inclusive last point index of each contour; `tags` identifies on-curve points.
// All pointed-to storage belongs to the parent [[TrueType.Face]] and is replaced
// by the next glyph load.
public struct Outline
{
    // The face owns the arrays and their shape. Public outline methods may mutate
    // the pointed-to coordinates without allowing callers to replace the view.
    readonly
    {
        contourCount: s16                  // Number of closed contours.
        pointCount:   s16                  // Total number of outline points.
        points:       #null [*] Vector     // Borrowed point array, or null when empty.
        tags:         #null [*] u8         // Borrowed point-tag array, or null when empty.
        contours:     #null [*] s16        // Borrowed inclusive contour-end indices.
        flags:        s32                  // Reserved outline flags; currently zero.
    }
}

public impl Outline
{
    internal func borrowed(points: #null [*] Vector, tags: #null [*] u8, contours: #null [*] s16, pointCount, contourCount: s16)->Outline
    {
        var result: retval
        result.points       = points
        result.tags         = tags
        result.contours     = contours
        result.pointCount   = pointCount
        result.contourCount = contourCount
        return result
    }

    internal mtd reset()
    {
        .contourCount = 0
        .pointCount   = 0
        .points       = null
        .tags         = null
        .contours     = null
        .flags        = 0
    }

    internal mtd setView(points: #null [*] Vector, tags: #null [*] u8, contours: #null [*] s16, pointCount, contourCount: s16)
    {
        .points       = points
        .tags         = tags
        .contours     = contours
        .pointCount   = pointCount
        .contourCount = contourCount
        .flags        = 0
    }

    // Translates every point by a 26.6 fixed-point offset.
    mtd translate(xOffset, yOffset: s32)
    {
        if .pointCount <= 0 do
            return

        let points = notnull .points
        for cast(u32) .pointCount
        {
            points[@index].x += xOffset
            points[@index].y += yOffset
        }
    }

    // Applies a 16.16 fixed-point linear transform to every point.
    //
    // Translation is intentionally not part of [[TrueType.Matrix]]; call
    // [[TrueType.Outline.translate]] separately when required.
    mtd transform(matrix: Matrix)
    {
        if .pointCount <= 0 do
            return

        let points = notnull .points
        for cast(u32) .pointCount
        {
            let pt = points[@index]
            points[@index].x = roundDiv(cast(s64) pt.x * matrix.xx + cast(s64) pt.y * matrix.xy, 65536)
            points[@index].y = roundDiv(cast(s64) pt.x * matrix.yx + cast(s64) pt.y * matrix.yy, 65536)
        }
    }

    // Thickens the current outline by the requested 26.6 fixed-point strength.
    //
    // The outline is mutated in place. Positive strengths add ink while preserving
    // counters; load the glyph again to recover its original shape.
    mtd embolden(strength: s32) fail
    {
        if .pointCount <= 0 or .contourCount <= 0 or !strength do
            return

        // Orientation must be computed once for the whole glyph, not per contour.
        // Outer contours and their holes (counters) are wound in opposite
        // directions, so a single shift sign expands the outer ring and shrinks
        // the holes - both adding ink. Re-deriving the winding per contour would
        // instead grow the holes, making letters bigger but not actually bolder.
        let ccw = totalOutlineSignedArea(me) >= 0

        // Match FreeType's FT_Outline_EmboldenXY, which halves the strength before
        // shifting: each side of a stem moves by strength/2, so the stem thickens by
        // strength total. Shifting by the full strength per side would otherwise
        // double the visual weight for the same nominal value.
        let perSide = cast(f64) strength * 0.5

        var start    = 0'u32
        let points   = notnull .points
        let contours = notnull .contours
        for cast(u32) .contourCount
        {
            let endIdx = cast(u32) contours[@index]
            let slice  = @mkslice(points + start, endIdx - start + 1)
            applyEmboldenToContour(slice, perSide, ccw)
            start = endIdx + 1
        }
    }

    // Converts the contours into an owned sequence of path commands.
    //
    // Quadratic TrueType segments become `ConicTo` commands. The returned array
    // remains valid independently of the face's reusable glyph slot.
    mtd const decompose()->Array'OutlineCommand => buildOutlineCommands(me)
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
    if outline.contourCount <= 0 or outline.pointCount <= 0 do
        return commands

    var contourStart = 0'u32
    let points       = cast(const [*] Vector) (notnull outline.points)
    let tags         = cast(const [*] u8) (notnull outline.tags)
    let contours     = cast(const [*] s16) (notnull outline.contours)
    for cast(u32) outline.contourCount
    {
        let contourEnd = cast(u32) contours[@index]
        let first      = points[contourStart]
        let last       = points[contourEnd]
        let firstOn    = isOnCurve(tags[contourStart])
        let lastOn     = isOnCurve(tags[contourEnd])

        var startPoint: Vector
        var current:    Vector
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
            let point = points[idx]
            if isOnCurve(tags[idx])
            {
                commands.add(OutlineCommand{kind: .LineTo, p0: point})
                current = point
                idx     += 1
                continue
            }

            let nextIdx = idx == contourEnd ? contourStart : idx + 1
            let nextPt  = points[nextIdx]
            if isOnCurve(tags[nextIdx])
            {
                commands.add(OutlineCommand{kind: .ConicTo, p0: point, p1: nextPt})
                current = nextPt
                idx     += 2
            }
            else
            {
                let mid = midpoint(point, nextPt)
                commands.add(OutlineCommand{kind: .ConicTo, p0: point, p1: mid})
                current = mid
                idx     += 1
            }
        }

        if !pointsEqual(current, startPoint) do
            commands.add(OutlineCommand{kind: .LineTo, p0: startPoint})

        contourStart = contourEnd + 1
    }

    return commands
}

func contourSignedArea(points: const [..] Vector)->f64
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

// Sum the signed area of every contour. For a well-formed glyph the outer
// contour dominates, so the sign gives the glyph orientation; the magnitude is
// the net filled area (outer minus holes).
func totalOutlineSignedArea(outline: const *Outline)->f64
{
    if outline.pointCount <= 0 or outline.contourCount <= 0 do
        return 0

    var total    = 0.0'f64
    var start    = 0'u32
    let points   = cast(const [*] Vector) (notnull outline.points)
    let contours = cast(const [*] s16) (notnull outline.contours)
    for cast(u32) outline.contourCount
    {
        let endIdx = cast(u32) contours[@index]
        let slice  = @mkslice(points + start, endIdx - start + 1)
        total += contourSignedArea(slice)
        start = endIdx + 1
    }

    return total
}

func applyEmboldenToContour(points: [..] Vector, strength: f64, ccw: bool)
{
    if @countof(points) < 2 or Math.isZeroEpsilon(cast(f32) strength) do
        return

    var source: Array'Vector
    source.add(points)

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

        var dirx   = n0x + n1x
        var diry   = n0y + n1y
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

        let dot   = Math.abs(dirx * n1x + diry * n1y)
        let miter = dot > 0.25 ? Math.min(4.0, 1.0 / dot) : 1.0
        points[@index].x = cast(s32) Math.round(cur.x + dirx * strength * miter)
        points[@index].y = cast(s32) Math.round(cur.y + diry * strength * miter)
    }
}
