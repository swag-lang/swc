#global namespace Math
#global public

// Stores a four-dimensional vector of `f32` components.
//
// It commonly holds homogeneous coordinates, where W separates points from directions, or an
// RGBA color.
#[Serialization.Final]
struct Vector4
{
    public x, y, z, w: f32     // Components along the X, Y, Z, and W axes
}

impl Vector4
{
    const Zero     = Vector4{0, 0, 0, 0}                                                     // Zero vector (0, 0, 0, 0)
    const One      = Vector4{1, 1, 1, 1}                                                     // All components set to one (1, 1, 1, 1)
    const UnitX    = Vector4{1, 0, 0, 0}                                                     // Unit vector along the X axis (1, 0, 0, 0)
    const UnitY    = Vector4{0, 1, 0, 0}                                                     // Unit vector along the Y axis (0, 1, 0, 0)
    const UnitZ    = Vector4{0, 0, 1, 0}                                                     // Unit vector along the Z axis (0, 0, 1, 0)
    const UnitW    = Vector4{0, 0, 0, 1}                                                     // Unit vector along the W axis (0, 0, 0, 1)
    const NegUnitX = Vector4{-1, 0, 0, 0}                                                    // Unit vector along the negative X axis (-1, 0, 0, 0)
    const NegUnitY = Vector4{0, -1, 0, 0}                                                    // Unit vector along the negative Y axis (0, -1, 0, 0)
    const NegUnitZ = Vector4{0, 0, -1, 0}                                                    // Unit vector along the negative Z axis (0, 0, -1, 0)
    const NegUnitW = Vector4{0, 0, 0, -1}                                                    // Unit vector along the negative W axis (0, 0, 0, -1)
    const Max      = Vector4{Swag.F32.Max, Swag.F32.Max, Swag.F32.Max, Swag.F32.Max}         // Largest finite `f32` in every component
    const NegMax   = Vector4{-Swag.F32.Max, -Swag.F32.Max, -Swag.F32.Max, -Swag.F32.Max}     // Most negative finite `f32` in every component
    const Min      = Vector4{Swag.F32.Min, Swag.F32.Min, Swag.F32.Min, Swag.F32.Min}         // Smallest positive normalized `f32` in every component, not the most negative value

    // Sets every component to `value`.
    //
    // This is what lets a scalar initialize or assign a vector, as in `vec = 5.0`.
    #[Swag.Inline]
    mtd opSet(value: f32)
    {
        .x, .y, .z, .w = value
    }

    // Applies `+=`, `-=`, `*=`, or `/=` component by component with `other`.
    #[Swag.Inline]
    mtd(op: Swag.Operator) opAssign(other: Vector4)
        where op == .AddAssign or op == .SubAssign or op == .MulAssign or op == .DivAssign
    {
        #static switch op
        {
        case .AddAssign:
            .x += other.x
            .y += other.y
            .z += other.z
            .w += other.w

        case .SubAssign:
            .x -= other.x
            .y -= other.y
            .z -= other.z
            .w -= other.w

        case .MulAssign:
            .x *= other.x
            .y *= other.y
            .z *= other.z
            .w *= other.w

        case .DivAssign:
            .x /= other.x
            .y /= other.y
            .z /= other.z
            .w /= other.w
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
            .w += value

        case .SubAssign:
            .x -= value
            .y -= value
            .z -= value
            .w -= value

        case .MulAssign:
            .x *= value
            .y *= value
            .z *= value
            .w *= value

        case .DivAssign:
            .x /= value
            .y /= value
            .z /= value
            .w /= value
        }
    }

    // Returns the component-wise sum, difference, product, or quotient with `other`.
    #[Swag.Inline]
    mtd(op: Swag.Operator) const opBinary(other: Vector4)->Vector4
        where op == .Add or op == .Sub or op == .Mul or op == .Div
    {
        #static switch op
        {
        case .Add: return Vector4{.x + other.x, .y + other.y, .z + other.z, .w + other.w}
        case .Sub: return Vector4{.x - other.x, .y - other.y, .z - other.z, .w - other.w}
        case .Mul: return Vector4{.x * other.x, .y * other.y, .z * other.z, .w * other.w}
        case .Div: return Vector4{.x / other.x, .y / other.y, .z / other.z, .w / other.w}
        }
    }

