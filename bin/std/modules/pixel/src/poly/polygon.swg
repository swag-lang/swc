#global public
using Core.Math

const ClipperScaleCoords = 1000.0'f64

struct Polygon
{
    points: Array'Vector2

    // Fill with a call to compute()
    isClockwise:     bool
    isConvex:        bool
    isSimple:        bool
    area:            f32
    totalLen:        f32
    bvMin:           Math.Vector2
    bvMax:           Math.Vector2
}

impl Polygon
{
    internal mtd appendClipperPath(path: *Clipper.ClipperPath)
    {
        var count = .points.count
        if count > 1 and .points[0].distanceToSquared(.points[count - 1]) < 0.5 * 0.5 do
            count -= 1

        for i in count
        {
            let pt = .points[i]
            path.add(Clipper.IntPoint{cast(s64) (pt.x * ClipperScaleCoords), cast(s64) (pt.y * ClipperScaleCoords)})
        }
    }

    internal func setupGeneratedPath(path: *LinePath)
    {
        path.isPolyOnly = true
        path.isClosed   = true
        path.isDirty    = false
        path.isFlatten  = true
        path.bvMin      = path.polygon.bvMin
        path.bvMax      = path.polygon.bvMax

        if path.polygon.points.count
        {
            path.startPoint = path.polygon.getPoint(0)
            path.endPoint   = path.startPoint
        }
    }

    // Get the given point
    #[Swag.Inline]
    mtd getPoint(i: u64)->&Vector2
    {
        let points = .points.buffer orelse cast([*] Vector2) 1'u64
        return points + i
    }

    #[Swag.Inline]
    mtd const getPoint(i: u64)->const &Vector2
    {
        let points = .points.buffer orelse cast([*] Vector2) 1'u64
        return points + i
    }

    // Get the given point, with an optional offset
    mtd const getPoint(i: u64, offset: f32 = 0)->Vector2
    {
        let points = .points.buffer orelse cast([*] Vector2) 1'u64
        if Math.isZeroEpsilon(offset) do
            return points[i]

        let count = .points.count - 1

        let v0 = points[(i + count - 1) % count]
        let v1 = points[i]
        let v2 = points[(i + 1) % count]

        let tmp0 = Vector2.toNormalizedSafe(v1 - v0)
        let n0   = tmp0.cross(1)
        let tmp1 = Vector2.toNormalizedSafe(v2 - v1)
        let n1   = tmp1.cross(1)

        let vva1 = v1 + n0
        let vva0 = v0 + n0
        let vvb1 = v2 + n1
        let vvb0 = v1 + n1
        let (yes, intPos) = Geometry.lineLineIntersect(vva0, vva1, vvb0, vvb1)

        var result: retval = v1
        if yes
        {
            result += ((intPos - v1) * offset)
        }
        else
        {
            let n = Vector2.toNormalizedSafe(n0 + n1)
            result += (n * offset)
        }

        return result
    }

    // Divide by adding points if two points are too far away
    mtd normalizeDist(dist: f32, closed: bool = true)
    {
        var i = 0'u64
        while i < (closed ? .points.count : .points.count - 1)
        {
            defer i += 1
            var v      = .points[(i + 1) % .points.count] - .points[i]
            let d      = v.length()
            var divide = cast(s32) (d / dist)
            if divide > 0
            {
                v /= cast(f32) (divide + 1)
                while divide > 0
                {
                    let np = .points[i] + v
                    .points.insertAt(i + 1, np)
                    divide -= 1
                    i += 1
                }
            }
        }
    }

    // Clear all points
    mtd clear()
    {
        .area        = 0
        .isClockwise = false
        .isConvex    = true
        .isSimple    = true
        .totalLen    = 0
        .points.clear()
    }

    // Add a new point
    mtd add(v: Vector2)
    {
        .points.add(v)
    }

