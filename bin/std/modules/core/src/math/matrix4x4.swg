#global namespace Math
#global public

private func determinant3x3(a, b, c, d, e, f, g, h, i: f32)->f32
{
    return a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g)
}

// Stores a 4 by 4 floating-point matrix in row-major order.
//
// `m[row, column]` addresses an element. Matrices transform row vectors, so
// [[Core.Math.Matrix4x4.multiplied]] applies `A` first and then `B`. OpenGL reads this row-major
// storage as column-major, which represents the equivalent transposed matrix under its
// column-vector convention.
#[Serialization.Final]
struct Matrix4x4
{
    public m: [4, 4] f32     // Matrix elements addressed by row, then column.
}

impl Matrix4x4
{
    // Creates a translation matrix for row-vector transforms.
    func createTranslation(offset: Vector3)->Matrix4x4
    {
        var result = Matrix4x4.createIdentity()
        result.m[3, 0] = offset.x
        result.m[3, 1] = offset.y
        result.m[3, 2] = offset.z
        return result
    }

    // Creates a scale matrix.
    func createScale(scale: Vector3)->Matrix4x4
    {
        var result = Matrix4x4.createIdentity()
        result.m[0, 0] = scale.x
        result.m[1, 1] = scale.y
        result.m[2, 2] = scale.z
        return result
    }

    // Creates a right-handed perspective projection matrix with an OpenGL depth range of [-1, 1].
    //
    // `verticalFov` is in radians; `aspect` and `nearPlane` must be positive and `farPlane` must exceed `nearPlane`.
    func createPerspective(verticalFov, aspect, nearPlane, farPlane: f32)->Matrix4x4
    {
        Swag.assert(verticalFov > 0 and verticalFov < ConstF32.Pi)
        Swag.assert(aspect > 0 and nearPlane > 0 and farPlane > nearPlane)
        let focal  = 1 / tan(verticalFov / 2)
        var result = Matrix4x4.createIdentity()
        result.m[0, 0] = focal / aspect
        result.m[1, 1] = focal
        result.m[2, 2] = (farPlane + nearPlane) / (nearPlane - farPlane)
        result.m[2, 3] = -1
        result.m[3, 2] = (2 * farPlane * nearPlane) / (nearPlane - farPlane)
        result.m[3, 3] = 0
        return result
    }

    // Creates a right-handed orthographic projection with an OpenGL depth range of [-1, 1].
    //
    // Each opposing bound pair must differ.
    func createOrthographic(left, right, bottom, top, nearPlane, farPlane: f32)->Matrix4x4
    {
        Swag.assert(left != right and bottom != top and nearPlane != farPlane)
        var result = Matrix4x4.createIdentity()
        result.m[0, 0] = 2 / (right - left)
        result.m[1, 1] = 2 / (top - bottom)
        result.m[2, 2] = -2 / (farPlane - nearPlane)
        result.m[3, 0] = -(right + left) / (right - left)
        result.m[3, 1] = -(top + bottom) / (top - bottom)
        result.m[3, 2] = -(farPlane + nearPlane) / (farPlane - nearPlane)
        result.m[3, 3] = 1
        return result
    }

    // Creates a right-handed view matrix looking from `eye` toward `target`.
    //
    // `up` must not be parallel to the viewing direction.
    func createLookAt(eye, target, up: Vector3)->Matrix4x4
    {
        let forward  = (target - eye).normalized()
        let right    = forward.cross(up).normalized()
        let actualUp = right.cross(forward)
        var result   = Matrix4x4.createIdentity()
        result.m[0, 0] = right.x
        result.m[1, 0] = right.y
        result.m[2, 0] = right.z
        result.m[0, 1] = actualUp.x
        result.m[1, 1] = actualUp.y
        result.m[2, 1] = actualUp.z
        result.m[0, 2] = -forward.x
        result.m[1, 2] = -forward.y
        result.m[2, 2] = -forward.z
        result.m[3, 0] = -right.dot(eye)
        result.m[3, 1] = -actualUp.dot(eye)
        result.m[3, 2] = forward.dot(eye)
        result.m[3, 3] = 1
        return result
    }

