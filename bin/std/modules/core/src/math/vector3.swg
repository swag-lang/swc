#global namespace Math
#global public

// Stores a three-dimensional vector of `f32` components.
//
// The same type serves as a position and as a direction. Angles are in radians.
#[Serialization.Final]
struct Vector3
{
    public x, y, z: f32     // Components along the X, Y, and Z axes
}

impl Vector3
{
    const Zero     = Vector3{0, 0, 0}                                         // Zero vector (0, 0, 0)
    const One      = Vector3{1, 1, 1}                                         // All components set to one (1, 1, 1)
    const UnitX    = Vector3{1, 0, 0}                                         // Unit vector along the X axis (1, 0, 0)
    const UnitY    = Vector3{0, 1, 0}                                         // Unit vector along the Y axis (0, 1, 0)
    const UnitZ    = Vector3{0, 0, 1}                                         // Unit vector along the Z axis (0, 0, 1)
    const NegUnitX = Vector3{-1, 0, 0}                                        // Unit vector along the negative X axis (-1, 0, 0)
    const NegUnitY = Vector3{0, -1, 0}                                        // Unit vector along the negative Y axis (0, -1, 0)
    const NegUnitZ = Vector3{0, 0, -1}                                        // Unit vector along the negative Z axis (0, 0, -1)
    const Max      = Vector3{Swag.F32.Max, Swag.F32.Max, Swag.F32.Max}        // Largest finite `f32` in every component
    const NegMax   = Vector3{-Swag.F32.Max, -Swag.F32.Max, -Swag.F32.Max}     // Most negative finite `f32` in every component
    const Min      = Vector3{Swag.F32.Min, Swag.F32.Min, Swag.F32.Min}        // Smallest positive normalized `f32` in every component, not the most negative value

    // Sets every component to `value`.
    //
    // This is what lets a scalar initialize or assign a vector, as in `vec = 5.0`.
    #[Swag.Inline]
    mtd opSet(value: f32)
    {
        .x, .y, .z = value
    }

    // Applies `+=`, `-=`, `*=`, or `/=` component by component with `other`.
    #[Swag.Inline]
    mtd(op: Swag.Operator) opAssign(other: Vector3)
        where op == .AddAssign or op == .SubAssign or op == .MulAssign or op == .DivAssign
    {
        #static switch op
        {
        case .AddAssign:
            .x += other.x
            .y += other.y
            .z += other.z

        case .SubAssign:
            .x -= other.x
            .y -= other.y
            .z -= other.z

        case .MulAssign:
            .x *= other.x
            .y *= other.y
            .z *= other.z

        case .DivAssign:
            .x /= other.x
            .y /= other.y
            .z /= other.z
        }
    }

    // Applies `+=`, `-=`, `*=`, or `/=` with the scalar `value` to every component.
    #[Swag.Inline]
    mtd(op: Swag.Operator) opAssign(value: f32)
        where op == .AddAssign or op == .SubAssign or op == .MulAssign or op == .DivAssign
    {
        #static switch op
        {
        case .AddAssign:
            .x += value
            .y += value
            .z += value

        case .SubAssign:
            .x -= value
            .y -= value
            .z -= value

        case .MulAssign:
            .x *= value
            .y *= value
            .z *= value

        case .DivAssign:
            .x /= value
            .y /= value
            .z /= value
        }
    }

    // Returns the component-wise sum, difference, product, or quotient with `other`.
    #[Swag.Inline]
    mtd(op: Swag.Operator) const opBinary(other: Vector3)->Vector3
        where op == .Add or op == .Sub or op == .Mul or op == .Div
    {
        #static switch op
        {
        case .Add: return Vector3{.x + other.x, .y + other.y, .z + other.z}
        case .Sub: return Vector3{.x - other.x, .y - other.y, .z - other.z}
        case .Mul: return Vector3{.x * other.x, .y * other.y, .z * other.z}
        case .Div: return Vector3{.x / other.x, .y / other.y, .z / other.z}
        }
    }