    // Returns this vector with `+`, `-`, `*`, or `/` applied to every component and the scalar `value`.
    //
    // Addition and multiplication are commutative, so the scalar may also come first.
    #[Swag.Inline, Swag.Commutative(.Add, .Mul)]
    mtd(op: Swag.Operator) const opBinary(value: f32)->Vector4
        where op == .Add or op == .Sub or op == .Mul or op == .Div
    {
        #static switch op
        {
        case .Add: return Vector4{.x + value, .y + value, .z + value, .w + value}
        case .Sub: return Vector4{.x - value, .y - value, .z - value, .w - value}
        case .Mul: return Vector4{.x * value, .y * value, .z * value, .w * value}
        case .Div: return Vector4{.x / value, .y / value, .z / value, .w / value}
        }
    }

    // Returns this vector with every component negated.
    #[Swag.Inline]
    mtd(op: Swag.Operator) const opUnary()->Vector4
        where op == .Neg
    {
        return Vector4{-.x, -.y, -.z, -.w}
    }

    // Sets the components to `x`, `y`, `z`, and `w`.
    #[Swag.Inline]
    mtd set(x, y, z, w: f32)
    {
        .x = x
        .y = y
        .z = z
        .w = w
    }

    // Returns the Euclidean length of the vector.
    #[Swag.Inline]
    mtd const length()->f32 => sqrt((.x * .x) + (.y * .y) + (.z * .z) + (.w * .w))

    // Returns the squared length of the vector.
    //
    // It avoids the square root of [[Core.Math.Vector4.length]], which is enough to compare lengths.
    #[Swag.Inline]
    mtd const lengthSquared()->f32 => (.x * .x) + (.y * .y) + (.z * .z) + (.w * .w)

    // Returns the dot product of this vector and `other`.
    #[Swag.Inline]
    mtd const dot(other: Vector4)->f32 => (.x * other.x) + (.y * other.y) + (.z * other.z) + (.w * other.w)

    // Sets every component to zero.
    #[Swag.Inline]
    mtd setZero()
    {
        .x, .y, .z, .w = 0
    }

    // Negates every component in place, reversing the direction of the vector.
    #[Swag.Inline]
    mtd negate()
    {
        .x = -.x
        .y = -.y
        .z = -.z
        .w = -.w
    }

    // Returns whether every component is exactly zero.
    //
    // Use [[Core.Math.Vector4.isZeroEpsilon]] for computed values.
    #[Swag.Inline]
    mtd const isZero()->bool => .x == 0 and .y == 0 and .z == 0 and .w == 0

    // Returns whether every component is closer to zero than `eps`.
    mtd const isZeroEpsilon(eps = ConstF32.Epsilon)->bool => Math.isZeroEpsilon(.x, eps) and Math.isZeroEpsilon(.y, eps) and Math.isZeroEpsilon(.z, eps) and Math.isZeroEpsilon(.w, eps)

    // Returns whether every component is closer than `eps` to the matching component of `other`.
    mtd const isEqualEpsilon(other: Vector4, eps = ConstF32.Epsilon)->bool => Math.isEqualEpsilon(.x, other.x, eps) and Math.isEqualEpsilon(.y, other.y, eps) and Math.isEqualEpsilon(.z, other.z, eps) and Math.isEqualEpsilon(.w, other.w, eps)

    // Returns the Euclidean distance between this vector and `dest`.
    mtd const distanceTo(dest: Vector4)->f32
    {
        let xn = (.x - dest.x)
        let yn = (.y - dest.y)
        let zn = (.z - dest.z)
        let wn = (.w - dest.w)
        return sqrt((xn * xn) + (yn * yn) + (zn * zn) + (wn * wn))
    }

    // Returns the squared distance between this vector and `dest`.
    //
    // It avoids the square root of [[Core.Math.Vector4.distanceTo]], which is enough to compare distances.
    mtd const distanceSquaredTo(dest: Vector4)->f32
    {
        let xn = (.x - dest.x)
        let yn = (.y - dest.y)
        let zn = (.z - dest.z)
        let wn = (.w - dest.w)
        return (xn * xn) + (yn * yn) + (zn * zn) + (wn * wn)
    }

    // Scales this vector to unit length in place.
    //
    // The length must not be near zero, which is asserted. Use
    // [[Core.Math.Vector4.normalizeOrZero]] when it can be.
    mtd normalize()
    {
        var norm = sqrt((.x * .x) + (.y * .y) + (.z * .z) + (.w * .w))
        Swag.assert(not Math.isZeroEpsilon(norm))
        norm = 1 / norm
        .x   *= norm
        .y   *= norm
        .z   *= norm
        .w   *= norm
    }