    // Creates a transform that scales, then rotates, then translates row vectors.
    func createTRS(translation: Vector3, rotation: Quaternion, scale: Vector3)->Matrix4x4
    {
        let scaled = Matrix4x4.createScale(scale).multiplied(rotation.toMatrix4x4())
        return scaled.multiplied(Matrix4x4.createTranslation(translation))
    }

    // Creates an identity matrix.
    func createIdentity()->Matrix4x4
    {
        var result: #returntype
        result.setIdentity()
        return result
    }

    // Sets this matrix to the identity.
    mtd setIdentity()
    {
        Swag.init(me, 1)
        .m[0, 0] = 1
        .m[1, 1] = 1
        .m[2, 2] = 1
        .m[3, 3] = 1
    }

    // Returns the product of this matrix and `other`.
    //
    // The result maps a vector the same way as applying this matrix first and `other` second with
    // [[Core.Math.Matrix4x4.transformVector]].
    mtd const multiplied(other: Matrix4x4)->Matrix4x4
    {
        var result: #returntype
        for row in 4
        {
            for column in 4
            {
                var value: f32
                for inner in 4 do
                    value += .m[row, inner] * other.m[inner, column]
                result.m[row, column] = value
            }
        }

        return result
    }

    // Transforms a homogeneous [[Core.Math.Vector4]] row vector without dividing by its final
    // component.
    //
    // Use `w = 1` for a position and `w = 0` for a direction. The result remains homogeneous;
    // divide its XYZ components by W separately when applying a projective transform.
    mtd const transformVector(vector: Vector4)->Vector4
    {
        return Vector4{
            .m[0, 0] * vector.x + .m[1, 0] * vector.y + .m[2, 0] * vector.z + .m[3, 0] * vector.w,
            .m[0, 1] * vector.x + .m[1, 1] * vector.y + .m[2, 1] * vector.z + .m[3, 1] * vector.w,
            .m[0, 2] * vector.x + .m[1, 2] * vector.y + .m[2, 2] * vector.z + .m[3, 2] * vector.w,
            .m[0, 3] * vector.x + .m[1, 3] * vector.y + .m[2, 3] * vector.z + .m[3, 3] * vector.w}
    }

    // Returns the product of `a` and `b`, applying `a` first and then `b` to row vectors.
    func multiply(a, b: Matrix4x4)->Matrix4x4 => a.multiplied(b)

    // Returns this matrix with rows and columns exchanged.
    mtd const transposed()->Matrix4x4
    {
        var result: #returntype
        for row in 4
        {
            for column in 4 do
                result.m[row, column] = .m[column, row]
        }

        return result
    }

    // Returns the determinant of this matrix.
    mtd const determinant()->f32
    {
        let a00 = .m[0, 0]
        let a01 = .m[0, 1]
        let a02 = .m[0, 2]
        let a03 = .m[0, 3]
        let a10 = .m[1, 0]
        let a11 = .m[1, 1]
        let a12 = .m[1, 2]
        let a13 = .m[1, 3]
        let a20 = .m[2, 0]
        let a21 = .m[2, 1]
        let a22 = .m[2, 2]
        let a23 = .m[2, 3]
        let a30 = .m[3, 0]
        let a31 = .m[3, 1]
        let a32 = .m[3, 2]
        let a33 = .m[3, 3]

        let minor0 = a11 * (a22 * a33 - a23 * a32) -
                     a12 * (a21 * a33 - a23 * a31) +
                     a13 * (a21 * a32 - a22 * a31)
        let minor1 = a10 * (a22 * a33 - a23 * a32) -
                     a12 * (a20 * a33 - a23 * a30) +
                     a13 * (a20 * a32 - a22 * a30)
        let minor2 = a10 * (a21 * a33 - a23 * a31) -
                     a11 * (a20 * a33 - a23 * a30) +
                     a13 * (a20 * a31 - a21 * a30)
        let minor3 = a10 * (a21 * a32 - a22 * a31) -
                     a11 * (a20 * a32 - a22 * a30) +
                     a12 * (a20 * a31 - a21 * a30)
        return a00 * minor0 - a01 * minor1 + a02 * minor2 - a03 * minor3
    }

