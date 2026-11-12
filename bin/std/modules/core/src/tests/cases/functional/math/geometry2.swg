#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

func expectVec2(actual, expected: Math.Vector2)
{
    Swag.require(actual.isEqualEpsilon(expected, 0.001))
}

func expectNear(actual, expected: f32)
{
    Swag.require(Math.isEqualEpsilon(actual, expected, 0.001))
}

#test
{
    let center = Math.Vector2{10, 20}
    Swag.require(Math.Geometry.ellipseContainsPoint({10, 20}, center, 5, 10))
    Swag.require(Math.Geometry.ellipseContainsPoint({15, 20}, center, 5, 10))
    Swag.require(Math.Geometry.ellipseContainsPoint({10, 30}, center, 5, 10))
    Swag.require(Math.Geometry.ellipseContainsPoint({13, 24}, center, 5, 10))
    Swag.require(not Math.Geometry.ellipseContainsPoint({15.1, 20}, center, 5, 10))
    Swag.require(not Math.Geometry.ellipseContainsPoint({10, 30.1}, center, 5, 10))
    Swag.require(not Math.Geometry.ellipseContainsPoint({14, 28}, center, 5, 10))
}

#test
{
    let a = Math.Vector2{0, 0}
    let b = Math.Vector2{10, 0}
    let c = Math.Vector2{0, 10}

    Swag.require(Math.Geometry.triangleContainsPoint({1, 1}, a, b, c))
    Swag.require(Math.Geometry.triangleContainsPoint(a, a, b, c))
    Swag.require(Math.Geometry.triangleContainsPoint({5, 0}, a, b, c))
    Swag.require(Math.Geometry.triangleContainsPoint({0, 5}, a, b, c))
    Swag.require(Math.Geometry.triangleContainsPoint({5, 5}, a, b, c))
    Swag.require(not Math.Geometry.triangleContainsPoint({6, 5}, a, b, c))
    Swag.require(not Math.Geometry.triangleContainsPoint({-1, 1}, a, b, c))

    Swag.require(Math.Geometry.triangleContainsPoint({1, 1}, a, c, b))
    Swag.require(not Math.Geometry.triangleContainsPoint({6, 5}, a, c, b))
}

#test
{
    let a = Math.Vector2{0, 0}
    let b = Math.Vector2{5, 0}
    let c = Math.Vector2{10, 0}

    Swag.require(Math.Geometry.triangleContainsPoint({7, 0}, a, b, c))
    Swag.require(not Math.Geometry.triangleContainsPoint({7, 1}, a, b, c))
    Swag.require(not Math.Geometry.triangleContainsPoint({11, 0}, a, b, c))
    Swag.require(Math.Geometry.triangleContainsPoint(a, a, a, a))
    Swag.require(not Math.Geometry.triangleContainsPoint({4, 4}, a, a, a))
}

#test
{
    let a = Math.Vector2{0, 0}
    let b = Math.Vector2{10, 0}

    expectNear(Math.Geometry.distanceFromPointToLine({5, 3}, a, b), 3)
    expectNear(Math.Geometry.distanceFromPointToLine({-5, 4}, a, b), 4)
    expectNear(Math.Geometry.distanceFromPointToLine({5, 0}, a, b), 0)
    expectNear(Math.Geometry.distanceFromPointToLine({3, 4}, a, a), 5)

    expectNear(Math.Geometry.distanceFromPointToSegment({5, 3}, a, b), 3)
    expectNear(Math.Geometry.distanceFromPointToSegment({-3, 4}, a, b), 5)
    expectNear(Math.Geometry.distanceFromPointToSegment({13, 4}, a, b), 5)
    expectNear(Math.Geometry.distanceFromPointToSegment({5, 0}, a, b), 0)
    expectNear(Math.Geometry.distanceFromPointToSegment({3, 4}, a, a), 5)
}

