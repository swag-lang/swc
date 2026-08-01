#global namespace Math
#global public

// Stores a 3 by 3 floating-point matrix.
#[Serialization.Final]
struct Matrix3x3
{
    m: [3, 3] f32     // Matrix elements addressed by two indices.
}

impl Matrix3x3
{
    // Creates an identity matrix.
    func createIdentity()->Matrix3x3
    {
        var result: retval
        result.setIdentity()
        return result
    }

    // Replaces every element with the identity matrix.
    mtd setIdentity()
    {
        @init(me, 1)
        .m[0, 0] = 1
        .m[1, 1] = 1
        .m[2, 2] = 1
    }
}
