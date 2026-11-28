// George Marsaglia's multiply-with-carry generator.
#global namespace Random
#global public

// George Marsaglia's 32-bit multiply-with-carry generator.
#[Swag.Opaque]
struct MultiplyWithCarry32
{
    internal
    {
        w: u32 = 521288629
        z: u32 = 362436069
    }
}

impl MultiplyWithCarry32
{
    // Seeds both components from one 32-bit value.
    mtd seedU32(value: u32)
    {
        .w = value != 0 ? value : 521288629
        .z = 362436069
    }

    // Seeds the two state components independently.
    mtd seedU32(value1, value2: u32)
    {
        .w = value1 != 0 ? value1 : 521288629
        .z = value2 != 0 ? value2 : 362436069
    }

    // Returns the next pseudorandom 32-bit value.
    #[Swag.Safety(.Overflow, false)]
    mtd nextU32()->u32
    {
        .z = 36969 * (.z & 0xFFFF) + (.z >> 16)
        .w = 18000 * (.w & 0xFFFF) + (.w >> 16)
        return (.z << 16) + .w
    }
}
