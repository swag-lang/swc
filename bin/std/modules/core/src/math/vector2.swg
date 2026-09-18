#global namespace Math
#global public

// Stores a two-dimensional vector of `f32` components.
//
// The same type serves as a position and as a direction. Angles are in radians, and a positive
// angle turns the X axis toward the Y axis, which is counter-clockwise when Y points up.
#[Serialization.Final]
struct Vector2
{
    public x, y: f32     // Components along the X and Y axes
}

impl Vector2
{
    const Zero     = Vector2{0, 0}                             // Zero vector (0, 0)
    const One      = Vector2{1, 1}                             // Both components set to one (1, 1)
    const UnitX    = Vector2{1, 0}                             // Unit vector along the X axis (1, 0)
    const UnitY    = Vector2{0, 1}                             // Unit vector along the Y axis (0, 1)
    const NegUnitX = Vector2{-1, 0}                            // Unit vector along the negative X axis (-1, 0)
    const NegUnitY = Vector2{0, -1}                            // Unit vector along the negative Y axis (0, -1)
    const Max      = Vector2{Swag.F32.Max, Swag.F32.Max}       // Largest finite `f32` in every component
    const NegMax   = Vector2{-Swag.F32.Max, -Swag.F32.Max}     // Most negative finite `f32` in every component
    const Min      = Vector2{Swag.F32.Min, Swag.F32.Min}       // Smallest positive normalized `f32` in every component, not the most negative value

    // Sets both components to `value`.
    //
    // This is what lets a scalar initialize or assign a vector, as in `vec = 5.0`.
    #[Swag.Inline]
    mtd opSet(value: f32)
    {
        .x, .y = value
    }

    // Applies `+=`, `-=`, `*=`, or `/=` component by component with `other`.
    #[Swag.Inline]
    mtd(op: Swag.Operator) opAssign(other: Vector2)
        where op == .AddAssign or op == .SubAssign or op == .MulAssign or op == .DivAssign
    {
        #static switch op
        {
        case .AddAssign:
            .x += other.x
            .y += other.y

        case .SubAssign:
            .x -= other.x
            .y -= other.y

        case .MulAssign:
            .x *= other.x
            .y *= other.y

        case .DivAssign:
            .x /= other.x
            .y /= other.y
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

        case .SubAssign:
            .x -= value
            .y -= value

        case .MulAssign:
            .x *= value
            .y *= value

        case .DivAssign:
            .x /= value
            .y /= value
        }
    }

    // Returns the component-wise sum, difference, product, or quotient with `other`.
    #[Swag.Inline]
    mtd(op: Swag.Operator) const opBinary(other: Vector2)->Vector2
        where op == .Add or op == .Sub or op == .Mul or op == .Div
    {
        #static switch op
        {
        case .Add: return Vector2{.x + other.x, .y + other.y}
        case .Sub: return Vector2{.x - other.x, .y - other.y}
        case .Mul: return Vector2{.x * other.x, .y * other.y}
        case .Div: return Vector2{.x / other.x, .y / other.y}
        }
    }

    // Returns this vector with `+`, `-`, `*`, or `/` applied to every component and the scalar `value`.
    //
    // Addition and multiplication are commutative, so the scalar may also come first.
    #[Swag.Inline, Swag.Commutative(.Add, .Mul)]
    mtd(op: Swag.Operator) const opBinary(value: f32)->Vector2
        where op == .Add or op == .Sub or op == .Mul or op == .Div
    {
        #static switch op
        {
        case .Add: return Vector2{.x + value, .y + value}
        case .Sub: return Vector2{.x - value, .y - value}
        case .Mul: return Vector2{.x * value, .y * value}
        case .Div: return Vector2{.x / value, .y / value}
        }
    }

    // Returns this vector with both components negated.
    #[Swag.Inline]
    mtd(op: Swag.Operator) const opUnary()->Vector2
        where op == .Neg
    {
        return Vector2{-.x, -.y}
    }

    // Sets the components to `x` and `y`.
    #[Swag.Inline]
    mtd set(x, y: f32)
    {
        .x = x
        .y = y
    }

