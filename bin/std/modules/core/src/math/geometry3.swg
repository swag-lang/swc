#global namespace Math
#global namespace Geometry
#global public

// A ray with an origin and a direction; points along it are `origin + direction * distance`.
#[Serialization.Final]
struct Ray3
{
    public origin:    Vector3     // Point where the ray begins.
    public direction: Vector3     // Direction scaled by the ray's parameterization.
}

impl Ray3
{
    // Returns the point at parameter `distance` along this ray.
    mtd const pointAt(distance: f32)->Vector3 => .origin + .direction * distance

    // Returns the nearest point on the forward ray to `point`.
    mtd const closestPoint(point: Vector3)->Vector3
    {
        let lengthSquared = .direction.lengthSquared()
        if lengthSquared == 0 do
            return .origin
        let parameter = Math.max(0'f32, (point - .origin).dot(.direction) / lengthSquared)
        return .pointAt(parameter)
    }

    // Returns the squared distance from `point` to the forward ray.
    mtd const distanceSquaredTo(point: Vector3)->f32 => .closestPoint(point).distanceSquaredTo(point)
}

// A plane represented by a unit normal and signed distance from the origin.
//
// Points on the plane satisfy `normal.dot(point) == distance`.
#[Serialization.Final]
struct Plane3
{
    public normal:   Vector3     // Unit normal that points toward the positive half-space.
    public distance: f32         // Signed origin offset: `normal.dot(point) == distance` on the plane.
}

impl Plane3
{
    // Creates a plane through `point` with the given normal; a zero normal produces the X plane.
    func fromPointNormal(point, normal: Vector3)->Plane3
    {
        let unitNormal = normal.normalizedOrZero()
        if unitNormal.isZero() do
            return Plane3{Vector3.UnitX, point.x}
        return Plane3{unitNormal, unitNormal.dot(point)}
    }

    // Creates the plane through three non-collinear points.
    func fromPoints(a, b, c: Vector3)->Plane3
    {
        let normal = (b - a).cross(c - a).normalizedOrZero()
        Swag.assert(not normal.isZero())
        return Plane3{normal, normal.dot(a)}
    }

    // Returns the signed distance of `point` from this plane.
    mtd const signedDistanceTo(point: Vector3)->f32 => .normal.dot(point) - .distance

    // Returns the orthogonal projection of `point` onto this plane.
    mtd const project(point: Vector3)->Vector3 => point - .normal * .signedDistanceTo(point)

    // Intersects this plane with a ray and returns whether the forward ray has a unique hit.
    //
    // `distance` is the ray parameter, so it is a world distance only for unit directions.
    mtd const intersect(ray: Ray3)->{ intersects: bool, distance: f32, point: Vector3 }
    {
        let denominator = .normal.dot(ray.direction)
        if denominator == 0 do
            return {intersects: false, distance: 0, point: ray.origin}
        let distance = (.distance - .normal.dot(ray.origin)) / denominator
        if distance < 0 do
            return {intersects: false, distance: distance, point: ray.pointAt(distance)}
        return {intersects: true, distance: distance, point: ray.pointAt(distance)}
    }
}

private func frustumPlane(coefficients: Vector4)->Plane3
{
    let normal = Vector3{coefficients.x, coefficients.y, coefficients.z}
    let length = normal.length()
    Swag.assert(length > 0)
    return Plane3{normal / length, -coefficients.w / length}
}

// A sphere described by its center and nonnegative radius.
#[Serialization.Final]
struct Sphere3
{
    public center: Vector3     // Center of the sphere.
    public radius: f32         // Radius; callers must keep it nonnegative.
}

impl Sphere3
{
    // Returns the nearest point in this sphere to `point`.
    mtd const closestPoint(point: Vector3)->Vector3
    {
        Swag.assert(.radius >= 0)
        let offset = point - .center
        let distanceSquared = offset.lengthSquared()
        if distanceSquared <= .radius * .radius or distanceSquared == 0 do
            return point
        return .center + offset * (.radius / sqrt(distanceSquared))
    }

    // Returns whether `point` lies inside or on this sphere.
    mtd const contains(point: Vector3)->bool
    {
        Swag.assert(.radius >= 0)
        return .center.distanceSquaredTo(point) <= .radius * .radius
    }

