// George Marsaglia's MWC (multiply with carry) generator.
#global namespace Random
#global public

// Represents mwc.
struct MWC
{
    w: u32 = 521288629     // W component.
    z: u32 = 362436069     // Z component.
}

impl MWC
{
    // Performs the seed u32 operation.
    mtd seedU32(value: u32)
    {
        .w = value != 0 ? value : 521288629
        .z = 362436069
    }

    // Performs the seed u32 operation.
    mtd seedU32(value1, value2: u32)
    {
        .w = value1 != 0 ? value1 : 521288629
        .z = value2 != 0 ? value2 : 362436069
    }

    // Performs the next u32 operation.
    #[Swag.Safety(.Overflow, false)]
    mtd nextU32()->u32
    {
        .z = 36969 * (.z & 0xFFFF) + (.z >> 16)
        .w = 18000 * (.w & 0xFFFF) + (.w >> 16)
        return (.z << 16) + .w
    }
}
