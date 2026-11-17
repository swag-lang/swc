#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

func expectVec3(actual, expected: Math.Vector3, eps = 0.001)
{
    Swag.require(actual.isEqualEpsilon(expected, eps))
}

func expectNear(actual, expected: f32)
{
    Swag.require(Math.isEqualEpsilon(actual, expected, 0.001))
}

#test
{
    let view       = Math.Matrix4x4.createLookAt({0, 0, 5}, {0, 0, 0}, Math.Vector3.UnitY)
    let projection = Math.Matrix4x4.createPerspective(Math.ConstF32.PiBy2, 1, 1, 10)
    let frustum    = Math.Geometry.Frustum3.fromMatrix(view.multiplied(projection))
    Swag.require(frustum.contains({0, 0, 0}))
    Swag.require(not frustum.contains({0, 0, 5}))
    Swag.require(not frustum.contains({20, 0, 0}))
    Swag.require(not frustum.contains({0, 0, 4.5}))
    Swag.require(not frustum.contains({0, 0, -6}))
    Swag.require(frustum.intersects(Math.Geometry.Bounds3{{-0.5, -0.5, -0.5}, {0.5, 0.5, 0.5}}))
    Swag.require(not frustum.intersects(Math.Geometry.Bounds3{{19, -1, -1}, {21, 1, 1}}))
}

#test
{
    let transform = Math.Transform3{
        {1, 0, 0}, Math.Quaternion.fromAxisAngle(Math.Vector3.UnitZ, Math.ConstF32.PiBy2), {2, 1, 1}}
    let point = transform.transformPoint({1, 0, 0})
    expectVec3(point, {1, 2, 0})
    expectVec3(transform.inverseTransformPoint(point), {1, 0, 0})
    expectVec3(transform.transformDirection({1, 0, 0}), {0, 2, 0})
    expectVec3(transform.transformNormal({1, 1, 0}), {-1, 0.5, 0})
    expectVec3(transform.toMatrix4x4().transformPoint({1, 0, 0}), point)
}

#test
{
    let quarterTurn = Math.Quaternion.fromAxisAngle(Math.Vector3.UnitZ, Math.ConstF32.PiBy2)
    expectVec3(quarterTurn.rotate(Math.Vector3.UnitX), Math.Vector3.UnitY)
    let eulerTurn = Math.Quaternion.fromEulerXYZ({0, 0, Math.ConstF32.PiBy2})
    expectVec3(eulerTurn.rotate(Math.Vector3.UnitX), Math.Vector3.UnitY)
    expectVec3(quarterTurn.toMatrix4x4().transformDirection(Math.Vector3.UnitX), Math.Vector3.UnitY)
    expectVec3(quarterTurn.inverse().rotate(Math.Vector3.UnitY), Math.Vector3.UnitX)
    expectNear(quarterTurn.length(), 1)
    expectVec3(Math.Quaternion.fromToRotation(Math.Vector3.UnitX, Math.Vector3.NegUnitX).rotate(Math.Vector3.UnitX), Math.Vector3.NegUnitX)
    let axisAngle = quarterTurn.toAxisAngle()
    expectVec3(axisAngle.axis, Math.Vector3.UnitZ)
    expectNear(axisAngle.angle, Math.ConstF32.PiBy2)
    expectVec3(Math.Quaternion.Identity.rotate({1, 2, 3}), {1, 2, 3})
    expectVec3(Math.Quaternion{0, 0, 0, 0}.normalized().rotate({2, 3, 4}), {2, 3, 4})
    let invalidRotation = Math.Quaternion{Swag.F32.NaN, 0, 0, 1}
    let safeRotation    = invalidRotation.normalized()
    Swag.require(safeRotation.x == 0 and safeRotation.y == 0 and safeRotation.z == 0 and safeRotation.w == 1)
    Swag.require(Math.isNaN(invalidRotation.length()))
    let infiniteRotation = Math.Quaternion{Swag.F32.Inf, 0, 0, 1}.inverse()
    Swag.require(infiniteRotation.x == 0 and
                 infiniteRotation.y == 0 and
                 infiniteRotation.z == 0 and
                 infiniteRotation.w == 1)

    let halfTurn = Math.Quaternion.fromAxisAngle(Math.Vector3.UnitY, Math.ConstF32.Pi - 0.01)
    let middle   = Math.Quaternion.slerp(Math.Quaternion.Identity, halfTurn, 0.5)
    expectVec3(middle.rotate(Math.Vector3.UnitZ), Math.Vector3.UnitX, 0.01)

    let first  = Math.Quaternion.fromAxisAngle(Math.Vector3.UnitZ, Math.ConstF32.PiBy2)
    let second = Math.Quaternion.fromAxisAngle(Math.Vector3.UnitX, Math.ConstF32.PiBy2)
    expectVec3(first.multiply(second).rotate(Math.Vector3.UnitY), {0, 0, 1})
    expectVec3((first * second).rotate(Math.Vector3.UnitY), {0, 0, 1})
}

