#global namespace Random
#global public

// Produces pseudorandom values from the selected algorithm.
#[Swag.Opaque]
struct(T = MultiplyWithCarry32) Generator
{
    // The generator state and whether it was seeded. Seed and draw through the methods:
    // reading a raw state tells nothing, and writing one can produce a degenerate sequence.
    private
    {
        rng:      T        // State of the underlying generator.
        seedDone: bool     // Whether a seed was applied, so the first draw can seed lazily.
    }
}

impl Generator
{
    // Seed random generator with a 32 bits value
    #[Swag.Inline]
    mtd seedU32(seed: u32)
    {
        .seedDone = true
        #static if #defined(T.seedU32) do
            return .rng.seedU32(seed)
        else do
            return .rng.seedU64(cast(u64) seed)
    }

    // Seed random generator with a 64 bits value
    #[Swag.Inline]
    mtd seedU64(seed: u64)
    {
        .seedDone = true
        #static if #defined(T.seedU64) do
            return .rng.seedU64(seed)
        else do
            return .rng.seedU32(cast #wrap (u32) seed)
    }

    // Returns an unsigned 32 bits random value
    #[Swag.Inline]
    mtd nextU32()->u32
    {
        if !.seedDone do
            .seedAutomatically()

        #static if #defined(T.nextU32) do
            return .rng.nextU32()
        else do
            return cast #wrap (u32) .rng.nextU64()
    }

    // Returns an unsigned 64 bits random value
    #[Swag.Inline]
    mtd nextU64()->u64
    {
        if !.seedDone do
            .seedAutomatically()

        #static if #defined(T.nextU64) do
            return .rng.nextU64()
        else do
            return (cast(u64) .rng.nextU32() << 32) | .rng.nextU32()
    }

    // Seeds the generator from the current clock and thread.
    mtd seedAutomatically()
    {
        .seedU64(Time.monotonicMicroseconds() ^ Env.Process.currentThreadId())
    }

    // Returns a signed 32 bits random value
    #[Swag.Inline]
    mtd nextS32()->s32
    {
        return cast #bit (s32) .nextU32()
    }

    // Returns a signed 64 bits random value
    #[Swag.Inline]
    mtd nextS64()->s64
    {
        return cast #bit (s64) .nextU64()
    }

    // Range is [0..1[, so 1.0 will never be returned
    #[Swag.Inline]
    mtd nextF32()->f32
    {
        return cast(f32) (.nextU32() >> 8) * (1'f32 / 16777216'f32)
    }

    // Range is [0..1[, so 1.0 will never be returned
    #[Swag.Inline]
    mtd nextF64()->f64
    {
        return cast(f64) (.nextU64() >> 11) * (1'f64 / 9007199254740992'f64)
    }

    // Returns an unsigned random value in a given range
    // 'max' is excluded
    mtd nextU32(min, max: u32)->u32
    {
        Debug.assert(max > min, "[[max]] must be greater than [[min]]")
        let range = max - min
        let limit = Swag.U32.Max - Swag.U32.Max % range
        var value = .nextU32()
        while value >= limit do
            value = .nextU32()
        value %= range
        return min + value
    }

    // Returns an unsigned random value in a given range
    // 'max' is excluded
    mtd nextU64(min, max: u64)->u64
    {
        Debug.assert(max > min, "[[max]] must be greater than [[min]]")
        let range = max - min
        let limit = Swag.U64.Max - Swag.U64.Max % range
        var value = .nextU64()
        while value >= limit do
            value = .nextU64()
        value %= range
        return min + value
    }

    // Returns a signed random value in a given range
    // 'max' is excluded
    #[Swag.Safety(.Overflow, false)]
    mtd nextS32(min, max: s32)->s32
    {
        Debug.assert(max > min, "[[max]] must be greater than [[min]]")
        let minBits = cast #bit (u32) min
        let maxBits = cast #bit (u32) max
        let range   = cast #wrap (u32) (maxBits - minBits)
        let limit   = Swag.U32.Max - Swag.U32.Max % range
        var value   = .nextU32()
        while value >= limit do
            value = .nextU32()
        value %= range
        return cast #bit (s32) cast #wrap (u32) (minBits + value)
    }

    // Returns a signed random value in a given range
    // 'max' is excluded
    #[Swag.Safety(.Overflow, false)]
    mtd nextS64(min, max: s64)->s64
    {
        Debug.assert(max > min, "[[max]] must be greater than [[min]]")
        let minBits = cast #bit (u64) min
        let maxBits = cast #bit (u64) max
        let range   = cast #wrap (u64) (maxBits - minBits)
        let limit   = Swag.U64.Max - Swag.U64.Max % range
        var value   = .nextU64()
        while value >= limit do
            value = .nextU64()
        value %= range
        return cast #bit (s64) cast #wrap (u64) (minBits + value)
    }

    // Returns a float value in a given range
    // 'max' is excluded
    mtd nextF32(min, max: f32)->f32
    {
        Debug.assert(max > min, "[[max]] must be greater than [[min]]")
        let range = max - min
        let value = .nextF32()
        return min + (value * range)
    }

    // Returns a float value in a given range
    // 'max' is excluded
    mtd nextF64(min, max: f64)->f64
    {
        Debug.assert(max > min, "[[max]] must be greater than [[min]]")
        let range = max - min
        let value = .nextF64()
        return min + (value * range)
    }

    // Returns a random bool
    mtd nextBool()->bool
    {
        return .nextU32(0, 2) == 0 ? false : true
    }

    // Randomizes the order of a slice using Fisher-Yates shuffling.
    mtd(V) shuffle(slice: [..] V)
    {
        let count = @countof(slice)
        if count < 2 do
            return

        let data = @dataof(slice)
        for var index = count - 1; index > 0; index -= 1
        {
            let other = .nextU64(0, index + 1)
            Core.swap(data + index, data + other)
        }
    }
}
