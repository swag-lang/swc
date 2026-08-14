#global public

using Core.Math

const ClipperScaleCoords = 1000.0'f64     // Scale from floating path pixels to integer Clipper coordinates.

// Owns an ordered polygon contour and cached geometric properties.
//
// Call `recompute` after mutating `points` to refresh winding, convexity, length,
// area, and bounds.
struct Polygon
{
    public points: Array'Vector2     // Ordered contour vertices in path-space pixels.

    // Everything [[Pixel.Polygon.recompute]] derives from `points`. Change the points and recompute
    // again; writing one of these on its own would describe a contour that is not there.
    public readonly
    {
        isClockwise: bool             // Winding direction after `recompute`.
        isConvex:    bool             // Whether every turn has the same orientation.
        isSimple:    bool             // Whether non-adjacent edges do not intersect.
        area:        f32              // Unsigned enclosed area, in square pixels.
        perimeter:   f32              // Closed-contour perimeter, in pixels.
        minBounds:   Math.Vector2     // Minimum coordinate bound.
        maxBounds:   Math.Vector2     // Maximum coordinate bound.
    }
}

impl Polygon
{
    internal mtd appendClipperPath(path: *Clipper.ClipperPath)
    {
        var count = .points.count
        if count > 1 and .points[0].distanceSquaredTo(.points[count - 1]) < 0.5 * 0.5 do
            count -= 1

        for i in count
        {
            let pt = .points[i]
            path.add(Clipper.IntPoint{cast(s64) (pt.x * ClipperScaleCoords), cast(s64) (pt.y * ClipperScaleCoords)})
        }
    }

    internal func setupGeneratedPath(path: *LinePath)
    {
        path.adoptGeneratedPolygon()
    }

    // Borrows the address of the point at zero-based index `i`.
    #[Swag.Inline]
    mtd pointAt(i: u64)->*Vector2
    {
        Debug.assert(i < .points.count)
        let points = .points.buffer!
        return points + i
    }

    // Borrows the address of the point at zero-based index `i`, as read-only.
    #[Swag.Inline]
    mtd const pointAt(i: u64)->const *Vector2
    {
        Debug.assert(i < .points.count)
        let points = .points.buffer!
        return points + i
    }

    // Reports whether `pt` lies inside the contour, by the even-odd rule.
    //
    // A point exactly on an edge can land on either side; callers that need a stable
    // answer there should not probe boundary points.
    mtd const contains(pt: Vector2)->bool
    {
        let n = .points.count
        if n < 3 do
            return false

        var inside = false
        var j      = n - 1
        for i in n
        {
            let a = .points[i]
            let b = .points[j]
            if (a.y > pt.y) != (b.y > pt.y)
            {
                let x = a.x + (pt.y - a.y) / (b.y - a.y) * (b.x - a.x)
                if pt.x < x do
                    inside = !inside
            }

            j = i
        }

        return inside
    }

    // Returns point `i`, optionally offset along the averaged edge normal.
    mtd const offsetPointAt(i: u64, offset: f32)->Vector2
    {
        Debug.assert(.points.count)
        let points = .points.buffer!
        if Math.isZeroEpsilon(offset)
        {
            Debug.assert(i < .points.count)
            return points[i]
        }

        var count = .points.count
        if count > 1 and points[0].distanceSquaredTo(points[count - 1]) < 0.5 * 0.5 do
            count -= 1
        Debug.assert(count)
        let pointIndex = i % count
        if count < 3 do
            return points[pointIndex]

        let v0 = points[(pointIndex + count - 1) % count]
        let v1 = points[pointIndex]
        let v2 = points[(pointIndex + 1) % count]

        let tmp0 = Vector2.normalizedOrZero(v1 - v0)
        let n0   = tmp0.cross(1)
        let tmp1 = Vector2.normalizedOrZero(v2 - v1)
        let n1   = tmp1.cross(1)

        let vva1 = v1 + n0
        let vva0 = v0 + n0
        let vvb1 = v2 + n1
        let vvb0 = v1 + n1
        let {intersects, intersectionPoint} = Geometry.intersectLines(vva0, vva1, vvb0, vvb1)

        var result: retval = v1
        if intersects
        {
            result += ((intersectionPoint - v1) * offset)
        }
        else
        {
            let n = Vector2.normalizedOrZero(n0 + n1)
            result += (n * offset)
        }

        return result
    }

    // Divide by adding points if two points are too far away
    mtd subdivideEdges(maxDistance: f32, closed: bool = true)
    {
        Debug.assert(maxDistance > 0)
        if .points.count < 2 do
            return

        var i = 0'u64
        while i < (closed ? .points.count : .points.count - 1)
        {
            defer i += 1
            var v      = .points[(i + 1) % .points.count] - .points[i]
            let d      = v.length()
            var divide = cast(s32) (d / maxDistance)
            if divide > 0
            {
                v /= cast(f32) (divide + 1)
                while divide > 0
                {
                    let np = .points[i] + v
                    .points.insertAt(i + 1, np)
                    divide -= 1
                    i      += 1
                }
            }
        }
    }

    // Declares the winding direction of this contour without recomputing it.
    //
    // The fill passes build contours whose orientation they already know, so they state it
    // instead of paying for a `recompute` that would only confirm it.
    internal mtd assumeClockwise(value: bool)
    {
        .isClockwise = value
    }