#test
{
    let plane         = Math.Geometry.Plane3.fromPointNormal({0, 2, 0}, Math.Vector3.UnitY)
    let throughPoints = Math.Geometry.Plane3.fromPoints({0, 2, 0}, {0, 2, 1}, {1, 2, 0})
    expectVec3(throughPoints.normal, Math.Vector3.UnitY)
    expectNear(throughPoints.distance, 2)
    expectNear(plane.signedDistanceTo({0, 5, 0}), 3)
    Swag.require(Math.Geometry.Sphere3{{0, 2.5, 0}, 0.5}.intersects(plane))
    Swag.require(not Math.Geometry.Sphere3{{0, 2.6, 0}, 0.5}.intersects(plane))
    expectVec3(plane.project({2, 5, 4}), {2, 2, 4})
    let planeHit = plane.intersect(Math.Geometry.Ray3{{0, 0, 0}, {0, 1, 0}})
    Swag.require(planeHit.intersects)
    expectNear(planeHit.distance, 2)
    expectVec3(planeHit.point, {0, 2, 0})
    Swag.require(not plane.intersect(Math.Geometry.Ray3{{0, 0, 0}, {1, 0, 0}}).intersects)
    Swag.require(not plane.intersect(Math.Geometry.Ray3{{0, 3, 0}, {0, 1, 0}}).intersects)

    let ray = Math.Geometry.Ray3{{1, 0, 0}, {0, 2, 0}}
    expectVec3(ray.closestPoint({3, 5, 0}), {1, 5, 0})
    expectNear(ray.distanceSquaredTo({3, 5, 0}), 4)
    expectVec3(ray.closestPoint({1, -2, 0}), ray.origin)
    expectVec3(Math.Geometry.Ray3{{1, 2, 3}, Math.Vector3.Zero}.closestPoint({9, 9, 9}), {1, 2, 3})
}