    // Returns the Euclidean length of the vector.
    #[Swag.Inline]
    mtd const length()->f32 => sqrt((.x * .x) + (.y * .y))

    // Returns the squared length of the vector.
    //
    // It avoids the square root of [[Core.Math.Vector2.length]], which is enough to compare lengths.
    #[Swag.Inline]
    mtd const lengthSquared()->f32 => (.x * .x) + (.y * .y)

    // Returns the dot product of this vector and `other`.
    #[Swag.Inline]
    mtd const dot(other: Vector2)->f32 => (.x * other.x) + (.y * other.y)

    // Returns the cross product of this vector with a Z-axis vector of length `axis`.
    //
    // The result lies in the plane: it is [[Core.Math.Vector2.perpendicularClockwise]] scaled by `axis`.
    #[Swag.Inline]
    mtd const cross(axis: f32)->Vector2 => {.y * axis, -.x * axis}

    // Returns the Z component of the cross product of this vector and `other`.
    //
    // It is positive when the shorter turn from this vector to `other` goes the way the X axis
    // turns toward the Y axis, negative when it goes the other way, and zero when the two vectors
    // are parallel.
    #[Swag.Inline]
    mtd const cross(other: Vector2)->f32 => .x * other.y - .y * other.x

    // Sets both components to zero.
    #[Swag.Inline]
    mtd setZero()
    {
        .x, .y = 0
    }

    // Negates both components in place, reversing the direction of the vector.
    #[Swag.Inline]
    mtd negate()
    {
        .x = -.x
        .y = -.y
    }

    // Returns whether both components are exactly zero.
    //
    // Use [[Core.Math.Vector2.isZeroEpsilon]] for computed values.
    #[Swag.Inline]
    mtd const isZero()->bool => .x == 0 and .y == 0

    // Returns whether both components are closer to zero than `eps`.
    mtd const isZeroEpsilon(eps = ConstF32.Epsilon)->bool => Math.isZeroEpsilon(.x, eps) and Math.isZeroEpsilon(.y, eps)

    // Returns whether every component is closer than `eps` to the matching component of `other`.
    mtd const isEqualEpsilon(other: Vector2, eps = ConstF32.Epsilon)->bool => Math.isEqualEpsilon(.x, other.x, eps) and Math.isEqualEpsilon(.y, other.y, eps)

    // Returns the Euclidean distance between this vector and `dest`.
    mtd const distanceTo(dest: Vector2)->f32
    {
        let xn = (.x - dest.x)
        let yn = (.y - dest.y)
        return sqrt((xn * xn) + (yn * yn))
    }

    // Returns the squared distance between this vector and `dest`.
    //
    // It avoids the square root of [[Core.Math.Vector2.distanceTo]], which is enough to compare distances.
    mtd const distanceSquaredTo(dest: Vector2)->f32
    {
        let xn = (.x - dest.x)
        let yn = (.y - dest.y)
        return (xn * xn) + (yn * yn)
    }

    // Scales this vector to unit length in place.
    //
    // The length must not be near zero, which is asserted. Use
    // [[Core.Math.Vector2.normalizeOrZero]] when it can be.
    mtd normalize()
    {
        var norm = sqrt((.x * .x) + (.y * .y))
        Swag.assert(not Math.isZeroEpsilon(norm))
        norm = 1 / norm
        .x   *= norm
        .y   *= norm
    }

    // Returns this vector scaled to unit length.
    //
    // The length must not be near zero, which is asserted. Use
    // [[Core.Math.Vector2.normalizedOrZero]] when it can be.
    mtd const normalized()->Vector2
    {
        var norm = sqrt((.x * .x) + (.y * .y))
        Swag.assert(not Math.isZeroEpsilon(norm))
        norm = 1 / norm
        return Vector2{.x * norm, .y * norm}
    }

    // Scales this vector to the length `newLength`, or sets it to zero when its length is near zero.
    mtd setLengthOrZero(newLength: f32)
    {
        .normalizeOrZero()
        .x *= newLength
        .y *= newLength
    }