    // Clear all points
    mtd clear()
    {
        .area        = 0
        .isClockwise = false
        .isConvex    = true
        .isSimple    = true
        .perimeter   = 0
        .minBounds   = {}
        .maxBounds   = {}
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
                    if Geometry.intersectSegments(a0, a1, b0, b1, 0.01).intersects do
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
        // `minBounds` and `maxBounds` are already filled by the `recompute` loop.
        var res = cast(s32) Math.sqrt(cast(f32) count)
        res = Math.clamp(res, 1, 1024)

        let w     = .maxBounds.x - .minBounds.x
        let h     = .maxBounds.y - .minBounds.y
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

            let cx0 = Math.clamp(cast(s32) ((Math.min(a0.x, a1.x) - .minBounds.x) * invCw), 0, res - 1)
            let cx1 = Math.clamp(cast(s32) ((Math.max(a0.x, a1.x) - .minBounds.x) * invCw), 0, res - 1)
            let cy0 = Math.clamp(cast(s32) ((Math.min(a0.y, a1.y) - .minBounds.y) * invCh), 0, res - 1)
            let cy1 = Math.clamp(cast(s32) ((Math.max(a0.y, a1.y) - .minBounds.y) * invCh), 0, res - 1)

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
                        if Geometry.intersectSegments(a0, a1, b0, b1, 0.01).intersects do
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
            copy.add(.offsetPointAt(i, value))

        .points = #move copy
        .recompute()
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

        // Closed path needs last point to be the same as the first one; copy it out
        // before 'add' can reallocate the buffer it points into.
        let v0 = dref .pointAt(0)
        .add(v0)

        // Clipper output contours never self-intersect, so the O(n^2) simplicity
        // test in `recompute` is redundant here.
        .recompute(knownSimple: true)
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
        case .Round: joinType = .Round
        case .Bevel: joinType = .Square
        case .Miter: joinType = .Miter
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
    mtd offsetPaths(value: f32, joinStyle: JoinStyle, tolerance: f32 = 0.5)->LinePathList
    {
        var result: retval

        var res: Clipper.ClipperPaths
        .offsetInto(&res, value, joinStyle, tolerance)

        for p, i in res
        {
            let np = result.newPath()
            np.polygon.storeClipperResult(p)
            setupGeneratedPath(np)
            if i == 0 do
                result.setBounds(np.minBounds, np.maxBounds)
            else do
                result.setBounds(Vector2.min(result.minBounds, np.minBounds), Vector2.max(result.maxBounds, np.maxBounds))
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
    mtd cleanedPaths()->LinePathList
    {
        var result: retval

        var res: Clipper.ClipperPaths
        .cleanInto(&res)

        for p, i in res
        {
            let np = result.newPath()
            np.polygon.storeClipperResult(p)
            setupGeneratedPath(np)
            if i == 0 do
                result.setBounds(np.minBounds, np.maxBounds)
            else do
                result.setBounds(Vector2.min(result.minBounds, np.minBounds), Vector2.max(result.maxBounds, np.maxBounds))
            if !.isClockwise do
                break
        }

        return result
    }

    // Computes the polygon's cached geometric properties.
    //
    // Call this after adding all points. `knownSimple` lets a caller that already
    // guarantees the polygon does not
    // self-intersect (e.g. the output of a Clipper union/clean/offset) skip the
    // O(n^2) self-intersection test, which otherwise dominates for large contours.
    mtd recompute(knownSimple = false)
    {
        .area        = 0
        .isClockwise = false
        .isConvex    = true
        .isSimple    = true
        .perimeter   = 0
        .minBounds   = {}
        .maxBounds   = {}

        if !.points.count do
            return

        var count = .points.count
        if count > 1 and .points[0].distanceSquaredTo(.points[count - 1]) < 0.5 * 0.5 do
            count -= 1

        .minBounds = .points[0]
        .maxBounds = .points[0]
        if count == 1 do
            return

        var signedTwiceArea = 0'f32
        var firstTurnSign   = 0'f32
        for i in count
        {
            let current = .points[i]
            let next    = .points[(i + 1) % count]
            .minBounds      = Vector2.min(.minBounds, current)
            .maxBounds      = Vector2.max(.maxBounds, current)
            .perimeter      += current.distanceTo(next)
            signedTwiceArea += current.x * next.y - next.x * current.y

            if count >= 3
            {
                let afterNext = .points[(i + 2) % count]
                let turn      = (next - current).cross(afterNext - next)
                if !Math.isZeroEpsilon(turn)
                {
                    if Math.isZeroEpsilon(firstTurnSign) do
                        firstTurnSign = Math.sign(turn)
                    elif Math.sign(turn) != firstTurnSign do
                        .isConvex = false
                }
            }
        }

        .area        = Math.abs(signedTwiceArea) * 0.5
        .isClockwise = count >= 3 and signedTwiceArea >= 0

        // A convex polygon never self-intersects, so it is simple by construction.
        // Skip the O(n^2) self-intersection test in that case — it covers the common
        // UI shapes (round rects, circles, ellipses) flattened every frame. 'isSimple'
        // is only read for non-convex polygons (the triangulated fill branch and the
        // offset-input selection), so this stays correct.
        if .isConvex or knownSimple do
            .isSimple = true
        else do
            .isSimple = .computeIsSimple(count)
    }
}