#test
{
    var bounds = Math.Geometry.Bounds3.createEmpty()
    Swag.require(not bounds.isValid())
    bounds.includePoint({-1, -2, -3})
    bounds.includePoint({1, 2, 3})
    Swag.require(bounds.isValid())
    expectVec3(bounds.size(), {2, 4, 6})
    expectVec3(bounds.center(), Math.Vector3.Zero)
    expectVec3(bounds.extents(), {1, 2, 3})
    expectNear(bounds.volume(), 48)
    expectNear(bounds.surfaceArea(), 88)
    Swag.require(bounds.contains({0, 0, 0}))
    Swag.require(not bounds.contains({2, 0, 0}))
    expectVec3(bounds.closestPoint({2, 0, 4}), {1, 0, 3})
    Swag.require(bounds.intersects(Math.Geometry.Bounds3{{1, 2, 3}, {4, 5, 6}}))
    Swag.require(not bounds.intersects(Math.Geometry.Bounds3{{1.1, 2, 3}, {4, 5, 6}}))
    Swag.require(bounds.intersects(Math.Geometry.Plane3.fromPointNormal({0, 0, 0}, Math.Vector3.UnitX)))
    Swag.require(not bounds.intersects(Math.Geometry.Plane3.fromPointNormal({2, 0, 0}, Math.Vector3.UnitX)))
    let merged = bounds.merged(Math.Geometry.Bounds3{{4, 0, 0}, {5, 1, 1}})
    expectVec3(merged.min, {-1, -2, -3})
    expectVec3(merged.max, {5, 2, 3})
    let sphere = Math.Geometry.Sphere3{{0, 0, 0}, 2}
    Swag.require(sphere.contains({1, 1, 0}))
    Swag.require(not sphere.contains({2, 2, 0}))
    expectVec3(sphere.closestPoint({3, 0, 0}), {2, 0, 0})
    expectVec3(sphere.closestPoint({1, 0, 0}), {1, 0, 0})
    Swag.require(sphere.intersects(Math.Geometry.Sphere3{{3, 0, 0}, 1}))
    Swag.require(not sphere.intersects(Math.Geometry.Sphere3{{3.1, 0, 0}, 1}))
    Swag.require(sphere.intersects(bounds))
    Swag.require(bounds.intersects(sphere))
    Swag.require(not sphere.intersects(Math.Geometry.Bounds3{{3, 3, 3}, {4, 4, 4}}))

    let hit = bounds.intersect(Math.Geometry.Ray3{{-4, 0, 0}, {1, 0, 0}})
    Swag.require(hit.intersects)
    expectNear(hit.distance, 3)
    expectVec3(hit.point, {-1, 0, 0})
    let insideHit = bounds.intersect(Math.Geometry.Ray3{{0, 0, 0}, {0, 2, 0}})
    Swag.require(insideHit.intersects)
    expectNear(insideHit.distance, 1)
    expectVec3(insideHit.point, {0, 2, 0})
    let stationaryInside = bounds.intersect(Math.Geometry.Ray3{{0, 0, 0}, Math.Vector3.Zero})
    Swag.require(stationaryInside.intersects and stationaryInside.distance == 0)
    expectVec3(stationaryInside.point, {0, 0, 0})
    Swag.require(not bounds.intersect(Math.Geometry.Ray3{{4, 0, 0}, Math.Vector3.Zero}).intersects)
    Swag.require(not bounds.intersect(Math.Geometry.Ray3{{-4, 4, 0}, {1, 0, 0}}).intersects)
}

#test
{
    let sphereHit = Math.Geometry.intersectRaySphere(Math.Geometry.Ray3{{0, 0, -3}, {0, 0, 1}}, {0, 0, 0}, 1)
    Swag.require(sphereHit.intersects)
    expectNear(sphereHit.distance, 2)
    expectVec3(sphereHit.point, {0, 0, -1})
    let sphereExit = Math.Geometry.intersectRaySphere(Math.Geometry.Ray3{{0, 0, 0}, {0, 0, 1}}, {0, 0, 0}, 1)
    Swag.require(sphereExit.intersects)
    expectNear(sphereExit.distance, 1)
    Swag.require(not Math.Geometry.intersectRaySphere(Math.Geometry.Ray3{{0, 0, -3}, {0, 0, -1}}, {0, 0, 0}, 1).intersects)

    let triangleHit = Math.Geometry.intersectRayTriangle(Math.Geometry.Ray3{{0.25, 0.25, -1}, {0, 0, 1}},
                                                         {0, 0, 0},
                                                         {1, 0, 0},
                                                         {0, 1, 0})
    Swag.require(triangleHit.intersects)
    expectNear(triangleHit.distance, 1)
    expectVec3(triangleHit.barycentric, {0.5, 0.25, 0.25})
    expectVec3(triangleHit.point, {0.25, 0.25, 0})
    Swag.require(not Math.Geometry.intersectRayTriangle(Math.Geometry.Ray3{{2, 2, -1}, {0, 0, 1}},
                                                        {0, 0, 0},
                                                        {1, 0, 0},
                                                        {0, 1, 0}).intersects)
}