    // Returns this vector with `+`, `-`, `*`, or `/` applied to every component and the scalar `value`.
    //
    // Addition and multiplication are commutative, so the scalar may also come first.
    #[Swag.Inline, Swag.Commutative(.Add, .Mul)]
    mtd(op: Swag.Operator) const opBinary(value: f32)->Vector3
        where op == .Add or op == .Sub or op == .Mul or op == .Div
    {
        #static switch op
        {
        case .Add: return Vector3{.x + value, .y + value, .z + value}
        case .Sub: return Vector3{.x - value, .y - value, .z - value}
        case .Mul: return Vector3{.x * value, .y * value, .z * value}
        case .Div: return Vector3{.x / value, .y / value, .z / value}
        }
    }

    // Returns this vector with every component negated.
    #[Swag.Inline]
    mtd(op: Swag.Operator) const opUnary()->Vector3
        where op == .Neg
    {
        return Vector3{-.x, -.y, -.z}
    }

    // Sets the components to `x`, `y`, and `z`.
    #[Swag.Inline]
    mtd set(x, y, z: f32)
    {
        .x = x
        .y = y
        .z = z
    }

    // Returns the Euclidean length of the vector.
    #[Swag.Inline]
    mtd const length()->f32 => sqrt((.x * .x) + (.y * .y) + (.z * .z))

    // Returns the squared length of the vector.
    //
    // It avoids the square root of [[Core.Math.Vector3.length]], which is enough to compare lengths.
    #[Swag.Inline]
    mtd const lengthSquared()->f32 => (.x * .x) + (.y * .y) + (.z * .z)

    // Returns the dot product of this vector and `other`.
    #[Swag.Inline]
    mtd const dot(other: Vector3)->f32 => (.x * other.x) + (.y * other.y) + (.z * other.z)

    // Returns the cross product of this vector and `other`.
    //
    // The result is perpendicular to both vectors, and its length is the area of the parallelogram
    // they span. The orientation follows the axes: `UnitX.cross(UnitY)` is `UnitZ`.
    #[Swag.Inline]
    mtd const cross(other: Vector3)->Vector3 => Vector3{(.y * other.z) - (.z * other.y), (.z * other.x) - (.x * other.z), (.x * other.y) - (.y * other.x)}

    // Sets every component to zero.
    #[Swag.Inline]
    mtd setZero()
    {
        .x, .y, .z = 0
    }

    // Negates every component in place, reversing the direction of the vector.
    #[Swag.Inline]
    mtd negate()
    {
        .x = -.x
        .y = -.y
        .z = -.z
    }

    // Returns whether every component is exactly zero.
    //
    // Use [[Core.Math.Vector3.isZeroEpsilon]] for computed values.
    #[Swag.Inline]
    mtd const isZero()->bool => .x == 0 and .y == 0 and .z == 0

    // Returns whether every component is closer to zero than `eps`.
    mtd const isZeroEpsilon(eps = ConstF32.Epsilon)->bool => Math.isZeroEpsilon(.x, eps) and Math.isZeroEpsilon(.y, eps) and Math.isZeroEpsilon(.z, eps)

    // Returns whether every component is closer than `eps` to the matching component of `other`.
    mtd const isEqualEpsilon(other: Vector3, eps = ConstF32.Epsilon)->bool => Math.isEqualEpsilon(.x, other.x, eps) and Math.isEqualEpsilon(.y, other.y, eps) and Math.isEqualEpsilon(.z, other.z, eps)

    // Returns the Euclidean distance between this vector and `dest`.
    mtd const distanceTo(dest: Vector3)->f32
    {
        let xn = (.x - dest.x)
        let yn = (.y - dest.y)
        let zn = (.z - dest.z)
        return sqrt((xn * xn) + (yn * yn) + (zn * zn))
    }

