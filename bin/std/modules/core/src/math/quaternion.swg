#global namespace Math
#global public

// Stores a quaternion with vector components `x`, `y`, `z` and scalar component `w`.
//
// Unit quaternions represent 3D rotations. `multiply` composes rotations so that the returned
// quaternion applies `other` first and this quaternion second.
#[Serialization.Final]
struct Quaternion
{
    public x, y, z, w: f32     // Vector part (x, y, z) and scalar part (w).
}

impl Quaternion
{
    const Identity = Quaternion{0, 0, 0, 1} // Rotation that leaves vectors unchanged

    // Returns the dot product of this quaternion and `other`.
    mtd const dot(other: Quaternion)->f32 => .x * other.x + .y * other.y + .z * other.z + .w * other.w

    // Returns the squared magnitude of this quaternion.
    mtd const lengthSquared()->f32 => .dot(me)

    // Returns the magnitude of this quaternion.
    mtd const length()->f32
    {
        if Math.isNaN(.x) or Math.isNaN(.y) or Math.isNaN(.z) or Math.isNaN(.w) do
            return Swag.F32.NaN
        let scale = Math.max(Math.max(Math.abs(.x), Math.abs(.y)), Math.max(Math.abs(.z), Math.abs(.w)))
        if scale == 0 do
            return 0
        if not Math.isFinite(scale) do
            return Swag.F32.Inf
        let x = .x / scale
        let y = .y / scale
        let z = .z / scale
        let w = .w / scale
        return scale * sqrt(x * x + y * y + z * z + w * w)
    }

    // Returns a unit quaternion, or identity for zero or non-finite components.
    mtd const normalized()->Quaternion
    {
        if not Math.isFinite(.x) or not Math.isFinite(.y) or not Math.isFinite(.z) or not Math.isFinite(.w) do
            return Identity
        let scale = Math.max(Math.max(Math.abs(.x), Math.abs(.y)), Math.max(Math.abs(.z), Math.abs(.w)))
        if scale == 0 or not Math.isFinite(scale) do
            return Identity
        let x = .x / scale
        let y = .y / scale
        let z = .z / scale
        let w = .w / scale
        let inverseLength = 1 / sqrt(x * x + y * y + z * z + w * w)
        return Quaternion{x * inverseLength, y * inverseLength, z * inverseLength, w * inverseLength}
    }

    // Returns the conjugate, which negates the vector part.
    mtd const conjugate()->Quaternion => Quaternion{-.x, -.y, -.z, .w}

    // Multiplies quaternions using the Hamilton product, composing rotations for unit inputs.
    #[Inline]
    mtd(op: Swag.Operator) const opBinary(other: Quaternion)->Quaternion
        where op == .Mul
    {
        return .multiply(other)
    }

    // Returns the multiplicative inverse, or identity for zero or non-finite components.
    mtd const inverse()->Quaternion
    {
        if not Math.isFinite(.x) or not Math.isFinite(.y) or not Math.isFinite(.z) or not Math.isFinite(.w) do
            return Identity
        let scale = Math.max(Math.max(Math.abs(.x), Math.abs(.y)), Math.max(Math.abs(.z), Math.abs(.w)))
        if scale == 0 or not Math.isFinite(scale) do
            return Identity
        let x = .x / scale
        let y = .y / scale
        let z = .z / scale
        let w = .w / scale
        let norm = (x * x + y * y + z * z + w * w) * scale
        return Quaternion{-x / norm, -y / norm, -z / norm, w / norm}
    }

    // Returns the Hamilton product; for unit quaternions this composes rotations.
    mtd const multiply(other: Quaternion)->Quaternion
    {
        return Quaternion{
            .w * other.x + .x * other.w + .y * other.z - .z * other.y,
            .w * other.y - .x * other.z + .y * other.w + .z * other.x,
            .w * other.z + .x * other.y - .y * other.x + .z * other.w,
            .w * other.w - .x * other.x - .y * other.y - .z * other.z}
    }

    // Rotates `vector` by this quaternion; the quaternion is normalized before use.
    mtd const rotate(vector: Vector3)->Vector3
    {
        let q = .normalized()
        let imaginary = Vector3{q.x, q.y, q.z}
        let twiceCross = imaginary.cross(vector) * 2
        return vector + twiceCross * q.w + imaginary.cross(twiceCross)
    }

