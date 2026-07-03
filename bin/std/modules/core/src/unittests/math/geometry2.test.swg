#global #if #command == Swag.CompilerCommand.Test
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
    @assert(Math.Geometry.isInEllipse(Math.Vector2{10, 20}, center, 5, 10))
    @assert(Math.Geometry.isInEllipse(Math.Vector2{15, 20}, center, 5, 10))
    @assert(Math.Geometry.isInEllipse(Math.Vector2{10, 30}, center, 5, 10))
    @assert(Math.Geometry.isInEllipse(Math.Vector2{13, 24}, center, 5, 10))
    @assert(!Math.Geometry.isInEllipse(Math.Vector2{15.1, 20}, center, 5, 10))
    @assert(!Math.Geometry.isInEllipse(Math.Vector2{10, 30.1}, center, 5, 10))
    @assert(!Math.Geometry.isInEllipse(Math.Vector2{14, 28}, center, 5, 10))
}

#test
{
    let a = Math.Vector2{0, 0}
    let b = Math.Vector2{10, 0}
    let c = Math.Vector2{0, 10}

    @assert(Math.Geometry.isInTriangle(Math.Vector2{1, 1}, a, b, c))
    @assert(Math.Geometry.isInTriangle(a, a, b, c))
    @assert(Math.Geometry.isInTriangle(Math.Vector2{5, 0}, a, b, c))
    @assert(Math.Geometry.isInTriangle(Math.Vector2{0, 5}, a, b, c))
    @assert(Math.Geometry.isInTriangle(Math.Vector2{5, 5}, a, b, c))
    @assert(!Math.Geometry.isInTriangle(Math.Vector2{6, 5}, a, b, c))
    @assert(!Math.Geometry.isInTriangle(Math.Vector2{-1, 1}, a, b, c))

    @assert(Math.Geometry.isInTriangle(Math.Vector2{1, 1}, a, c, b))
    @assert(!Math.Geometry.isInTriangle(Math.Vector2{6, 5}, a, c, b))
}

#test
{
    let a = Math.Vector2{0, 0}
    let b = Math.Vector2{10, 0}

    expectNear(Math.Geometry.distanceToLine(Math.Vector2{5, 3}, a, b), 3)
    expectNear(Math.Geometry.distanceToLine(Math.Vector2{-5, 4}, a, b), 4)
    expectNear(Math.Geometry.distanceToLine(Math.Vector2{5, 0}, a, b), 0)
    expectNear(Math.Geometry.distanceToLine(Math.Vector2{3, 4}, a, a), 5)

    expectNear(Math.Geometry.distanceToSegment(Math.Vector2{5, 3}, a, b), 3)
    expectNear(Math.Geometry.distanceToSegment(Math.Vector2{-3, 4}, a, b), 5)
    expectNear(Math.Geometry.distanceToSegment(Math.Vector2{13, 4}, a, b), 5)
    expectNear(Math.Geometry.distanceToSegment(Math.Vector2{5, 0}, a, b), 0)
    expectNear(Math.Geometry.distanceToSegment(Math.Vector2{3, 4}, a, a), 5)
}

#test
{
    let cross = Math.Geometry.nearestPointsSegSeg(Math.Vector2{0, 0}, Math.Vector2{10, 0}, Math.Vector2{5, -5}, Math.Vector2{5, 5})
    expectVec2(cross.a, Math.Vector2{5, 0})
    expectVec2(cross.b, Math.Vector2{5, 0})
    expectNear(cross.dist, 0)

    let separated = Math.Geometry.nearestPointsSegSeg(Math.Vector2{0, 0}, Math.Vector2{10, 0}, Math.Vector2{12, 3}, Math.Vector2{12, 8})
    expectVec2(separated.a, Math.Vector2{10, 0})
    expectVec2(separated.b, Math.Vector2{12, 3})
    expectNear(separated.dist, Math.sqrt(13'f32))

    let parallel = Math.Geometry.nearestPointsSegSeg(Math.Vector2{0, 0}, Math.Vector2{10, 0}, Math.Vector2{2, 3}, Math.Vector2{8, 3})
    expectVec2(parallel.a, Math.Vector2{2, 0})
    expectVec2(parallel.b, Math.Vector2{2, 3})
    expectNear(parallel.dist, 3)
}

#test
{
    let lineCross = Math.Geometry.lineLineIntersect(Math.Vector2{0, 0}, Math.Vector2{10, 10}, Math.Vector2{0, 10}, Math.Vector2{10, 0})
    @assert(lineCross.yes)
    expectVec2(lineCross.pos, Math.Vector2{5, 5})

    let lineParallel = Math.Geometry.lineLineIntersect(Math.Vector2{0, 0}, Math.Vector2{10, 0}, Math.Vector2{0, 1}, Math.Vector2{10, 1})
    @assert(!lineParallel.yes)

    let lineCollinear = Math.Geometry.lineLineIntersect(Math.Vector2{0, 0}, Math.Vector2{10, 0}, Math.Vector2{2, 0}, Math.Vector2{8, 0})
    @assert(lineCollinear.yes)
    expectVec2(lineCollinear.pos, Math.Vector2{0, 0})
}

#test
{
    let cross = Math.Geometry.segSegIntersect(Math.Vector2{0, 0}, Math.Vector2{10, 10}, Math.Vector2{0, 10}, Math.Vector2{10, 0})
    @assert(cross.yes)
    expectVec2(cross.pos, Math.Vector2{5, 5})

    let touch = Math.Geometry.segSegIntersect(Math.Vector2{0, 0}, Math.Vector2{10, 0}, Math.Vector2{10, 0}, Math.Vector2{10, 5})
    @assert(touch.yes)
    expectVec2(touch.pos, Math.Vector2{10, 0})

    let outside = Math.Geometry.segSegIntersect(Math.Vector2{0, 0}, Math.Vector2{1, 1}, Math.Vector2{2, 0}, Math.Vector2{2, 4})
    @assert(!outside.yes)

    let parallel = Math.Geometry.segSegIntersect(Math.Vector2{0, 0}, Math.Vector2{10, 0}, Math.Vector2{0, 1}, Math.Vector2{10, 1})
    @assert(!parallel.yes)

    let collinearOverlap = Math.Geometry.segSegIntersect(Math.Vector2{0, 0}, Math.Vector2{10, 0}, Math.Vector2{4, 0}, Math.Vector2{12, 0})
    @assert(collinearOverlap.yes)
    expectVec2(collinearOverlap.pos, Math.Vector2{4, 0})

    let collinearDisjoint = Math.Geometry.segSegIntersect(Math.Vector2{0, 0}, Math.Vector2{10, 0}, Math.Vector2{12, 0}, Math.Vector2{15, 0})
    @assert(!collinearDisjoint.yes)
}
