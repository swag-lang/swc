#global namespace Math
#global public

// Stores a 4 by 4 floating-point matrix.
#[Serialization.Final]
struct Matrix4x4
{
    m: [4, 4] f32     // Matrix elements addressed by two indices.
}

impl Matrix4x4
{
    // Creates an identity matrix.
    func createIdentity()->Matrix4x4
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
        .m[3, 3] = 1
    }
}