    // Converts this rotation to a row-major 4x4 matrix suitable for row-vector transforms.
    mtd const toMatrix4x4()->Matrix4x4
    {
        let q = .normalized()
        let xx = q.x * q.x
        let yy = q.y * q.y
        let zz = q.z * q.z
        let xy = q.x * q.y
        let xz = q.x * q.z
        let yz = q.y * q.z
        let wx = q.w * q.x
        let wy = q.w * q.y
        let wz = q.w * q.z
        var result = Matrix4x4.createIdentity()
        result.m[0, 0] = 1 - 2 * (yy + zz)
        result.m[1, 0] = 2 * (xy - wz)
        result.m[2, 0] = 2 * (xz + wy)
        result.m[0, 1] = 2 * (xy + wz)
        result.m[1, 1] = 1 - 2 * (xx + zz)
        result.m[2, 1] = 2 * (yz - wx)
        result.m[0, 2] = 2 * (xz - wy)
        result.m[1, 2] = 2 * (yz + wx)
        result.m[2, 2] = 1 - 2 * (xx + yy)
        return result
    }

    // Converts this rotation to an axis and angle in radians. Identity uses the X axis and zero angle.
    mtd const toAxisAngle()->{ axis: Vector3, angle: f32 }
    {
        let q = .normalized()
        let angle = 2 * Math.acos(Math.clamp(q.w, -1'f32, 1'f32))
        let sineHalf = sqrt(Math.max(0'f32, 1 - q.w * q.w))
        if sineHalf <= ConstF32.Epsilon do
            return {axis: Vector3.UnitX, angle: 0}
        return {axis: Vector3{q.x, q.y, q.z} / sineHalf, angle: angle}
    }

    // Creates a rotation of `angle` radians about `axis`; a zero axis returns identity.
    func fromAxisAngle(axis: Vector3, angle: f32)->Quaternion
    {
        let unitAxis = axis.normalizedOrZero()
        if unitAxis.isZero() do
            return Identity
        let halfAngle = angle * 0.5
        let sine = Math.sin(halfAngle)
        return Quaternion{unitAxis.x * sine, unitAxis.y * sine, unitAxis.z * sine, Math.cos(halfAngle)}
    }

    // Creates the shortest rotation that maps `from` onto `target`; zero inputs return identity.
    func fromToRotation(from, target: Vector3)->Quaternion
    {
        let start = from.normalizedOrZero()
        let finish = target.normalizedOrZero()
        if start.isZero() or finish.isZero() do
            return Identity
        let cosine = Math.clamp(start.dot(finish), -1'f32, 1'f32)
        if cosine < -0.999999'f32
        {
            let absolute = start.absolute()
            var basis = Vector3.UnitZ
            if absolute.x <= absolute.y and absolute.x <= absolute.z do
                basis = Vector3.UnitX
            else
            {
                if absolute.y <= absolute.z do
                    basis = Vector3.UnitY
            }
            return fromAxisAngle(start.cross(basis), ConstF32.Pi)
        }
        let axis = start.cross(finish)
        return Quaternion{axis.x, axis.y, axis.z, 1 + cosine}.normalized()
    }

    // Creates a rotation from X, Y, and Z Euler angles in radians, applied in that order.
    func fromEulerXYZ(angles: Vector3)->Quaternion
    {
        let half = angles * 0.5
        let sx = Math.sin(half.x)
        let cx = Math.cos(half.x)
        let sy = Math.sin(half.y)
        let cy = Math.cos(half.y)
        let sz = Math.sin(half.z)
        let cz = Math.cos(half.z)
        let x = Quaternion{sx, 0, 0, cx}
        let y = Quaternion{0, sy, 0, cy}
        let z = Quaternion{0, 0, sz, cz}
        return z.multiply(y).multiply(x).normalized()
    }

    // Interpolates between two rotations along the shortest arc.
    func slerp(from, target: Quaternion, factor: f32)->Quaternion
    {
        let start = from.normalized()
        var finish = target.normalized()
        var cosine = start.dot(finish)
        if cosine < 0
        {
            finish = Quaternion{-finish.x, -finish.y, -finish.z, -finish.w}
            cosine = -cosine
        }

        if cosine > 0.9995
        {
            let blended = Quaternion{
                start.x + factor * (finish.x - start.x),
                start.y + factor * (finish.y - start.y),
                start.z + factor * (finish.z - start.z),
                start.w + factor * (finish.w - start.w)}
            return blended.normalized()
        }

        let angle = Math.acos(Math.clamp(cosine, -1'f32, 1'f32))
        let sine = Math.sin(angle)
        let fromWeight = Math.sin((1 - factor) * angle) / sine
        let toWeight = Math.sin(factor * angle) / sine
        return Quaternion{
            start.x * fromWeight + finish.x * toWeight,
            start.y * fromWeight + finish.y * toWeight,
            start.z * fromWeight + finish.z * toWeight,
            start.w * fromWeight + finish.w * toWeight}
    }
}