    // Scales this vector to the length `newLength`, keeping its direction.
    //
    // The current length must not be near zero, which is asserted.
    mtd setLength(newLength: f32)
    {
        .normalize()
        .x *= newLength
        .y *= newLength
    }

    // Scales this vector to unit length in place, or sets it to zero when its length is near zero.
    mtd normalizeOrZero()
    {
        var norm = sqrt((.x * .x) + (.y * .y))
        if Math.isZeroEpsilon(norm)
        {
            .x, .y = 0
            return
        }

        norm = 1 / norm
        .x   *= norm
        .y   *= norm
    }

    // Returns this vector scaled to unit length, or the zero vector when its length is near zero.
    mtd const normalizedOrZero()->Vector2
    {
        var norm = sqrt((.x * .x) + (.y * .y))
        if Math.isZeroEpsilon(norm) do
            return Zero
        norm = 1 / norm
        return Vector2{.x * norm, .y * norm}
    }

    // Returns the component-wise minimum of `a` and `b`.
    func min(a, b: Vector2)->Vector2
    {
        var result: retval
        result.x = Math.min(a.x, b.x)
        result.y = Math.min(a.y, b.y)
        return result
    }

    // Returns the component-wise maximum of `a` and `b`.
    func max(a, b: Vector2)->Vector2
    {
        var result: retval
        result.x = Math.max(a.x, b.x)
        result.y = Math.max(a.y, b.y)
        return result
    }

    // Rounds both components down to integer values in place.
    mtd floor()
    {
        .x = Math.floor(.x)
        .y = Math.floor(.y)
    }

    // Rounds both components up to integer values in place.
    mtd ceil()
    {
        .x = Math.ceil(.x)
        .y = Math.ceil(.y)
    }

    // Rounds both components to the nearest integer values in place.
    //
    // A component halfway between two integers rounds away from zero.
    mtd round()
    {
        .x = Math.round(.x)
        .y = Math.round(.y)
    }

    // Rotates this vector about the origin by `angle`.
    //
    // A positive angle turns the X axis toward the Y axis.
    mtd rotateBy(angle: Math.Angle)
    {
        let s  = Math.sin(angle.radians)
        let c  = Math.cos(angle.radians)
        let tx = .x
        let ty = .y
        .x = (c * tx) - (s * ty)
        .y = (s * tx) + (c * ty)
    }

    // Returns the cosine of the angle between this vector and `other`, within [-1, 1].
    //
    // The result is NaN when either vector is zero.
    mtd const angleCosineTo(other: Vector2)->f32
    {
        // Rounding can push the ratio for nearly parallel vectors just past 1 in magnitude,
        // outside the domain of acos. The comparisons leave a NaN untouched.
        let cosine = .dot(other) / (.length() * other.length())
        return cosine > 1 ? 1 : (cosine < -1 ? -1 : cosine)
    }

    // Returns the unsigned angle between this vector and `other`, in radians within [0, π].
    //
    // The result is NaN when either vector is zero.
    mtd const angleTo(other: Vector2)->f32 => Math.acos(.angleCosineTo(other))

    // Returns the angle that turns this vector onto `other`, in radians within [0, 2π).
    //
    // The angle is measured in the direction that turns the X axis toward the Y axis. The result
    // is NaN when either vector is zero.
    mtd const orientedAngleTo(other: Vector2)->f32
    {
        var angle = Math.acos(.angleCosineTo(other))
        let sign  = (.x * other.y) - (.y * other.x)
        if sign < 0 do
            angle = ConstF32.TwoPi - angle
        return angle
    }

    // Returns the linear interpolation from `src` to `dst` at `factor`.
    //
    // A `factor` of 0 gives `src` and 1 gives `dst`. It is not clamped, so other values extrapolate.
    func lerp(src, dst: Vector2, factor: f32)->Vector2
    {
        var result: retval
        result.x = Math.lerp(src.x, dst.x, factor)
        result.y = Math.lerp(src.y, dst.y, factor)
        return result
    }

