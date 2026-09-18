#global namespace Math
#global namespace Geometry
#global public

// Returns whether `point` lies inside or on the axis-aligned ellipse centered at `center` with the radii `radiusX` and `radiusY`.
//
// Both radii must be positive, which is asserted.
func ellipseContainsPoint(point, center: Vector2, radiusX, radiusY: f32)->bool
{
    Swag.assert(radiusX > 0 and radiusY > 0)
    return (pow((point.x - center.x), 2) / pow(radiusX, 2)) + (pow((point.y - center.y), 2) / pow(radiusY, 2)) <= 1
}

// Returns whether `point` lies inside or on an edge of the triangle `a`, `b`, `c`.
//
// The vertices may be given in either winding order: the point is inside when it lies on the
// same side of all three edges.
func triangleContainsPoint(point, a, b, c: Vector2)->bool
{
    let ax  = c.x - b.x
    let ay  = c.y - b.y
    let bx  = a.x - c.x
    let by  = a.y - c.y
    let cx  = b.x - a.x
    let cy  = b.y - a.y
    let apx = point.x - a.x
    let apy = point.y - a.y
    let bpx = point.x - b.x
    let bpy = point.y - b.y
    let cpx = point.x - c.x
    let cpy = point.y - c.y

    let aCrossBp = ax * bpy - ay * bpx
    let cCrossAp = cx * apy - cy * apx
    let bCrossCp = bx * cpy - by * cpx

    return ((aCrossBp >= 0) and (bCrossCp >= 0) and (cCrossAp >= 0)) or ((aCrossBp <= 0) and (bCrossCp <= 0) and (cCrossAp <= 0))
}

// Returns the distance from `point` to the infinite line through `lineStart` and `lineEnd`.
//
// When the two points coincide there is no line, and the distance to `lineStart` is returned.
func distanceFromPointToLine(point, lineStart, lineEnd: Vector2)->f32
{
    // What remains of the offset once its component along the line is removed is perpendicular to it.
    let toPoint   = point - lineStart
    let direction = (lineEnd - lineStart).normalizedOrZero()
    return (toPoint - direction * toPoint.dot(direction)).length()
}

// Returns the shortest distance from `point` to the segment from `segmentStart` to `segmentEnd`.
//
// A segment whose ends coincide is treated as the point `segmentStart`.
func distanceFromPointToSegment(point, segmentStart, segmentEnd: Vector2)->f32
{
    let ab = segmentEnd - segmentStart
    if Math.isZeroEpsilon(ab.lengthSquared(), ConstF32.Epsilon * ConstF32.Epsilon) do
        return (point - segmentStart).length()

    let be = point - segmentEnd
    let ae = point - segmentStart

    let abbe = ab.dot(be)
    if abbe > 0 do
        return be.length()

    let abae = ab.dot(ae)
    if abae < 0 do
        return ae.length()

    // The projection falls inside the segment: the parallelogram area over the base length is
    // the height.
    return Math.abs(ab.cross(ae)) / ab.length()
}

