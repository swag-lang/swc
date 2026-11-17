#global namespace Math
#global public

// Stores a 3 by 3 floating-point matrix in row-major order.
//
// `m[row, column]` addresses an element. Matrices transform row vectors, so
// [[Core.Math.Matrix3x3.multiplied]] applies `A` first and then `B`.
#[Serialization.Final]
struct Matrix3x3
{
    public m: [3, 3] f32     // Matrix elements addressed by row, then column.
}

impl Matrix3x3
{
    // Creates a 2D translation matrix for row-vector transforms.
    func createTranslation(offset: Vector2)->Matrix3x3
    {
        var result = Matrix3x3.createIdentity()
        result.m[2, 0] = offset.x
        result.m[2, 1] = offset.y
        return result
    }

    // Creates a 2D scale matrix.
    func createScale(scale: Vector2)->Matrix3x3
    {
        var result = Matrix3x3.createIdentity()
        result.m[0, 0] = scale.x
        result.m[1, 1] = scale.y
        return result
    }

    // Creates a 2D counterclockwise rotation matrix; `angle` is in radians.
    func createRotation(angle: Angle)->Matrix3x3
    {
        let cosine = Math.cos(angle.radians)
        let sine = Math.sin(angle.radians)
        var result = Matrix3x3.createIdentity()
        result.m[0, 0] = cosine
        result.m[0, 1] = sine
        result.m[1, 0] = -sine
        result.m[1, 1] = cosine
        return result
    }

    // Creates an identity matrix.
    func createIdentity()->Matrix3x3
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
    }

    // Returns the product of this matrix and `other`.
    //
    // The result maps a vector the same way as applying this matrix first and `other` second with
    // [[Core.Math.Matrix3x3.transformVector]].
    mtd const multiplied(other: Matrix3x3)->Matrix3x3
    {
        var result: #returntype
        for row in 3
        {
            for column in 3
            {
                var value: f32
                for inner in 3 do
                    value += .m[row, inner] * other.m[inner, column]
                result.m[row, column] = value
            }
        }
        return result
    }

    // Transforms a homogeneous [[Core.Math.Vector3]] without dividing by its final component.
    //
    // Use `z = 1` for a 2D point and `z = 0` for a 2D direction when the matrix represents an
    // affine transform. The result remains homogeneous; divide by `z` separately when the
    // matrix represents a projective transform.
    mtd const transformVector(vector: Vector3)->Vector3
    {
        return Vector3{
            .m[0, 0] * vector.x + .m[1, 0] * vector.y + .m[2, 0] * vector.z,
            .m[0, 1] * vector.x + .m[1, 1] * vector.y + .m[2, 1] * vector.z,
            .m[0, 2] * vector.x + .m[1, 2] * vector.y + .m[2, 2] * vector.z}
    }

    // Transforms a 2D point and divides by its homogeneous component.
    mtd const transformPoint(point: Vector2)->Vector2
    {
        let transformed = .transformVector(Vector3{point.x, point.y, 1})
        Swag.assert(transformed.z != 0)
        return Vector2{transformed.x / transformed.z, transformed.y / transformed.z}
    }

    // Transforms a 2D direction without applying translation.
    mtd const transformDirection(direction: Vector2)->Vector2
    {
        let transformed = .transformVector(Vector3{direction.x, direction.y, 0})
        return Vector2{transformed.x, transformed.y}
    }

    // Transforms a 2D normal with the inverse transpose of this matrix's linear part.
    mtd const transformNormal(normal: Vector2)->Vector2
    {
        let transformed = .inverted().transposed().transformDirection(normal)
        return transformed
    }

    // Returns this matrix with rows and columns exchanged.
    mtd const transposed()->Matrix3x3
    {
        var result: #returntype
        for row in 3
        {
            for column in 3 do
                result.m[row, column] = .m[column, row]
        }
        return result
    }

    // Returns the determinant of this matrix.
    mtd const determinant()->f32
    {
        return .m[0, 0] * (.m[1, 1] * .m[2, 2] - .m[1, 2] * .m[2, 1]) -
               .m[0, 1] * (.m[1, 0] * .m[2, 2] - .m[1, 2] * .m[2, 0]) +
               .m[0, 2] * (.m[1, 0] * .m[2, 1] - .m[1, 1] * .m[2, 0])
    }

    // Replaces this matrix with its inverse; the determinant must be nonzero.
    mtd invert()
    {
        let det = .determinant()
        Swag.assert(det != 0)
        let src = me[]
        let a00 = src.m[0, 0]
        let a01 = src.m[0, 1]
        let a02 = src.m[0, 2]
        let a10 = src.m[1, 0]
        let a11 = src.m[1, 1]
        let a12 = src.m[1, 2]
        let a20 = src.m[2, 0]
        let a21 = src.m[2, 1]
        let a22 = src.m[2, 2]
        .m[0, 0] = (a11 * a22 - a12 * a21) / det
        .m[0, 1] = (a02 * a21 - a01 * a22) / det
        .m[0, 2] = (a01 * a12 - a02 * a11) / det
        .m[1, 0] = (a12 * a20 - a10 * a22) / det
        .m[1, 1] = (a00 * a22 - a02 * a20) / det
        .m[1, 2] = (a02 * a10 - a00 * a12) / det
        .m[2, 0] = (a10 * a21 - a11 * a20) / det
        .m[2, 1] = (a01 * a20 - a00 * a21) / det
        .m[2, 2] = (a00 * a11 - a01 * a10) / det
    }

    // Returns the inverse matrix; its determinant must be nonzero.
    mtd const inverted()->Matrix3x3
    {
        var result = me[]
        result.invert()
        return result
    }
}
