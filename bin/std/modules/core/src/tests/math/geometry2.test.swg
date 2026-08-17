#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

func expectVec2(actual, expected: Math.Vector2)
{
    @assert(actual.isEqualEpsilon(expected, 0.001))
}

func expectNear(actual, expected: f32)
{
    @assert(Math.isEqualEpsilon(actual, expected, 0.001))
}

#test
{
    let center = Math.Vector2{10, 20}
    @assert(Math.Geometry.ellipseContainsPoint(Math.Vector2{10, 20}, center, 5, 10))
    @assert(Math.Geometry.ellipseContainsPoint(Math.Vector2{15, 20}, center, 5, 10))
    @assert(Math.Geometry.ellipseContainsPoint(Math.Vector2{10, 30}, center, 5, 10))
    @assert(Math.Geometry.ellipseContainsPoint(Math.Vector2{13, 24}, center, 5, 10))
    @assert(!Math.Geometry.ellipseContainsPoint(Math.Vector2{15.1, 20}, center, 5, 10))
    @assert(!Math.Geometry.ellipseContainsPoint(Math.Vector2{10, 30.1}, center, 5, 10))
    @assert(!Math.Geometry.ellipseContainsPoint(Math.Vector2{14, 28}, center, 5, 10))
}

#test
{
    let a = Math.Vector2{0, 0}
    let b = Math.Vector2{10, 0}
    let c = Math.Vector2{0, 10}

    @assert(Math.Geometry.triangleContainsPoint(Math.Vector2{1, 1}, a, b, c))
    @assert(Math.Geometry.triangleContainsPoint(a, a, b, c))
    @assert(Math.Geometry.triangleContainsPoint(Math.Vector2{5, 0}, a, b, c))
    @assert(Math.Geometry.triangleContainsPoint(Math.Vector2{0, 5}, a, b, c))
    @assert(Math.Geometry.triangleContainsPoint(Math.Vector2{5, 5}, a, b, c))
    @assert(!Math.Geometry.triangleContainsPoint(Math.Vector2{6, 5}, a, b, c))
    @assert(!Math.Geometry.triangleContainsPoint(Math.Vector2{-1, 1}, a, b, c))

    @assert(Math.Geometry.triangleContainsPoint(Math.Vector2{1, 1}, a, c, b))
    @assert(!Math.Geometry.triangleContainsPoint(Math.Vector2{6, 5}, a, c, b))
}

#test
{
    let a = Math.Vector2{0, 0}
    let b = Math.Vector2{10, 0}

    expectNear(Math.Geometry.distanceFromPointToLine(Math.Vector2{5, 3}, a, b), 3)
    expectNear(Math.Geometry.distanceFromPointToLine(Math.Vector2{-5, 4}, a, b), 4)
    expectNear(Math.Geometry.distanceFromPointToLine(Math.Vector2{5, 0}, a, b), 0)
    expectNear(Math.Geometry.distanceFromPointToLine(Math.Vector2{3, 4}, a, a), 5)

    expectNear(Math.Geometry.distanceFromPointToSegment(Math.Vector2{5, 3}, a, b), 3)
    expectNear(Math.Geometry.distanceFromPointToSegment(Math.Vector2{-3, 4}, a, b), 5)
    expectNear(Math.Geometry.distanceFromPointToSegment(Math.Vector2{13, 4}, a, b), 5)
    expectNear(Math.Geometry.distanceFromPointToSegment(Math.Vector2{5, 0}, a, b), 0)
    expectNear(Math.Geometry.distanceFromPointToSegment(Math.Vector2{3, 4}, a, a), 5)
}

#test
{
    let cross = Math.Geometry.closestPointsBetweenSegments(Math.Vector2{0, 0}, Math.Vector2{10, 0}, Math.Vector2{5, -5}, Math.Vector2{5, 5})
    expectVec2(cross.first, Math.Vector2{5, 0})
    expectVec2(cross.second, Math.Vector2{5, 0})
    expectNear(cross.distance, 0)

    let separated = Math.Geometry.closestPointsBetweenSegments(Math.Vector2{0, 0}, Math.Vector2{10, 0}, Math.Vector2{12, 3}, Math.Vector2{12, 8})
    expectVec2(separated.first, Math.Vector2{10, 0})
    expectVec2(separated.second, Math.Vector2{12, 3})
    expectNear(separated.distance, Math.sqrt(13'f32))

    let parallel = Math.Geometry.closestPointsBetweenSegments(Math.Vector2{0, 0}, Math.Vector2{10, 0}, Math.Vector2{2, 3}, Math.Vector2{8, 3})
    expectVec2(parallel.first, Math.Vector2{2, 0})
    expectVec2(parallel.second, Math.Vector2{2, 3})
    expectNear(parallel.distance, 3)

    let pointAndSegment = Math.Geometry.closestPointsBetweenSegments(Math.Vector2{2, 2}, Math.Vector2{2, 2}, Math.Vector2{0, 0}, Math.Vector2{4, 0})
    expectVec2(pointAndSegment.first, Math.Vector2{2, 2})
    expectVec2(pointAndSegment.second, Math.Vector2{2, 0})
    expectNear(pointAndSegment.distance, 2)
}

#test
{
    let lineCross = Math.Geometry.intersectLines(Math.Vector2{0, 0}, Math.Vector2{10, 10}, Math.Vector2{0, 10}, Math.Vector2{10, 0})
    @assert(lineCross.intersects)
    expectVec2(lineCross.point, Math.Vector2{5, 5})

    let lineParallel = Math.Geometry.intersectLines(Math.Vector2{0, 0}, Math.Vector2{10, 0}, Math.Vector2{0, 1}, Math.Vector2{10, 1})
    @assert(!lineParallel.intersects)

    let lineCollinear = Math.Geometry.intersectLines(Math.Vector2{0, 0}, Math.Vector2{10, 0}, Math.Vector2{2, 0}, Math.Vector2{8, 0})
    @assert(!lineCollinear.intersects)
}

#test
{
    let cross = Math.Geometry.intersectSegments(Math.Vector2{0, 0}, Math.Vector2{10, 10}, Math.Vector2{0, 10}, Math.Vector2{10, 0})
    @assert(cross.intersects)
    expectVec2(cross.point, Math.Vector2{5, 5})

    let touch = Math.Geometry.intersectSegments(Math.Vector2{0, 0}, Math.Vector2{10, 0}, Math.Vector2{10, 0}, Math.Vector2{10, 5})
    @assert(touch.intersects)
    expectVec2(touch.point, Math.Vector2{10, 0})

    let outside = Math.Geometry.intersectSegments(Math.Vector2{0, 0}, Math.Vector2{1, 1}, Math.Vector2{2, 0}, Math.Vector2{2, 4})
    @assert(!outside.intersects)

    let parallel = Math.Geometry.intersectSegments(Math.Vector2{0, 0}, Math.Vector2{10, 0}, Math.Vector2{0, 1}, Math.Vector2{10, 1})
    @assert(!parallel.intersects)

    let collinearOverlap = Math.Geometry.intersectSegments(Math.Vector2{0, 0}, Math.Vector2{10, 0}, Math.Vector2{4, 0}, Math.Vector2{12, 0})
    @assert(collinearOverlap.intersects)
    expectVec2(collinearOverlap.point, Math.Vector2{4, 0})

    let collinearDisjoint = Math.Geometry.intersectSegments(Math.Vector2{0, 0}, Math.Vector2{10, 0}, Math.Vector2{12, 0}, Math.Vector2{15, 0})
    @assert(!collinearDisjoint.intersects)
}
