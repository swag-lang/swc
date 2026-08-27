#global if #command == Swag.CompilerCommand.Test
#global internal

using Core

// The packed inverse 4x4 transform against the scalar form of section 8.5.12.2: coefficient
// blocks over the range a conforming stream produces, predictions that push the clamp both
// ways, and a stride wider than the block so the neighbouring samples must stay untouched.
func assertIdct4x4Case(seed: u64)
{
    const Stride = 16'u64
    var block:    [16] s16
    var expected: [4 * Stride + 16] u8
    var actual:   [4 * Stride + 16] u8
    for index in 16'u64 do
        block[index] = cast(s16) (cast(s64) ((index * (seed * 37 + 11) + seed * 101 + 3) & 2047) - 1024)
    if seed % 5 == 0 do
        block[0] = cast(s16) (cast(s64) (seed * 977 & 8191) - 4096)
    for index in @countof(expected)
    {
        let value = cast(u8) ((index * (seed * 13 + 7) + seed * 29) & 255)
        expected[index] = value
        actual[index]   = value
    }

    H264.addIdct4x4Scalar(@dataof(expected) + 4, Stride, @dataof(block))
    H264.addIdct4x4(@dataof(actual) + 4, Stride, @dataof(block))
    @assert(Memory.compare(@dataof(expected), @dataof(actual), @countof(actual)) == 0)

    // The flat DC add on the same samples, over the whole range of the rounded value.
    var dc = cast(s32) (cast(s64) ((seed * 8191 + 17) & 0x3FFF) - 0x2000)
    if seed % 7 == 0 do
        dc *= 4096
    H264.addDc4x4Scalar(@dataof(expected) + 4, Stride, dc)
    H264.addDc4x4(@dataof(actual) + 4, Stride, dc)
    @assert(Memory.compare(@dataof(expected), @dataof(actual), @countof(actual)) == 0)
}

// The packed inverse 8x8 transform against its scalar form, same conventions.
func assertIdct8x8Case(seed: u64)
{
    const Stride = 16'u64
    var block:    [64] s16
    var expected: [8 * Stride + 16] u8
    var actual:   [8 * Stride + 16] u8

    // Dense random blocks amplify through two eight-point passes; a conforming stream bounds
    // the intermediates to 16 bits, which these magnitudes respect with margin.
    for index in 64'u64 do
        block[index] = cast(s16) (cast(s64) ((index * (seed * 53 + 7) + seed * 131 + 5) & 255) - 128)
    if seed % 3 == 0 do
        block[0] = cast(s16) (cast(s64) (seed * 977 & 4095) - 2048)
    for index in @countof(expected)
    {
        let value = cast(u8) ((index * (seed * 19 + 3) + seed * 41) & 255)
        expected[index] = value
        actual[index]   = value
    }

    H264.addIdct8x8Scalar(@dataof(expected) + 4, Stride, @dataof(block))
    H264.addIdct8x8(@dataof(actual) + 4, Stride, @dataof(block))
    @assert(Memory.compare(@dataof(expected), @dataof(actual), @countof(actual)) == 0)
}

// The packed Hadamard transform must match the scalar 32-bit reference over the full input
// range, including outputs that saturate at both signed 16-bit boundaries.
func assertHadamard4x4Case(seed: u64)
{
    var expected: [16] s16
    var actual:   [16] s16
    for index in 16'u64
    {
        let value = cast #bit(s16) cast(u16) ((index * (seed * 104729 + 8191) + seed * 65521 + 32749) & 0xFFFF)
        expected[index] = value
        actual[index]   = value
    }

    H264.hadamard4x4Scalar(@dataof(expected))
    H264.hadamard4x4(@dataof(actual))
    @assert(Memory.compare(@dataof(expected), @dataof(actual), #sizeof(actual)) == 0)
}

#test
{
    for seed in 512'u64
    {
        assertIdct4x4Case(seed)
        assertIdct8x8Case(seed)
        assertHadamard4x4Case(seed)
    }

    var expected: [16] s16 = [Swag.S16.Min, Swag.S16.Max, Swag.S16.Min, Swag.S16.Max, Swag.S16.Max, Swag.S16.Min, Swag.S16.Max, Swag.S16.Min, Swag.S16.Min, Swag.S16.Min, Swag.S16.Max, Swag.S16.Max, Swag.S16.Max, Swag.S16.Max, Swag.S16.Min, Swag.S16.Min]
    var actual             = expected
    H264.hadamard4x4Scalar(@dataof(expected))
    H264.hadamard4x4(@dataof(actual))
    @assert(Memory.compare(@dataof(expected), @dataof(actual), #sizeof(actual)) == 0)
}
