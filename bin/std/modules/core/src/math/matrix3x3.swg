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
}