// Returns the closest pair of points between two segments and the distance separating them.
//
// `first` lies on the segment from `firstStart` to `firstEnd`, and `second` on the segment from
// `secondStart` to `secondEnd`. A segment whose ends coincide is treated as a point. When several
// pairs are equally close, as with overlapping parallel segments, one of them is returned.
// @LICENCE: BSL-1.0
// @ORIGIN: Geometric Tools by David Eberly, https://www.geometrictools.com/GTE/Mathematics/DistSegmentSegment.h
// @MODIFIED: Adapted to Swag's two-dimensional vector API.
// @NOTICE: /bin/THIRDPARTY.md#geometric-tools
func closestPointsBetweenSegments(firstStart, firstEnd, secondStart, secondEnd: Math.Vector2)->{ first: Math.Vector2, second: Math.Vector2, distance: f32 }
{
    let p1p0 = firstEnd - firstStart
    let q1q0 = secondEnd - secondStart
    let p0q0 = firstStart - secondStart
    let a    = p1p0.dot(p1p0)
    let b    = p1p0.dot(q1q0)
    let c    = q1q0.dot(q1q0)
    let d    = p1p0.dot(p0q0)
    let e    = q1q0.dot(p0q0)
    let det  = a * c - b * b

    var result: retval
    let epsilonSquared = ConstF32.Epsilon * ConstF32.Epsilon
    if a <= epsilonSquared and c <= epsilonSquared
    {
        result.first    = firstStart
        result.second   = secondStart
        result.distance = (firstStart - secondStart).length()
        return result
    }

    if a <= epsilonSquared
    {
        let t = Math.clamp(e / c, 0'f32, 1'f32)
        result.first    = firstStart
        result.second   = secondStart + t * q1q0
        result.distance = (result.first - result.second).length()
        return result
    }

    if c <= epsilonSquared
    {
        let s = Math.clamp(-d / a, 0'f32, 1'f32)
        result.first    = firstStart + s * p1p0
        result.second   = secondStart
        result.distance = (result.first - result.second).length()
        return result
    }

    var s, t: f32
    if det > 0
    {
        let bte = b * e
        let ctd = c * d
        if bte <= ctd
        {
            s = 0
            if e <= 0
            {
                t = 0
                let nd = -d
                if nd >= a do
                    s = 1
                elif nd > 0 do
                    s = nd / a
            }
            elif e < c
            {
                t = e / c
            }
            else
            {
                t = 1
                let bmd = b - d
                if bmd >= a do
                    s = 1
                elif bmd > 0 do
                    s = bmd / a
            }
        }
        else
        {
            s = bte - ctd
            if s >= det
            {
                s = 1
                let bpe = b + e
                if bpe <= 0
                {
                    t = 0
                    let nd = -d
                    if nd <= 0 do
                        s = 0
                    elif nd < a do
                        s = nd / a
                }
                elif bpe < c
                {
                    t = bpe / c
                }
                else
                {
                    t = 1
                    let bmd = b - d
                    if bmd <= 0 do
                        s = 0
                    elif bmd < a do
                        s = bmd / a
                }
            }
            else
            {
                let ate = a * e
                let btd = b * d
                if ate <= btd
                {
                    t = 0
                    let nd = -d
                    if nd <= 0 do
                        s = 0
                    elif nd >= a do
                        s = 1
                    else do
                        s = nd / a
                }
                else
                {
                    t = ate - btd
                    if t >= det
                    {
                        t = 1
                        let bmd = b - d
                        if bmd <= 0 do
                            s = 0
                        elif bmd >= a do
                            s = 1
                        else do
                            s = bmd / a
                    }
                    else
                    {
                        s /= det
                        t /= det
                    }
                }
            }
        }
    }
    else
    {
        if e <= 0
        {
            t = 0
            let nd = -d
            if nd <= 0 do
                s = 0
            elif nd >= a do
                s = 1
            else do
                s = nd / a
        }
        elif e >= c
        {
            t = 1
            let bmd = b - d
            if bmd <= 0 do
                s = 0
            elif bmd >= a do
                s = 1
            else do
                s = bmd / a
        }
        else
        {
            s = 0
            t = e / c
        }
    }

    result.first  = firstStart + s * p1p0
    result.second = secondStart + t * q1q0
    let diff = result.first - result.second
    result.distance = diff.length()
    return result
}

// Returns where two infinite lines cross, as a factor along each: the crossing is
// `start + factor * (end - start)` on both lines.
private func lineIntersectionFactors(start0, end0, start1, end1: Vector2, epsilon: f32)->{ intersects: bool, firstFactor: f32, secondFactor: f32 }
{
    var result: retval

    let ua = (end1.x - start1.x) * (start0.y - start1.y) - (end1.y - start1.y) * (start0.x - start1.x)
    let ub = (end0.x - start0.x) * (start0.y - start1.y) - (end0.y - start0.y) * (start0.x - start1.x)
    let d  = (end1.y - start1.y) * (end0.x - start0.x) - (end1.x - start1.x) * (end0.y - start0.y)

    // Parallel or coincident lines have no single crossing.
    if Math.abs(d) < epsilon do
        return result

    result.intersects   = true
    result.firstFactor  = ua / d
    result.secondFactor = ub / d
    return result
}

// Returns the point where the infinite line through `start0` and `end0` crosses the one through `start1` and `end1`.
//
// `intersects` is false, and `point` is zero, when the lines are parallel or coincident. The
// test compares the cross product of the two direction vectors with `epsilon`, so it depends on
// their lengths as well as on the angle between them.
func intersectLines(start0, end0, start1, end1: Vector2, epsilon: f32 = ConstF32.Epsilon)->{ intersects: bool, point: Vector2 }
{
    var result: retval

    let {intersects, firstFactor, ?} = lineIntersectionFactors(start0, end0, start1, end1, epsilon)
    if not intersects do
        return result

    result.intersects = true
    result.point.x    = start0.x + firstFactor * (end0.x - start0.x)
    result.point.y    = start0.y + firstFactor * (end0.y - start0.y)
    return result
}

