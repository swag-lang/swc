#global namespace Random
#global public

// George Marsaglia's CMWC (Complementary Multiply With Carry) 4096 random number generator.
#[Swag.Opaque]
struct ComplementaryMultiplyWithCarry4096
{
    internal
    {
        state: [4096] u32
        carry: u32
        index: u32 = 4096
    }
}

impl ComplementaryMultiplyWithCarry4096
{
    // Seeds the generator with a 32-bit unsigned value.
    mtd seedU32(value: u32)
    {
        var generator: MultiplyWithCarry32
        generator.seedU32(value)
        for stateIndex in (.state).count do
            .state[stateIndex] = generator.nextU32()
        .index = 4095
        .carry = value % 809430660
    }

    // Generates the next 32-bit unsigned random number.
    #[Swag.Safety(.Overflow, false)]
    mtd nextU32()->u32
    {
        const a = 18782'u64
        const r = 0xFFFFFFFE

        // Be sure we have seeded
        if .index > 4095 do
            .seedU32(362436)

        .index = (.index + 1) & 4095
        let t = a * .state[.index] + .carry
        .carry = cast(u32) (t >> 32)
        var x = t + .carry
        if x < .carry do
            x, .carry += 1
        let v = cast(u32) (r - x)
        .state[.index] = v
        return v
    }
}
