#global namespace Math
#global namespace Geometry
#global public

// Test if a point is inside an ellipse.
// Uses the standard ellipse equation: (x-cx)²/rx² + (y-cy)²/ry² ≤ 1.
func ellipseContainsPoint(point, center: Vector2, radiusX, radiusY: f32)->bool
{
    Debug.assert(radiusX > 0 and radiusY > 0)
    return (pow((point.x - center.x), 2) / pow(radiusX, 2)) + (pow((point.y - center.y), 2) / pow(radiusY, 2)) <= 1
}

// Test if a point is inside a triangle using cross product method.
// Uses barycentric coordinates by checking if all cross products have the same sign.
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

    let aCROSSbp = ax * bpy - ay * bpx
    let cCROSSap = cx * apy - cy * apx
    let bCROSScp = bx * cpy - by * cpx

    return ((aCROSSbp >= 0) and (bCROSScp >= 0) and (cCROSSap >= 0)) or ((aCROSSbp <= 0) and (bCROSScp <= 0) and (cCROSSap <= 0))
}

// Calculate the perpendicular distance from a point to an infinite line.
// Projects the point onto the line and returns the distance to the projection.
func distanceFromPointToLine(point, lineStart, lineEnd: Vector2)->f32
{
    let toPt = point - lineStart
    var seg  = lineEnd - lineStart
    seg.normalizeOrZero()
    let dot = toPt.dot(seg)
    seg *= dot
    let cross = toPt - seg
    return cross.length()
}

// Calculate the shortest distance from a point to a line segment.
// Handles endpoints by clamping the projection to the segment bounds.
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

    let x1  = ab.x
    let y1  = ab.y
    let x2  = ae.x
    let y2  = ae.y
    let mod = Math.sqrt(x1 * x1 + y1 * y1)
    return Math.abs(x1 * y2 - y1 * x2) / mod
}

// Find the closest points between two line segments and their distance.
// Implementation based on David Eberly's Geometric Tools library algorithm.
//
// ---
// David Eberly, Geometric Tools, Redmond WA 98052
// Copyright (c) 1998-2022
// Distributed under the Boost Software License, Version 1.0.
// https://www.boost.org/LICENSE_1_0.txt
// https://www.geometrictools.com/License/Boost/LICENSE_1_0.txt
// https://www.geometrictools.com/Documentation/DistanceSegments3D.pdf
// https://www.geometrictools.com/GTE/Mathematics/DistSegmentSegment.h
// ---
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

    var s, t: f32 = undefined
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

// Calculate intersection coefficients for two infinite lines.
// Returns parametric coefficients 'd0' and 'd1' where intersection = start + d * (end - start).
private func lineIntersectionFactors(start0, end0, start1, end1: Vector2, epsilon: f32)->{ intersects: bool, firstFactor: f32, secondFactor: f32 }
{
    var result: retval

    let ua = (end1.x - start1.x) * (start0.y - start1.y) - (end1.y - start1.y) * (start0.x - start1.x)
    let ub = (end0.x - start0.x) * (start0.y - start1.y) - (end0.y - start0.y) * (start0.x - start1.x)
    let d  = (end1.y - start1.y) * (end0.x - start0.x) - (end1.x - start1.x) * (end0.y - start0.y)

    // Parallel lines
    if Math.abs(d) < epsilon
    {
        return result
    }

    result.intersects   = true
    result.firstFactor  = ua / d
    result.secondFactor = ub / d
    return result
}

// Find the intersection point of two infinite lines.
// Returns the intersection point if lines are not parallel, otherwise returns failure.
func intersectLines(start0, end0, start1, end1: Vector2, epsilon: f32 = ConstF32.Epsilon)->{ intersects: bool, point: Vector2 }
{
    var result: retval

    let {intersects, firstFactor, ?} = lineIntersectionFactors(start0, end0, start1, end1, epsilon)
    if !intersects do
        return result

    result.intersects = true
    result.point.x    = start0.x + firstFactor * (end0.x - start0.x)
    result.point.y    = start0.y + firstFactor * (end0.y - start0.y)
    return result
}

// Find the intersection point of two line segments.
// Returns the intersection point only if it lies within both segment bounds.
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

        var a0, a1, b0, b1: f32 = undefined
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
    if !intersects do
        return result

    if firstFactor < -epsilon or firstFactor > 1 + epsilon or secondFactor < -epsilon or secondFactor > 1 + epsilon do
        return result

    result.intersects = true
    result.point.x    = start0.x + firstFactor * (end0.x - start0.x)
    result.point.y    = start0.y + firstFactor * (end0.y - start0.y)
    return result
}

// Test if a point is inside a polygon using ray casting algorithm.
// Implementation of the PNPoly algorithm by W. Randolph Franklin.
func polygonContainsPoint(polygon: Array'Math.Vector2, point: Math.Vector2)->bool
{
    var contains = false
    if !polygon.count do
        return contains
    let buffer = notnull polygon.buffer
    var verti  = buffer
    var vertj  = buffer + cast(s32) polygon.count - 1
    for polygon.count
    {
        if ((verti.y > point.y) != (vertj.y > point.y)) and
           (point.x < (vertj.x - verti.x) * (point.y - verti.y) / (vertj.y - verti.y) + verti.x)
        {
            contains = !contains
        }

        vertj = verti
        verti += 1
    }

    return contains
}
