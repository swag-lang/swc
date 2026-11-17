#global namespace Math
#global public

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
}