// Returns the point where the segment from `start0` to `end0` meets the segment from `start1` to `end1`.
//
// `intersects` reports whether the segments meet, and `point` is only meaningful when they do. `epsilon` is the
// tolerance of both the parallelism test and the segment ends, so segments that touch at an end
// intersect. Collinear segments that overlap report one end of their overlap, and a segment whose
// ends coincide is treated as a point.
func intersectSegments(start0, end0, start1, end1: Vector2, epsilon: f32 = ConstF32.Epsilon)->{ intersects: bool, point: Vector2 }
{
    var result: retval

    let r  = end0 - start0
    let s  = end1 - start1
    let qp = start1 - start0

    if Math.abs(r.cross(s)) < epsilon and Math.abs(qp.cross(r)) < epsilon
    {
        let epsilonSq = epsilon * epsilon

        if Math.isZeroEpsilon(r.lengthSquared(), epsilonSq)
        {
            if Math.isZeroEpsilon(s.lengthSquared(), epsilonSq)
            {
                result.intersects = start0.isEqualEpsilon(start1, epsilon)
                result.point      = start0
                return result
            }

            result.intersects = Math.isZeroEpsilon(distanceFromPointToSegment(start0, start1, end1), epsilon)
            result.point      = start0
            return result
        }

        if Math.isZeroEpsilon(s.lengthSquared(), epsilonSq)
        {
            result.intersects = Math.isZeroEpsilon(distanceFromPointToSegment(start1, start0, end0), epsilon)
            result.point      = start1
            return result
        }

        var a0, a1, b0, b1: f32
        if Math.abs(r.x) >= Math.abs(r.y)
        {
            a0 = start0.x
            a1 = end0.x
            b0 = start1.x
            b1 = end1.x
        }
        else
        {
            a0 = start0.y
            a1 = end0.y
            b0 = start1.y
            b1 = end1.y
        }

        if a1 < a0
        {
            let tmp = a0
            a0 = a1
            a1 = tmp
        }

        if b1 < b0
        {
            let tmp = b0
            b0 = b1
            b1 = tmp
        }

        let overlapStart = Math.max(a0, b0)
        let overlapEnd   = Math.min(a1, b1)
        if overlapStart > overlapEnd + epsilon do
            return result

        let denom  = Math.abs(r.x) >= Math.abs(r.y) ? r.x : r.y
        let origin = Math.abs(r.x) >= Math.abs(r.y) ? start0.x : start0.y
        let t      = (overlapStart - origin) / denom

        result.intersects = true
        result.point      = start0 + r * t
        return result
    }

    let {intersects, firstFactor, secondFactor} = lineIntersectionFactors(start0, end0, start1, end1, epsilon)
    if not intersects do
        return result

    if firstFactor < -epsilon or firstFactor > 1 + epsilon or secondFactor < -epsilon or secondFactor > 1 + epsilon do
        return result

    result.intersects = true
    result.point.x    = start0.x + firstFactor * (end0.x - start0.x)
    result.point.y    = start0.y + firstFactor * (end0.y - start0.y)
    return result
}

// Returns whether `point` lies inside the polygon whose vertices are `polygon`, in order.
//
// The last vertex connects back to the first, and a self-intersecting polygon follows the
// even-odd rule. A point exactly on an edge may land on either side, and an empty polygon
// contains nothing. This is the PNPoly algorithm by W. Randolph Franklin.
func polygonContainsPoint(polygon: Array'Math.Vector2, point: Math.Vector2)->bool
{
    if polygon.isEmpty() do
        return false

    // A horizontal ray leaving the point crosses the outline an odd number of times exactly
    // when the point is inside, so every crossed edge flips the answer.
    var contains = false
    var previous = polygon.count - 1
    for index in polygon.count
    {
        let vi = polygon[index]
        let vj = polygon[previous]
        if ((vi.y > point.y) != (vj.y > point.y)) and
           (point.x < (vj.x - vi.x) * (point.y - vi.y) / (vj.y - vi.y) + vi.x)
        {
            contains = not contains
        }

        previous = index
    }

    return contains
}
