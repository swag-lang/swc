#global namespace Math
#global public

// Stores a 2 by 2 floating-point matrix in row-major order and transforms row vectors.
#[Serialization.Final]
struct Matrix2x2
{
    public m: [2, 2] f32     // Matrix elements addressed by row, then column.
}

impl Matrix2x2
{
    // Creates the identity matrix.
    func createIdentity()->Matrix2x2
    {
        var result: #returntype
        result.setIdentity()
        return result
    }

    // Creates a 2D scale matrix.
    func createScale(scale: Vector2)->Matrix2x2
    {
        return Matrix2x2{[[scale.x, 0], [0, scale.y]]}
    }

    // Creates a counterclockwise 2D rotation matrix; `angle` is in radians.
    func createRotation(angle: Angle)->Matrix2x2
    {
        let cosine = Math.cos(angle.radians)
        let sine = Math.sin(angle.radians)
        return Matrix2x2{[[cosine, sine], [-sine, cosine]]}
    }

    // Sets this matrix to the identity.
    mtd setIdentity()
    {
        Swag.init(me, 1)
        .m[0, 0] = 1
        .m[1, 1] = 1
    }

    // Returns the product of this matrix and `other`.
    mtd const multiplied(other: Matrix2x2)->Matrix2x2
    {
        return Matrix2x2{[
            [.m[0, 0] * other.m[0, 0] + .m[0, 1] * other.m[1, 0],
             .m[0, 0] * other.m[0, 1] + .m[0, 1] * other.m[1, 1]],
            [.m[1, 0] * other.m[0, 0] + .m[1, 1] * other.m[1, 0],
             .m[1, 0] * other.m[0, 1] + .m[1, 1] * other.m[1, 1]]]}
    }

    // Transforms a 2D vector without translation.
    mtd const transformVector(vector: Vector2)->Vector2
    {
        return Vector2{
            .m[0, 0] * vector.x + .m[1, 0] * vector.y,
            .m[0, 1] * vector.x + .m[1, 1] * vector.y}
    }

    // Returns the determinant of this matrix.
    mtd const determinant()->f32 => .m[0, 0] * .m[1, 1] - .m[0, 1] * .m[1, 0]

    // Replaces this matrix with its inverse; its determinant must be nonzero.
    mtd invert()
    {
        let determinant = .determinant()
        Swag.assert(determinant != 0)
        let source = me[]
        .m[0, 0] = source.m[1, 1] / determinant
        .m[0, 1] = -source.m[0, 1] / determinant
        .m[1, 0] = -source.m[1, 0] / determinant
        .m[1, 1] = source.m[0, 0] / determinant
    }

    // Returns the inverse matrix; its determinant must be nonzero.
    mtd const inverted()->Matrix2x2
    {
        var result = me[]
        result.invert()
        return result
    }
}