    private mtd computeIsSimple(count: u64)->bool
    {
        if count < 4 do
            return true

        // Small rings: the brute-force all-pairs test is cheaper than building a grid
        // (no allocation), and stays exact. The O(n^2) cost is negligible here.
        if count <= 48
        {
            for i in count
            {
                let nextI = (i + 1) % count
                let a0    = .points[i]
                let a1    = .points[nextI]
                if a0.isEqualEpsilon(a1) do
                    continue

                var j = i + 1
                while j < count
                {
                    defer j += 1
                    let nextJ = (j + 1) % count
                    if nextI == j or nextJ == i do
                        continue

                    let b0 = .points[j]
                    let b1 = .points[nextJ]
                    if b0.isEqualEpsilon(b1) do
                        continue
                    if Geometry.segSegIntersect(a0, a1, b0, b1, 0.01).yes do
                        return false
                }
            }

            return true
        }

        // Self-intersection test via a uniform spatial grid over the polygon bbox.
        // Each edge is registered in every cell its bounding box overlaps and tested
        // only against edges already present in those cells. Two intersecting edges
        // always share the cell containing their crossing point, so no pair is missed,
        // while for the dense, short edges produced by flattening this runs in ~O(n)
        // instead of the O(n^2) brute-force all-pairs test. That test dominated the
        // entire vector pipeline (it runs in every non-convex path flatten).
        // 'bvMin'/'bvMax' are already filled by the compute() loop above.
        var res = cast(s32) Math.sqrt(cast(f32) count)
        res = Math.clamp(res, 1, 1024)

        let w     = .bvMax.x - .bvMin.x
        let h     = .bvMax.y - .bvMin.y
        let invCw = w > Math.ConstF32.Epsilon ? cast(f32) res / w : 0'f32
        let invCh = h > Math.ConstF32.Epsilon ? cast(f32) res / h : 0'f32

        var grid: Array'(Array'u32)
        grid.resize(cast(u64) res * cast(u64) res)

        for i in count
        {
            let nextI = (i + 1) % count
            let a0    = .points[i]
            let a1    = .points[nextI]
            if a0.isEqualEpsilon(a1) do
                continue

            let cx0 = Math.clamp(cast(s32) ((Math.min(a0.x, a1.x) - .bvMin.x) * invCw), 0, res - 1)
            let cx1 = Math.clamp(cast(s32) ((Math.max(a0.x, a1.x) - .bvMin.x) * invCw), 0, res - 1)
            let cy0 = Math.clamp(cast(s32) ((Math.min(a0.y, a1.y) - .bvMin.y) * invCh), 0, res - 1)
            let cy1 = Math.clamp(cast(s32) ((Math.max(a0.y, a1.y) - .bvMin.y) * invCh), 0, res - 1)

            // Test against edges already registered in #null any cell this edge overlaps.
            for cy in cy0 to cy1
            {
                for cx in cx0 to cx1
                {
                    for j in grid[cast(u64) (cy * res + cx)]
                    {
                        let nextJ = (j + 1) % count
                        if nextI == j or nextJ == i do
                            continue

                        let b0 = .points[j]
                        let b1 = .points[nextJ]
                        if b0.isEqualEpsilon(b1) do
                            continue
                        if Geometry.segSegIntersect(a0, a1, b0, b1, 0.01).yes do
                            return false
                    }
                }
            }

            // Register this edge in every overlapped cell.
            for cy in cy0 to cy1
            {
                for cx in cx0 to cx1 do
                    grid[cast(u64) (cy * res + cx)].add(cast(u32) i)
            }
        }