    // Returns the squared distance between this vector and `dest`.
    //
    // It avoids the square root of [[Core.Math.Vector3.distanceTo]], which is enough to compare distances.
    mtd const distanceSquaredTo(dest: Vector3)->f32
    {
        let xn = (.x - dest.x)
        let yn = (.y - dest.y)
        let zn = (.z - dest.z)
        return (xn * xn) + (yn * yn) + (zn * zn)
    }

    // Scales this vector to unit length in place.
    //
    // The length must not be near zero, which is asserted. Use
    // [[Core.Math.Vector3.normalizeOrZero]] when it can be.
    mtd normalize()
    {
        var norm = sqrt((.x * .x) + (.y * .y) + (.z * .z))
        Swag.assert(not Math.isZeroEpsilon(norm))
        norm = 1 / norm
        .x   *= norm
        .y   *= norm
        .z   *= norm
    }

    // Returns this vector scaled to unit length.
    //
    // The length must not be near zero, which is asserted. Use
    // [[Core.Math.Vector3.normalizedOrZero]] when it can be.
    mtd const normalized()->Vector3
    {
        var norm = sqrt((.x * .x) + (.y * .y) + (.z * .z))
        Swag.assert(not Math.isZeroEpsilon(norm))
        norm = 1 / norm
        return Vector3{.x * norm, .y * norm, .z * norm}
    }

    // Scales this vector to the length `newLength`, or sets it to zero when its length is near zero.
    mtd setLengthOrZero(newLength: f32)
    {
        .normalizeOrZero()
        .x *= newLength
        .y *= newLength
        .z *= newLength
    }

    // Scales this vector to the length `newLength`, keeping its direction.
    //
    // The current length must not be near zero, which is asserted.
    mtd setLength(newLength: f32)
    {
        .normalize()
        .x *= newLength
        .y *= newLength
        .z *= newLength
    }

    // Scales this vector to unit length in place, or sets it to zero when its length is near zero.
    mtd normalizeOrZero()
    {
        var norm = sqrt((.x * .x) + (.y * .y) + (.z * .z))
        if Math.isZeroEpsilon(norm)
        {
            .x, .y, .z = 0
            return
        }

        norm = 1 / norm
        .x   *= norm
        .y   *= norm
        .z   *= norm
    }

    // Returns this vector scaled to unit length, or the zero vector when its length is near zero.
    mtd const normalizedOrZero()->Vector3
    {
        var norm = sqrt((.x * .x) + (.y * .y) + (.z * .z))
        if Math.isZeroEpsilon(norm) do
            return Zero
        norm = 1 / norm
        return Vector3{.x * norm, .y * norm, .z * norm}
    }

    // Returns the component-wise minimum of `a` and `b`.
    func min(a, b: Vector3)->Vector3
    {
        var result: retval
        result.x = Math.min(a.x, b.x)
        result.y = Math.min(a.y, b.y)
        result.z = Math.min(a.z, b.z)
        return result
    }

    // Returns the component-wise maximum of `a` and `b`.
    func max(a, b: Vector3)->Vector3
    {
        var result: retval
        result.x = Math.max(a.x, b.x)
        result.y = Math.max(a.y, b.y)
        result.z = Math.max(a.z, b.z)
        return result
    }

    // Rounds every component down to an integer value in place.
    mtd floor()
    {
        .x = Math.floor(.x)
        .y = Math.floor(.y)
        .z = Math.floor(.z)
    }

    // Rounds every component up to an integer value in place.
    mtd ceil()
    {
        .x = Math.ceil(.x)
        .y = Math.ceil(.y)
        .z = Math.ceil(.z)
    }

    // Rounds every component to the nearest integer value in place.
    //
    // A component halfway between two integers rounds away from zero.
    mtd round()
    {
        .x = Math.round(.x)
        .y = Math.round(.y)
        .z = Math.round(.z)
    }