    // Clamps every component in place between the matching components of `min` and `max`.
    mtd clamp(min, max: Vector2)
    {
        .x = Math.clamp(.x, min.x, max.x)
        .y = Math.clamp(.y, min.y, max.y)
    }

    // Returns this vector with every component clamped between the matching components of `min` and `max`.
    mtd const clamped(min, max: Vector2)->Vector2 => Vector2{Math.clamp(.x, min.x, max.x), Math.clamp(.y, min.y, max.y)}

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
    mtd const clampedLength(minLength, maxLength: f32)->Vector2
    {
        let len = .length()
        if len < minLength do
            return .normalized() * minLength
        elif len > maxLength do
            return .normalized() * maxLength
        return me
    }

    // Returns this vector with the absolute value of every component.
    mtd const absolute()->Vector2 => Vector2{Math.abs(.x), Math.abs(.y)}

    // Replaces both components with their absolute values.
    mtd makeAbsolute()
    {
        .x = Math.abs(.x)
        .y = Math.abs(.y)
    }

    // Returns this vector turned a quarter turn from the X axis toward the Y axis.
    //
    // That is counter-clockwise when Y points up. The length is unchanged.
    mtd const perpendicular()->Vector2 => Vector2{-.y, .x}

    // Returns this vector turned a quarter turn from the Y axis toward the X axis.
    //
    // That is clockwise when Y points up. The length is unchanged.
    mtd const perpendicularClockwise()->Vector2 => Vector2{.y, -.x}

    // Returns the projection of this vector onto the direction of `other`.
    //
    // The result is the zero vector when `other` is near zero.
    mtd const projectedOnto(other: Vector2)->Vector2
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
    mtd const reflected(normal: Vector2)->Vector2
    {
        let scale = 2.0 * .dot(normal)
        return Vector2{.x - normal.x * scale, .y - normal.y * scale}
    }

    // Returns the sign of every component, as -1, 0, or 1.
    mtd const sign()->Vector2 => Vector2{Math.sign(.x), Math.sign(.y)}

    // Returns whether every component is finite, neither infinite nor NaN.
    mtd const isFinite()->bool => Math.isFinite(.x) and Math.isFinite(.y)

    // Returns whether any component is NaN.
    mtd const isNaN()->bool => Math.isNaN(.x) or Math.isNaN(.y)

    // Moves this vector toward `target` by at most `maxDistance`.
    //
    // It lands exactly on `target` once that is within `maxDistance`.
    mtd moveTowards(target: Vector2, maxDistance: f32)
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
    mtd const movedTowards(target: Vector2, maxDistance: f32)->Vector2
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
    func smoothDamp(current, target: Vector2, currentVelocity: *Vector2, smoothTime, deltaTime: f32)->Vector2
    {
        var result: retval
        result.x = Math.smoothDamp(current.x, target.x, &currentVelocity.x, smoothTime, deltaTime)
        result.y = Math.smoothDamp(current.y, target.y, &currentVelocity.y, smoothTime, deltaTime)
        return result
    }

    // Creates a vector from the polar coordinates `angle`, in radians, and `radius`.
    //
    // The angle is measured from the positive X axis toward the Y axis.
    func fromPolar(angle, radius: f32)->Vector2 => Vector2{radius * cos(angle), radius * sin(angle)}

    // Returns the polar coordinates of this vector: its angle in radians within [-π, π], and its length.
    mtd const toPolar()->{ angle: f32, radius: f32 } => {Math.atan2(.y, .x), .length()}

    // Returns the angle of this vector from the positive X axis, in radians within [-π, π].
    //
    // A positive angle turns toward the Y axis.
    mtd const toAngle()->f32 => Math.atan2(.y, .x)

    // Turns this vector to the direction `angle`, in radians, keeping its length.
    //
    // The angle is measured from the positive X axis toward the Y axis.
    mtd setAngle(angle: f32)
    {
        let magnitude = .length()
        .x = magnitude * Math.cos(angle)
        .y = magnitude * Math.sin(angle)
    }
}
