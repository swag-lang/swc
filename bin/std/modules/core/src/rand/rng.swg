#global namespace Random
#global public

// Produces pseudorandom values from the algorithm `T`.
//
// A generator that was never seeded seeds itself from the clock and the current thread on its
// first draw. Seed it explicitly for a reproducible sequence.
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
    // Seeds the generator with a 32-bit value.
    #[Swag.Inline]
    mtd seedU32(seed: u32)
    {
        .seedDone = true
        #static if #defined(T.seedU32) do
            return .rng.seedU32(seed)
        else do
            return .rng.seedU64(cast(u64) seed)
    }

    // Seeds the generator with a 64-bit value.
    #[Swag.Inline]
    mtd seedU64(seed: u64)
    {
        .seedDone = true
        #static if #defined(T.seedU64) do
            return .rng.seedU64(seed)
        else do
            return .rng.seedU32(cast #wrap (u32) seed)
    }

    // Returns the next 32-bit unsigned value.
    #[Swag.Inline]
    mtd nextU32()->u32
    {
        if not .seedDone do
            .seedAutomatically()

        #static if #defined(T.nextU32) do
            return .rng.nextU32()
        else do
            return cast #wrap (u32) .rng.nextU64()
    }

    // Returns the next 64-bit unsigned value.
    #[Swag.Inline]
    mtd nextU64()->u64
    {
        if not .seedDone do
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

    // Returns the next 32-bit signed value.
    #[Swag.Inline]
    mtd nextS32()->s32 => cast #bit (s32) .nextU32()

    // Returns the next 64-bit signed value.
    #[Swag.Inline]
    mtd nextS64()->s64 => cast #bit (s64) .nextU64()

    // Returns a value in the half-open interval `[0, 1)`, with 24 bits of precision.
    #[Swag.Inline]
    mtd nextF32()->f32 => cast(f32) (.nextU32() >> 8) * (1'f32 / 16777216'f32)

    // Returns a value in the half-open interval `[0, 1)`, with 53 bits of precision.
    #[Swag.Inline]
    mtd nextF64()->f64 => cast(f64) (.nextU64() >> 11) * (1'f64 / 9007199254740992'f64)

    // Returns a uniformly distributed value in the half-open interval `[min, max)`.
    //
    // `max` must be greater than `min`.
    mtd nextU32(min, max: u32)->u32
    {
        Swag.assert(max > min, "[[max]] must be greater than [[min]]")
        let range = max - min
        let limit = Swag.U32.Max - Swag.U32.Max % range
        var value = .nextU32()
        while value >= limit do
            value = .nextU32()
        value %= range
        return min + value
    }

    // Returns a uniformly distributed value in the half-open interval `[min, max)`.
    //
    // `max` must be greater than `min`.
    mtd nextU64(min, max: u64)->u64
    {
        Swag.assert(max > min, "[[max]] must be greater than [[min]]")
        let range = max - min
        let limit = Swag.U64.Max - Swag.U64.Max % range
        var value = .nextU64()
        while value >= limit do
            value = .nextU64()
        value %= range
        return min + value
    }

    // Returns a uniformly distributed value in the half-open interval `[min, max)`.
    //
    // `max` must be greater than `min`.
    #[Swag.Safety(.Overflow, false)]
    mtd nextS32(min, max: s32)->s32
    {
        Swag.assert(max > min, "[[max]] must be greater than [[min]]")
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

    // Returns a uniformly distributed value in the half-open interval `[min, max)`.
    //
    // `max` must be greater than `min`.
    #[Swag.Safety(.Overflow, false)]
    mtd nextS64(min, max: s64)->s64
    {
        Swag.assert(max > min, "[[max]] must be greater than [[min]]")
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

    // Returns a value in the half-open interval `[min, max)`.
    //
    // `max` must be greater than `min`.
    mtd nextF32(min, max: f32)->f32
    {
        Swag.assert(max > min, "[[max]] must be greater than [[min]]")
        let range = max - min
        let value = .nextF32()
        return min + (value * range)
    }

    // Returns a value in the half-open interval `[min, max)`.
    //
    // `max` must be greater than `min`.
    mtd nextF64(min, max: f64)->f64
    {
        Swag.assert(max > min, "[[max]] must be greater than [[min]]")
        let range = max - min
        let value = .nextF64()
        return min + (value * range)
    }

    // Returns `true` or `false` with equal probability.
    mtd nextBool()->bool => .nextU32(0, 2) != 0

    // Randomizes the order of the elements of `slice` in place with a Fisher-Yates shuffle.
    mtd(V) shuffle(slice: [..] V)
    {
        let count = slice.count
        if count < 2 do
            return

        let data = slice.buffer
        for var index = count - 1; index > 0; index -= 1
        {
            let other = .nextU64(0, index + 1)
            Core.swap(data + index, data + other)
        }
    }
}