#test
{
    let cross = Math.Geometry.closestPointsBetweenSegments({0, 0}, {10, 0}, {5, -5}, {5, 5})
    expectVec2(cross.first, {5, 0})
    expectVec2(cross.second, {5, 0})
    expectNear(cross.distance, 0)

    let separated = Math.Geometry.closestPointsBetweenSegments({0, 0}, {10, 0}, {12, 3}, {12, 8})
    expectVec2(separated.first, {10, 0})
    expectVec2(separated.second, {12, 3})
    expectNear(separated.distance, Math.sqrt(13'f32))

    let sideBySide = Math.Geometry.closestPointsBetweenSegments({0, 0}, {10, 0}, {2, 3}, {8, 3})
    expectVec2(sideBySide.first, {2, 0})
    expectVec2(sideBySide.second, {2, 3})
    expectNear(sideBySide.distance, 3)

    let pointAndSegment = Math.Geometry.closestPointsBetweenSegments({2, 2}, {2, 2}, {0, 0}, {4, 0})
    expectVec2(pointAndSegment.first, {2, 2})
    expectVec2(pointAndSegment.second, {2, 0})
    expectNear(pointAndSegment.distance, 2)

    let segmentAndPoint = Math.Geometry.closestPointsBetweenSegments({0, 0}, {4, 0}, {2, 2}, {2, 2})
    expectVec2(segmentAndPoint.first, {2, 0})
    expectVec2(segmentAndPoint.second, {2, 2})
    expectNear(segmentAndPoint.distance, 2)

    let twoPoints = Math.Geometry.closestPointsBetweenSegments({1, 2}, {1, 2}, {4, 6}, {4, 6})
    expectVec2(twoPoints.first, {1, 2})
    expectVec2(twoPoints.second, {4, 6})
    expectNear(twoPoints.distance, 5)

    let reversedPoints = Math.Geometry.closestPointsBetweenSegments({4, 6}, {4, 6}, {1, 2}, {1, 2})
    expectVec2(reversedPoints.first, {4, 6})
    expectVec2(reversedPoints.second, {1, 2})
    expectNear(reversedPoints.distance, 5)
}

#test
{
    let lineCross = Math.Geometry.intersectLines({0, 0}, {10, 10}, {0, 10}, {10, 0})
    Swag.require(lineCross.intersects)
    expectVec2(lineCross.point, {5, 5})

    let lineParallel = Math.Geometry.intersectLines({0, 0}, {10, 0}, {0, 1}, {10, 1})
    Swag.require(not lineParallel.intersects)

    let lineCollinear = Math.Geometry.intersectLines({0, 0}, {10, 0}, {2, 0}, {8, 0})
    Swag.require(not lineCollinear.intersects)
}

#test
{
    let cross = Math.Geometry.intersectSegments({0, 0}, {10, 10}, {0, 10}, {10, 0})
    Swag.require(cross.intersects)
    expectVec2(cross.point, {5, 5})

    let touch = Math.Geometry.intersectSegments({0, 0}, {10, 0}, {10, 0}, {10, 5})
    Swag.require(touch.intersects)
    expectVec2(touch.point, {10, 0})

    let outside = Math.Geometry.intersectSegments({0, 0}, {1, 1}, {2, 0}, {2, 4})
    Swag.require(not outside.intersects)

    let sideBySide = Math.Geometry.intersectSegments({0, 0}, {10, 0}, {0, 1}, {10, 1})
    Swag.require(not sideBySide.intersects)

    let collinearOverlap = Math.Geometry.intersectSegments({0, 0}, {10, 0}, {4, 0}, {12, 0})
    Swag.require(collinearOverlap.intersects)
    expectVec2(collinearOverlap.point, {4, 0})

    let collinearDisjoint = Math.Geometry.intersectSegments({0, 0}, {10, 0}, {12, 0}, {15, 0})
    Swag.require(not collinearDisjoint.intersects)

    let pointOnSegment = Math.Geometry.intersectSegments({2, 0}, {2, 0}, {0, 0}, {4, 0})
    Swag.require(pointOnSegment.intersects)
    expectVec2(pointOnSegment.point, {2, 0})

    let pointOutside = Math.Geometry.intersectSegments({5, 1}, {5, 1}, {0, 0}, {4, 0})
    Swag.require(not pointOutside.intersects)

    let samePoint = Math.Geometry.intersectSegments({3, 4}, {3, 4}, {3, 4}, {3, 4})
    Swag.require(samePoint.intersects)
    expectVec2(samePoint.point, {3, 4})

    let separatePoints = Math.Geometry.intersectSegments({3, 4}, {3, 4}, {6, 8}, {6, 8})
    Swag.require(not separatePoints.intersects)
}

// Horizontal edges do not divide by zero, and winding does not change inside/outside.
#test
{
    var polygon: Array'Math.Vector2
    Swag.require(not Math.Geometry.polygonContainsPoint(polygon, {5, 5}))

    polygon.add({0, 0})
    polygon.add({10, 0})
    polygon.add({10, 10})
    polygon.add({0, 10})
    Swag.require(Math.Geometry.polygonContainsPoint(polygon, {5, 5}))
    Swag.require(not Math.Geometry.polygonContainsPoint(polygon, {15, 5}))
    Swag.require(not Math.Geometry.polygonContainsPoint(polygon, {5, -1}))

    Slice.reverse(polygon.toSlice())
    Swag.require(Math.Geometry.polygonContainsPoint(polygon, {5, 5}))
    Swag.require(not Math.Geometry.polygonContainsPoint(polygon, {15, 5}))
}