    // Returns whether this sphere overlaps `other`, including tangency.
    mtd const intersects(other: Sphere3)->bool
    {
        Swag.assert(.radius >= 0 and other.radius >= 0)
        let radius = .radius + other.radius
        return .center.distanceSquaredTo(other.center) <= radius * radius
    }

    // Returns whether this sphere overlaps `bounds`, including tangency.
    mtd const intersects(bounds: Bounds3)->bool
    {
        Swag.assert(.radius >= 0)
        if not bounds.isValid() do
            return false
        return .center.distanceSquaredTo(bounds.closestPoint(.center)) <= .radius * .radius
    }

    // Returns whether this sphere touches or crosses `plane`.
    mtd const intersects(plane: Plane3)->bool
    {
        Swag.assert(.radius >= 0)
        return Math.abs(plane.signedDistanceTo(.center)) <= .radius
    }
}

// An axis-aligned 3D box described by inclusive minimum and maximum corners.
#[Serialization.Final]
struct Bounds3
{
    public min: Vector3     // Inclusive lower corner.
    public max: Vector3     // Inclusive upper corner.
}

impl Bounds3
{
    // Creates an empty box that can be expanded with [[Core.Math.Geometry.Bounds3.includePoint]].
    func createEmpty()->Bounds3 => Bounds3{Vector3.Max, Vector3.Min}

    // Returns whether every minimum component is no greater than its matching maximum.
    mtd const isValid()->bool => .min.x <= .max.x and .min.y <= .max.y and .min.z <= .max.z

    // Returns the side lengths, or zero for an invalid box.
    mtd const size()->Vector3
    {
        if not .isValid() do
            return Vector3.Zero
        return .max - .min
    }

    // Returns the midpoint, or zero for an invalid box.
    mtd const center()->Vector3
    {
        if not .isValid() do
            return Vector3.Zero
        return (.min + .max) * 0.5
    }

    // Returns half of each side length, or zero for an invalid box.
    mtd const extents()->Vector3 => .size() * 0.5

    // Returns the volume, or zero for an invalid box.
    mtd const volume()->f32
    {
        let dimensions = .size()
        return dimensions.x * dimensions.y * dimensions.z
    }

    // Returns the total surface area, or zero for an invalid box.
    mtd const surfaceArea()->f32
    {
        let dimensions = .size()
        return 2 * (dimensions.x * dimensions.y + dimensions.y * dimensions.z + dimensions.z * dimensions.x)
    }

    // Returns whether this box contains `point`, including its boundary.
    mtd const contains(point: Vector3)->bool
    {
        return .isValid() and
               point.x >= .min.x and
               point.x <= .max.x and
               point.y >= .min.y and
               point.y <= .max.y and
               point.z >= .min.z and
               point.z <= .max.z
    }

    // Returns whether this box overlaps `other`, including touching faces, edges, or corners.
    mtd const intersects(other: Bounds3)->bool
    {
        return .isValid() and
               other.isValid() and
               .min.x <= other.max.x and
               .max.x >= other.min.x and
               .min.y <= other.max.y and
               .max.y >= other.min.y and
               .min.z <= other.max.z and
               .max.z >= other.min.z
    }

    // Returns whether this box overlaps `sphere`, including tangency.
    mtd const intersects(sphere: Sphere3)->bool => sphere.intersects(me)

    // Returns whether this box touches or crosses `plane`.
    mtd const intersects(plane: Plane3)->bool
    {
        if not .isValid() do
            return false
        let center          = .center()
        let extents         = .extents()
        let projectedRadius = Math.abs(plane.normal.x) * extents.x +
                              Math.abs(plane.normal.y) * extents.y +
                              Math.abs(plane.normal.z) * extents.z
        return Math.abs(plane.signedDistanceTo(center)) <= projectedRadius
    }

    // Returns the nearest point in this box to `point`; an invalid box returns `point` unchanged.
    mtd const closestPoint(point: Vector3)->Vector3
    {
        if not .isValid() do
            return point
        return Vector3{
            Math.clamp(point.x, .min.x, .max.x),
            Math.clamp(point.y, .min.y, .max.y),
            Math.clamp(point.z, .min.z, .max.z)}
    }

    // Expands this box to include `point`.
    mtd includePoint(point: Vector3)
    {
        .min = Vector3.min(.min, point)
        .max = Vector3.max(.max, point)
    }

    // Returns the smallest box containing both this box and `other`.
    mtd const merged(other: Bounds3)->Bounds3
    {
        if not .isValid() do
            return other
        if not other.isValid() do
            return me
        return Bounds3{Vector3.min(.min, other.min), Vector3.max(.max, other.max)}
    }