    // Returns this vector scaled to unit length.
    //
    // The length must not be near zero, which is asserted. Use
    // [[Core.Math.Vector4.normalizedOrZero]] when it can be.
    mtd const normalized()->Vector4
    {
        var norm = sqrt((.x * .x) + (.y * .y) + (.z * .z) + (.w * .w))
        Swag.assert(not Math.isZeroEpsilon(norm))
        norm = 1 / norm
        return Vector4{.x * norm, .y * norm, .z * norm, .w * norm}
    }

    // Scales this vector to the length `newLength`, or sets it to zero when its length is near zero.
    mtd setLengthOrZero(newLength: f32)
    {
        .normalizeOrZero()
        .x *= newLength
        .y *= newLength
        .z *= newLength
        .w *= newLength
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
        .w *= newLength
    }

    // Scales this vector to unit length in place, or sets it to zero when its length is near zero.
    mtd normalizeOrZero()
    {
        var norm = sqrt((.x * .x) + (.y * .y) + (.z * .z) + (.w * .w))
        if Math.isZeroEpsilon(norm)
        {
            .x, .y, .z, .w = 0
            return
        }

        norm = 1 / norm
        .x   *= norm
        .y   *= norm
        .z   *= norm
        .w   *= norm
    }

    // Returns this vector scaled to unit length, or the zero vector when its length is near zero.
    mtd const normalizedOrZero()->Vector4
    {
        var norm = sqrt((.x * .x) + (.y * .y) + (.z * .z) + (.w * .w))
        if Math.isZeroEpsilon(norm) do
            return Zero
        norm = 1 / norm
        return Vector4{.x * norm, .y * norm, .z * norm, .w * norm}
    }

    // Returns the component-wise minimum of `a` and `b`.
    func min(a, b: Vector4)->Vector4
    {
        var result: retval
        result.x = Math.min(a.x, b.x)
        result.y = Math.min(a.y, b.y)
        result.z = Math.min(a.z, b.z)
        result.w = Math.min(a.w, b.w)
        return result
    }

    // Returns the component-wise maximum of `a` and `b`.
    func max(a, b: Vector4)->Vector4
    {
        var result: retval
        result.x = Math.max(a.x, b.x)
        result.y = Math.max(a.y, b.y)
        result.z = Math.max(a.z, b.z)
        result.w = Math.max(a.w, b.w)
        return result
    }

    // Rounds every component down to an integer value in place.
    mtd floor()
    {
        .x = Math.floor(.x)
        .y = Math.floor(.y)
        .z = Math.floor(.z)
        .w = Math.floor(.w)
    }

    // Rounds every component up to an integer value in place.
    mtd ceil()
    {
        .x = Math.ceil(.x)
        .y = Math.ceil(.y)
        .z = Math.ceil(.z)
        .w = Math.ceil(.w)
    }

    // Rounds every component to the nearest integer value in place.
    //
    // A component halfway between two integers rounds away from zero.
    mtd round()
    {
        .x = Math.round(.x)
        .y = Math.round(.y)
        .z = Math.round(.z)
        .w = Math.round(.w)
    }

    // Returns the cosine of the angle between this vector and `other`, within [-1, 1].
    //
    // The result is NaN when either vector is zero.
    mtd const angleCosineTo(other: Vector4)->f32
    {
        // Rounding can push the ratio for nearly parallel vectors just past 1 in magnitude,
        // outside the domain of acos. The comparisons leave a NaN untouched.
        let cosine = .dot(other) / (.length() * other.length())
        return cosine > 1 ? 1 : (cosine < -1 ? -1 : cosine)
    }

    // Returns the unsigned angle between this vector and `other`, in radians within [0, π].
    //
    // The result is NaN when either vector is zero.
    mtd const angleTo(other: Vector4)->f32 => Math.acos(.angleCosineTo(other))

    // Returns the linear interpolation from `src` to `dst` at `factor`.
    //
    // A `factor` of 0 gives `src` and 1 gives `dst`. It is not clamped, so other values extrapolate.
    func lerp(src, dst: Vector4, factor: f32)->Vector4
    {
        var result: retval
        result.x = Math.lerp(src.x, dst.x, factor)
        result.y = Math.lerp(src.y, dst.y, factor)
        result.z = Math.lerp(src.z, dst.z, factor)
        result.w = Math.lerp(src.w, dst.w, factor)
        return result
    }