        return true
    }

    // Fast expand polygon by a given amount
    mtd offset(value: f32)
    {
        if Math.isZeroEpsilon(value) do
            return
        if !.points.count do
            return

        var copy: Array'Vector2
        copy.reserve(.points.count)

        for i in .points.count do
            copy.add(.getPoint(i, value))

        .points = #move copy
    }

    internal mtd storeClipperResult(res: Clipper.ClipperPath)
    {
        .clear()
        if !res.count do
            return

        for pt in res
        {
            let vec = Math.Vector2{cast(f32) (pt.x / ClipperScaleCoords), cast(f32) (pt.y / ClipperScaleCoords)}
            .add(vec)
        }

        // Closed path needs last point to be the same as the first one
        let v0 = .getPoint(0)
        .add(v0)

        // Clipper output contours never self-intersect, so the O(n^2) simplicity
        // test in compute() is redundant here.
        .compute(knownSimple: true)
    }

    internal mtd addOffsetInputs(off: *Clipper.Offset, joinType: Clipper.JoinType)
    {
        if .isSimple
        {
            var path: Clipper.ClipperPath
            .appendClipperPath(&path)
            off.addPath(path, joinType)
        }
        else
        {
            // Offset cleaned contours only when the polygon is known to be
            // non-simple. Cleaning simple glyph outlines first can fragment
            // inner contours into many tiny loops.
            var paths: Clipper.ClipperPaths
            .cleanInto(&paths)
            for path in paths do
                off.addPath(path, joinType)
        }
    }

    private mtd offsetInto(res: *Clipper.ClipperPaths, value: f32, joinStyle: JoinStyle, toler: f32)
    {
        if Math.isZeroEpsilon(value) do
            return
        if !.points.count do
            return

        var joinType = Clipper.JoinType.Square
        switch joinStyle
        {
        case Round:
            joinType = .Round
        case Bevel:
            joinType = .Square
        case Miter:
            joinType = .Miter
        }

        var off: Clipper.Offset
        off.arcTolerance = toler * ClipperScaleCoords
        .addOffsetInputs(&off, joinType)

        // Compute
        off.execute(res, cast(f64) (value * ClipperScaleCoords))
    }

    // Slow but quality offset with a joinStyle
    mtd offset(value: f32, joinStyle: JoinStyle, toler: f32 = 0.5)
    {
        var res: Clipper.ClipperPaths

        .offsetInto(&res, value, joinStyle, toler)
        .clear()
        if res.count do
            .storeClipperResult(res[0])
    }

    // Slow but quality offset with a joinStyle
    mtd getOffset(value: f32, joinStyle: JoinStyle, toler: f32 = 0.5)->LinePathList
    {
        var result: retval
        result.bvMin = .bvMin
        result.bvMax = .bvMax

        var res: Clipper.ClipperPaths
        .offsetInto(&res, value, joinStyle, toler)

        for p in res
        {
            let np = result.newPath()
            np.polygon.storeClipperResult(p)
            setupGeneratedPath(np)
        }

        return result
    }

    private mtd cleanInto(res: *Clipper.ClipperPaths)
    {
        if !.points.count do
            return

        var trf: Clipper.Transform
        trf.strictSimple  = true
        trf.reverseOutput = !.isClockwise

        // Register path
        var path: Clipper.ClipperPath
        .appendClipperPath(&path)
        trf.addPath(&path, .Subject)

        // Compute
        trf.execute(.Union, res, .NonZero, .NonZero)
    }

    // Clean polygon by removing bad/unecessary points
    mtd clean()
    {
        var res: Clipper.ClipperPaths
        .cleanInto(&res)
        .clear()
        if res.count do
            .storeClipperResult(res[0])
    }

    // Clean polygon by removing bad/unecessary points
    mtd getClean()->LinePathList
    {
        var result: retval
        result.bvMin = .bvMin
        result.bvMax = .bvMax

        var res: Clipper.ClipperPaths
        .cleanInto(&res)

        for p in res
        {
            let np = result.newPath()
            np.polygon.storeClipperResult(p)
            setupGeneratedPath(np)
            if !.isClockwise do
                break
        }

        return result
    }

    // Compute private values, like convex/clockwise
    // Call it once the polygon contains all its points.
    // 'knownSimple' lets a caller that already guarantees the polygon does not
    // self-intersect (e.g. the output of a Clipper union/clean/offset) skip the
    // O(n^2) self-intersection test, which otherwise dominates for large contours.
    mtd compute(knownSimple = false)
    {
        .area        = 0
        .isClockwise = false
        .isConvex    = true
        .isSimple    = true
        .totalLen    = 0

        if !.points.count do
            return

        let n        = .points.count - 1
        let isClosed = .points[0].distanceToSquared(.points.back()) < 0.5 * 0.5
        if isClosed do
            .points.count -= 1

        var q = 0
        var p = n - 1

        .bvMin = .points[0]
        .bvMax = .points[0]

        var first = true
        var lastC = 0'f32
        while q < n
        {
            // Convex
            let v  = .points.buffer[(q + 2) % .points.count] - .points.buffer[(q + 1) % .points.count]
            let v1 = .points.buffer[(q + 1) % .points.count] - .points.buffer[(q + 0) % .points.count]
            let c  = v.cross(v1)
            if first
            {
                lastC = c
                first = false
            }
            elif !Math.isZeroEpsilon(c) and !Math.isZeroEpsilon(lastC) and Math.sign(c) != Math.sign(lastC)
            {
                .isConvex = false
            }

            .bvMin = Vector2.min(.bvMin, .points[p])
            .bvMax = Vector2.max(.bvMax, .points[p])

            // Area
            .area += .points[p].x * .points[q].y - .points[q].x * .points[p].y
            .totalLen += v1.length()
            p = q
            q += 1
        }

        if isClosed do
            .points.count += 1

        // A convex polygon never self-intersects, so it is simple by construction.
        // Skip the O(n^2) self-intersection test in that case — it covers the common
        // UI shapes (round rects, circles, ellipses) flattened every frame. 'isSimple'
        // is only read for non-convex polygons (the triangulated fill branch and the
        // offset-input selection), so this stays correct.
        if .isConvex or knownSimple do
            .isSimple = true
        else do
            .isSimple = .computeIsSimple(n)

        .isClockwise = .area >= 0
    }
}