    // Intersects this box with a ray using the slab method.
    //
    // `distance` is the first forward parameter, or the exit parameter when the ray starts inside.
    // A miss returns false.
    mtd const intersect(ray: Ray3)->{ intersects: bool, distance: f32, point: Vector3 }
    {
        if not .isValid() do
            return {intersects: false, distance: 0, point: ray.origin}
        if ray.direction.isZero()
        {
            let containsOrigin = .contains(ray.origin)
            return {intersects: containsOrigin, distance: 0, point: ray.origin}
        }

        var near = -Swag.F32.Max
        var far  = Swag.F32.Max
        if ray.direction.x == 0
        {
            if ray.origin.x < .min.x or ray.origin.x > .max.x do
                return {intersects: false, distance: 0, point: ray.origin}
        }
        else
        {
            let inverse = 1 / ray.direction.x
            let a       = (.min.x - ray.origin.x) * inverse
            let b       = (.max.x - ray.origin.x) * inverse
            near = Math.max(near, Math.min(a, b))
            far  = Math.min(far, Math.max(a, b))
        }

        if ray.direction.y == 0
        {
            if ray.origin.y < .min.y or ray.origin.y > .max.y do
                return {intersects: false, distance: 0, point: ray.origin}
        }
        else
        {
            let inverse = 1 / ray.direction.y
            let a       = (.min.y - ray.origin.y) * inverse
            let b       = (.max.y - ray.origin.y) * inverse
            near = Math.max(near, Math.min(a, b))
            far  = Math.min(far, Math.max(a, b))
        }

        if ray.direction.z == 0
        {
            if ray.origin.z < .min.z or ray.origin.z > .max.z do
                return {intersects: false, distance: 0, point: ray.origin}
        }
        else
        {
            let inverse = 1 / ray.direction.z
            let a       = (.min.z - ray.origin.z) * inverse
            let b       = (.max.z - ray.origin.z) * inverse
            near = Math.max(near, Math.min(a, b))
            far  = Math.min(far, Math.max(a, b))
        }

        if near > far or far < 0 do
            return {intersects: false, distance: 0, point: ray.origin}
        var distance = near
        if distance < 0 do
            distance = far
        return {intersects: true, distance: distance, point: ray.pointAt(distance)}
    }
}

// A view frustum represented by six inward-facing normalized planes.
#[Serialization.Final]
struct Frustum3
{
    public left, right, bottom, top, near, far: Plane3     // Clip boundary planes; their positive side is inside.
}

impl Frustum3
{
    // Extracts an OpenGL depth-range frustum from a world-to-clip row-vector matrix.
    func fromMatrix(worldToClip: Matrix4x4)->Frustum3
    {
        let left = frustumPlane(Vector4{
            worldToClip.m[0, 0] + worldToClip.m[0, 3],
            worldToClip.m[1, 0] + worldToClip.m[1, 3],
            worldToClip.m[2, 0] + worldToClip.m[2, 3],
            worldToClip.m[3, 0] + worldToClip.m[3, 3]})
        let right = frustumPlane(Vector4{
            worldToClip.m[0, 3] - worldToClip.m[0, 0],
            worldToClip.m[1, 3] - worldToClip.m[1, 0],
            worldToClip.m[2, 3] - worldToClip.m[2, 0],
            worldToClip.m[3, 3] - worldToClip.m[3, 0]})
        let bottom = frustumPlane(Vector4{
            worldToClip.m[0, 1] + worldToClip.m[0, 3],
            worldToClip.m[1, 1] + worldToClip.m[1, 3],
            worldToClip.m[2, 1] + worldToClip.m[2, 3],
            worldToClip.m[3, 1] + worldToClip.m[3, 3]})
        let top = frustumPlane(Vector4{
            worldToClip.m[0, 3] - worldToClip.m[0, 1],
            worldToClip.m[1, 3] - worldToClip.m[1, 1],
            worldToClip.m[2, 3] - worldToClip.m[2, 1],
            worldToClip.m[3, 3] - worldToClip.m[3, 1]})
        let near = frustumPlane(Vector4{
            worldToClip.m[0, 2] + worldToClip.m[0, 3],
            worldToClip.m[1, 2] + worldToClip.m[1, 3],
            worldToClip.m[2, 2] + worldToClip.m[2, 3],
            worldToClip.m[3, 2] + worldToClip.m[3, 3]})
        let far = frustumPlane(Vector4{
            worldToClip.m[0, 3] - worldToClip.m[0, 2],
            worldToClip.m[1, 3] - worldToClip.m[1, 2],
            worldToClip.m[2, 3] - worldToClip.m[2, 2],
            worldToClip.m[3, 3] - worldToClip.m[3, 2]})
        return Frustum3{left, right, bottom, top, near, far}
    }