    // Returns the cosine of the angle between this vector and `other`, within [-1, 1].
    //
    // The result is NaN when either vector is zero.
    mtd const angleCosineTo(other: Vector3)->f32
    {
        // Rounding can push the ratio for nearly parallel vectors just past 1 in magnitude,
        // outside the domain of acos. The comparisons leave a NaN untouched.
        let cosine = .dot(other) / (.length() * other.length())
        return cosine > 1 ? 1 : (cosine < -1 ? -1 : cosine)
    }

    // Returns the unsigned angle between this vector and `other`, in radians within [0, π].
    //
    // The result is NaN when either vector is zero.
    mtd const angleTo(other: Vector3)->f32 => Math.acos(.angleCosineTo(other))

    // Returns the linear interpolation from `src` to `dst` at `factor`.
    //
    // A `factor` of 0 gives `src` and 1 gives `dst`. It is not clamped, so other values extrapolate.
    func lerp(src, dst: Vector3, factor: f32)->Vector3
    {
        var result: retval
        result.x = Math.lerp(src.x, dst.x, factor)
        result.y = Math.lerp(src.y, dst.y, factor)
        result.z = Math.lerp(src.z, dst.z, factor)
        return result
    }

    // Clamps every component in place between the matching components of `min` and `max`.
    mtd clamp(min, max: Vector3)
    {
        .x = Math.clamp(.x, min.x, max.x)
        .y = Math.clamp(.y, min.y, max.y)
        .z = Math.clamp(.z, min.z, max.z)
    }

    // Returns this vector with every component clamped between the matching components of `min` and `max`.
    mtd const clamped(min, max: Vector3)->Vector3 => Vector3{Math.clamp(.x, min.x, max.x), Math.clamp(.y, min.y, max.y), Math.clamp(.z, min.z, max.z)}

    // Scales this vector in place so that its length lies between `minLength` and `maxLength`.
    //
    // The direction is kept, so a vector shorter than `minLength` must not be zero, which is asserted.
    mtd clampLength(minLength, maxLength: f32)
    {
        let len = .length()
        if len < minLength do
            .setLength(minLength)
        elif len > maxLength do
            .setLength(maxLength)
    }

    // Returns this vector scaled so that its length lies between `minLength` and `maxLength`.
    //
    // The direction is kept, so a vector shorter than `minLength` must not be zero, which is asserted.
    mtd const clampedLength(minLength, maxLength: f32)->Vector3
    {
        let len = .length()
        if len < minLength do
            return .normalized() * minLength
        elif len > maxLength do
            return .normalized() * maxLength
        return me
    }

    // Returns this vector with the absolute value of every component.
    mtd const absolute()->Vector3 => Vector3{Math.abs(.x), Math.abs(.y), Math.abs(.z)}

    // Replaces every component with its absolute value.
    mtd makeAbsolute()
    {
        .x = Math.abs(.x)
        .y = Math.abs(.y)
        .z = Math.abs(.z)
    }

    // Returns the projection of this vector onto the direction of `other`.
    //
    // The result is the zero vector when `other` is near zero.
    mtd const projectedOnto(other: Vector3)->Vector3
    {
        let dotProduct    = .dot(other)
        let otherLengthSq = other.lengthSquared()
        if Math.isZeroEpsilon(otherLengthSq) do
            return Zero
        return other * (dotProduct / otherLengthSq)
    }

    // Returns this vector reflected off a surface whose normal is `normal`.
    //
    // `normal` must have unit length. The component along it is reversed and the component along
    // the surface is kept.
    mtd const reflected(normal: Vector3)->Vector3
    {
        let scale = 2.0 * .dot(normal)
        return Vector3{.x - normal.x * scale, .y - normal.y * scale, .z - normal.z * scale}
    }