    // Clamps every component in place between the matching components of `min` and `max`.
    mtd clamp(min, max: Vector4)
    {
        .x = Math.clamp(.x, min.x, max.x)
        .y = Math.clamp(.y, min.y, max.y)
        .z = Math.clamp(.z, min.z, max.z)
        .w = Math.clamp(.w, min.w, max.w)
    }

    // Returns this vector with every component clamped between the matching components of `min` and `max`.
    mtd const clamped(min, max: Vector4)->Vector4 => Vector4{Math.clamp(.x, min.x, max.x), Math.clamp(.y, min.y, max.y), Math.clamp(.z, min.z, max.z), Math.clamp(.w, min.w, max.w)}

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
    mtd const clampedLength(minLength, maxLength: f32)->Vector4
    {
        let len = .length()
        if len < minLength do
            return .normalized() * minLength
        elif len > maxLength do
            return .normalized() * maxLength
        return me
    }

    // Returns this vector with the absolute value of every component.
    mtd const absolute()->Vector4 => Vector4{Math.abs(.x), Math.abs(.y), Math.abs(.z), Math.abs(.w)}

    // Replaces every component with its absolute value.
    mtd makeAbsolute()
    {
        .x = Math.abs(.x)
        .y = Math.abs(.y)
        .z = Math.abs(.z)
        .w = Math.abs(.w)
    }

    // Returns the projection of this vector onto the direction of `other`.
    //
    // The result is the zero vector when `other` is near zero.
    mtd const projectedOnto(other: Vector4)->Vector4
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
    mtd const reflected(normal: Vector4)->Vector4
    {
        let scale = 2.0 * .dot(normal)
        return Vector4{.x - normal.x * scale, .y - normal.y * scale, .z - normal.z * scale, .w - normal.w * scale}
    }

    // Returns the sign of every component, as -1, 0, or 1.
    mtd const sign()->Vector4 => Vector4{Math.sign(.x), Math.sign(.y), Math.sign(.z), Math.sign(.w)}

    // Returns whether every component is finite, neither infinite nor NaN.
    mtd const isFinite()->bool => Math.isFinite(.x) and Math.isFinite(.y) and Math.isFinite(.z) and Math.isFinite(.w)

    // Returns whether any component is NaN.
    mtd const isNaN()->bool => Math.isNaN(.x) or Math.isNaN(.y) or Math.isNaN(.z) or Math.isNaN(.w)

    // Moves this vector toward `target` by at most `maxDistance`.
    //
    // It lands exactly on `target` once that is within `maxDistance`.
    mtd moveTowards(target: Vector4, maxDistance: f32)
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
    mtd const movedTowards(target: Vector4, maxDistance: f32)->Vector4
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
    func smoothDamp(current, target: Vector4, currentVelocity: *Vector4, smoothTime, deltaTime: f32)->Vector4
    {
        var result: retval
        result.x = Math.smoothDamp(current.x, target.x, &currentVelocity.x, smoothTime, deltaTime)
        result.y = Math.smoothDamp(current.y, target.y, &currentVelocity.y, smoothTime, deltaTime)
        result.z = Math.smoothDamp(current.z, target.z, &currentVelocity.z, smoothTime, deltaTime)
        result.w = Math.smoothDamp(current.w, target.w, &currentVelocity.w, smoothTime, deltaTime)
        return result
    }

    // Returns the 3D point these homogeneous coordinates describe, with X, Y, and Z divided by W.
    //
    // When W is near zero the coordinates describe a direction rather than a point, and X, Y, and
    // Z are returned unchanged.
    mtd const toVector3()->Vector3
    {
        if Math.isZeroEpsilon(.w) do
            return Vector3{.x, .y, .z}
        return Vector3{.x / .w, .y / .w, .z / .w}
    }

    // Returns the X, Y, and Z components as a [[Core.Math.Vector3]], without dividing by W.
    mtd const xyz()->Vector3 => Vector3{.x, .y, .z}

    // Returns the X and Y components as a [[Core.Math.Vector2]].
    mtd const xy()->Vector2 => Vector2{.x, .y}

    // Creates a vector from the components of `v` and the W component `w`.
    //
    // A `w` of 1 makes homogeneous coordinates for the point `v`, and 0 for the direction `v`.
    func fromVector3(v: Vector3, w: f32)->Vector4 => Vector4{v.x, v.y, v.z, w}

    // Creates a vector from the components of `v` followed by `z` and `w`.
    func fromVector2(v: Vector2, z, w: f32)->Vector4 => Vector4{v.x, v.y, z, w}
}