    // Replaces this matrix with its inverse; the determinant must be nonzero.
    mtd invert()
    {
        me[] = me.inverted()
    }

    // Returns the inverse matrix; its determinant must be nonzero.
    mtd const inverted()->Matrix4x4
    {
        let a00 = .m[0, 0]
        let a01 = .m[0, 1]
        let a02 = .m[0, 2]
        let a03 = .m[0, 3]
        let a10 = .m[1, 0]
        let a11 = .m[1, 1]
        let a12 = .m[1, 2]
        let a13 = .m[1, 3]
        let a20 = .m[2, 0]
        let a21 = .m[2, 1]
        let a22 = .m[2, 2]
        let a23 = .m[2, 3]
        let a30 = .m[3, 0]
        let a31 = .m[3, 1]
        let a32 = .m[3, 2]
        let a33 = .m[3, 3]

        var result: #returntype
        result.m[0, 0] = determinant3x3(a11, a12, a13, a21, a22, a23, a31, a32, a33)
        result.m[0, 1] = -determinant3x3(a01, a02, a03, a21, a22, a23, a31, a32, a33)
        result.m[0, 2] = determinant3x3(a01, a02, a03, a11, a12, a13, a31, a32, a33)
        result.m[0, 3] = -determinant3x3(a01, a02, a03, a11, a12, a13, a21, a22, a23)
        result.m[1, 0] = -determinant3x3(a10, a12, a13, a20, a22, a23, a30, a32, a33)
        result.m[1, 1] = determinant3x3(a00, a02, a03, a20, a22, a23, a30, a32, a33)
        result.m[1, 2] = -determinant3x3(a00, a02, a03, a10, a12, a13, a30, a32, a33)
        result.m[1, 3] = determinant3x3(a00, a02, a03, a10, a12, a13, a20, a22, a23)
        result.m[2, 0] = determinant3x3(a10, a11, a13, a20, a21, a23, a30, a31, a33)
        result.m[2, 1] = -determinant3x3(a00, a01, a03, a20, a21, a23, a30, a31, a33)
        result.m[2, 2] = determinant3x3(a00, a01, a03, a10, a11, a13, a30, a31, a33)
        result.m[2, 3] = -determinant3x3(a00, a01, a03, a10, a11, a13, a20, a21, a23)
        result.m[3, 0] = -determinant3x3(a10, a11, a12, a20, a21, a22, a30, a31, a32)
        result.m[3, 1] = determinant3x3(a00, a01, a02, a20, a21, a22, a30, a31, a32)
        result.m[3, 2] = -determinant3x3(a00, a01, a02, a10, a11, a12, a30, a31, a32)
        result.m[3, 3] = determinant3x3(a00, a01, a02, a10, a11, a12, a20, a21, a22)

        let det = .determinant()
        Swag.assert(det != 0)
        for row in 4
        {
            for column in 4 do
                result.m[row, column] /= det
        }

        return result
    }

    // Transforms a point and divides by its homogeneous W coordinate.
    mtd const transformPoint(point: Vector3)->Vector3
    {
        let transformed = .transformVector(Vector4{point.x, point.y, point.z, 1})
        Swag.assert(transformed.w != 0)
        return Vector3{transformed.x / transformed.w, transformed.y / transformed.w, transformed.z / transformed.w}
    }

    // Transforms a direction without applying translation.
    mtd const transformDirection(direction: Vector3)->Vector3
    {
        let transformed = .transformVector(Vector4{direction.x, direction.y, direction.z, 0})
        return Vector3{transformed.x, transformed.y, transformed.z}
    }

    // Transforms a normal with the inverse transpose of this matrix's linear part.
    //
    // This preserves perpendicularity under nonuniform scale. The matrix must be affine and invertible.
    mtd const transformNormal(normal: Vector3)->Vector3
    {
        return .inverted().transposed().transformDirection(normal)
    }
}