    // Returns the sign of every component, as -1, 0, or 1.
    mtd const sign()->Vector3 => Vector3{Math.sign(.x), Math.sign(.y), Math.sign(.z)}

    // Returns whether every component is finite, neither infinite nor NaN.
    mtd const isFinite()->bool => Math.isFinite(.x) and Math.isFinite(.y) and Math.isFinite(.z)

    // Returns whether any component is NaN.
    mtd const isNaN()->bool => Math.isNaN(.x) or Math.isNaN(.y) or Math.isNaN(.z)

    // Moves this vector toward `target` by at most `maxDistance`.
    //
    // It lands exactly on `target` once that is within `maxDistance`.
    mtd moveTowards(target: Vector3, maxDistance: f32)
    {
        let dir  = target - me
        let dist = dir.length()
        if dist <= maxDistance do
            me[] = target
        else do
            me[] += dir * (maxDistance / dist)
    }

    // Returns this vector moved toward `target` by at most `maxDistance`.
    //
    // The result is exactly `target` once that is within `maxDistance`.
    mtd const movedTowards(target: Vector3, maxDistance: f32)->Vector3
    {
        let dir  = target - me
        let dist = dir.length()
        if dist <= maxDistance do
            return target
        return me[] + (dir * (maxDistance / dist))
    }

    // Returns `current` moved toward `target` along a critically damped spring over `deltaTime`.
    //
    // Each component follows [[Core.Math.smoothDamp]]. `currentVelocity` carries the velocity from
    // one call to the next and is updated in place.
    func smoothDamp(current, target: Vector3, currentVelocity: *Vector3, smoothTime, deltaTime: f32)->Vector3
    {
        var result: retval
        result.x = Math.smoothDamp(current.x, target.x, &currentVelocity.x, smoothTime, deltaTime)
        result.y = Math.smoothDamp(current.y, target.y, &currentVelocity.y, smoothTime, deltaTime)
        result.z = Math.smoothDamp(current.z, target.z, &currentVelocity.z, smoothTime, deltaTime)
        return result
    }

    // Creates a vector from spherical coordinates whose polar axis is Y.
    //
    // `phi` is the polar angle from the positive Y axis, `theta` the azimuth in the XZ plane from
    // the positive X axis toward the positive Z axis, both in radians, and `radius` the length.
    func fromSpherical(theta, phi, radius: f32)->Vector3
    {
        let sinPhi = Math.sin(phi)
        return Vector3{radius * sinPhi * Math.cos(theta), radius * Math.cos(phi), radius * sinPhi * Math.sin(theta)}
    }

    // Returns the spherical coordinates of this vector, with Y as the polar axis.
    //
    // The angles are measured as in [[Core.Math.Vector3.fromSpherical]]: `theta` lies within
    // [-π, π] and `phi` within [0, π]. `phi` is NaN for the zero vector.
    mtd const toSpherical()->{ theta: f32, phi: f32, radius: f32 }
    {
        let radius = .length()
        let phi    = Math.acos(.y / radius)
        let theta  = Math.atan2(.z, .x)
        return {theta, phi, radius}
    }

    // Creates a vector from cylindrical coordinates around the Y axis.
    //
    // `theta` is the angle in the XZ plane, in radians from the positive X axis toward the
    // positive Z axis, `radius` the distance from the Y axis, and `height` the Y component.
    func fromCylindrical(theta, radius, height: f32)->Vector3 => Vector3{radius * Math.cos(theta), height, radius * Math.sin(theta)}

    // Returns the cylindrical coordinates of this vector around the Y axis.
    //
    // The coordinates are measured as in [[Core.Math.Vector3.fromCylindrical]], with `theta`
    // within [-π, π].
    mtd const toCylindrical()->{ theta: f32, radius: f32, height: f32 }
    {
        let radius = Math.sqrt((.x * .x) + (.z * .z))
        let theta  = Math.atan2(.z, .x)
        return {theta, radius, .y}
    }
}