    // Returns whether `point` lies inside or on all six clip planes.
    mtd const contains(point: Vector3)->bool
    {
        return .left.signedDistanceTo(point) >= 0 and
               .right.signedDistanceTo(point) >= 0 and
               .bottom.signedDistanceTo(point) >= 0 and
               .top.signedDistanceTo(point) >= 0 and
               .near.signedDistanceTo(point) >= 0 and
               .far.signedDistanceTo(point) >= 0
    }

    // Returns whether `bounds` may intersect the frustum, rejecting it when wholly outside any one plane.
    //
    // This conservative plane test can keep boxes that miss only at a frustum corner.
    mtd const intersects(bounds: Bounds3)->bool
    {
        if not bounds.isValid() do
            return false
        return boundsIntersectsPlane(bounds, .left) and
               boundsIntersectsPlane(bounds, .right) and
               boundsIntersectsPlane(bounds, .bottom) and
               boundsIntersectsPlane(bounds, .top) and
               boundsIntersectsPlane(bounds, .near) and
               boundsIntersectsPlane(bounds, .far)
    }
}

private func boundsIntersectsPlane(bounds: Bounds3, plane: Plane3)->bool
{
    let center  = bounds.center()
    let extents = bounds.extents()
    let radius  = Math.abs(plane.normal.x) * extents.x +
                  Math.abs(plane.normal.y) * extents.y +
                  Math.abs(plane.normal.z) * extents.z
    return plane.signedDistanceTo(center) + radius >= 0
}

// Returns the intersection of a ray and a sphere, or a miss when the ray points away.
//
// The returned distance uses the ray parameter and the nearest nonnegative root.
func intersectRaySphere(ray: Ray3, center: Vector3, radius: f32)->{ intersects: bool, distance: f32, point: Vector3 }
{
    Swag.assert(radius >= 0)
    let offset = ray.origin - center
    let a      = ray.direction.dot(ray.direction)
    if a == 0 do
        return {intersects: false, distance: 0, point: ray.origin}
    let b = offset.dot(ray.direction)
    let c = offset.dot(offset) - radius * radius
    let discriminant = b * b - a * c
    if discriminant < 0 do
        return {intersects: false, distance: 0, point: ray.origin}
    let root     = sqrt(discriminant)
    var distance = (-b - root) / a
    if distance < 0 do
        distance = (-b + root) / a
    if distance < 0 do
        return {intersects: false, distance: distance, point: ray.origin}
    return {intersects: true, distance: distance, point: ray.pointAt(distance)}
}

// Returns the intersection of a ray with a triangle using a two-sided Möller–Trumbore test.
func intersectRayTriangle(ray: Ray3, a, b, c: Vector3)->{ intersects: bool, distance: f32, barycentric: Vector3, point: Vector3 }
{
    let edge1       = b - a
    let edge2       = c - a
    let p           = ray.direction.cross(edge2)
    let determinant = edge1.dot(p)
    if Math.isZeroEpsilon(determinant) do
        return {intersects: false, distance: 0, barycentric: Vector3.Zero, point: ray.origin}
    let inverse = 1 / determinant
    let offset  = ray.origin - a
    let u       = offset.dot(p) * inverse
    if u < 0 or u > 1 do
        return {intersects: false, distance: 0, barycentric: Vector3.Zero, point: ray.origin}
    let q = offset.cross(edge1)
    let v = ray.direction.dot(q) * inverse
    if v < 0 or u + v > 1 do
        return {intersects: false, distance: 0, barycentric: Vector3.Zero, point: ray.origin}
    let distance = edge2.dot(q) * inverse
    if distance < 0 do
        return {intersects: false, distance: distance, barycentric: Vector3{1 - u - v, u, v}, point: ray.origin}
    return {intersects: true, distance: distance, barycentric: Vector3{1 - u - v, u, v}, point: ray.pointAt(distance)}
}
