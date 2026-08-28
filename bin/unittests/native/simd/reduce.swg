#global private
using Swag

// The horizontal reductions, checked against the scalar fold of the same lanes,
// plus the sum of absolute differences and the byte dot product.

const ReduceS64Min = -9_223_372_036_854_775_807's64 - 1

#[Swag.NoInline]
func liveReduceAdd(value: #simd [16] u8)->u8 => @vecreduceadd(value)

#test
{
    // Integer sums wrap, exactly like the element-wise arithmetic.
    var bytes: [16] u8
    for i in 16 do
        bytes[i] = cast(u8) ((i * 17 + 3) % 256)

    var total = 0'u32
    for b in bytes do
        total += b
    let expected = cast(u8) (total % 256)
    @assert(@vecreduceadd(cast(#simd [16] u8) bytes) == expected)
    @assert(liveReduceAdd(cast(#simd [16] u8) bytes) == expected)

    var minimum = bytes[0]
    var maximum = bytes[0]
    for b in bytes
    {
        minimum = @min(minimum, b)
        maximum = @max(maximum, b)
    }
    @assert(@vecreducemin(cast(#simd [16] u8) bytes) == minimum)
    @assert(@vecreducemax(cast(#simd [16] u8) bytes) == maximum)

    var conjunction = 0xFF'u8
    var disjunction = 0'u8
    var difference  = 0'u8
    for b in bytes
    {
        conjunction &= b
        disjunction |= b
        difference  ^= b
    }
    @assert(@vecreduceand(cast(#simd [16] u8) bytes) == conjunction)
    @assert(@vecreduceor(cast(#simd [16] u8) bytes) == disjunction)
    @assert(@vecreducexor(cast(#simd [16] u8) bytes) == difference)
}

#test
{
    // Signed lanes keep their sign through the narrow extraction.
    let signedBytes = cast(#simd [16] s8) [-1, 2, -3, 4, -5, 6, -7, 8, -128, 127, 0, 0, 0, 0, 0, 0]
    @assert(@vecreduceadd(signedBytes) == 4 - 128 + 127)
    @assert(@vecreducemin(signedBytes) == -128)
    @assert(@vecreducemax(signedBytes) == 127)

    let signedWords = cast(#simd [8] s16) [-1000, 2000, -3000, 4000, 5, 6, 7, -32768]
    @assert(@vecreducemin(signedWords) == -32768)
    @assert(@vecreducemax(signedWords) == 4000)

    let words = cast(#simd [8] u16) [1, 2, 3, 4, 5, 6, 7, 0xFFFF]
    @assert(@vecreduceadd(words) == 27)
    @assert(@vecreducemin(words) == 1)
    @assert(@vecreducemax(words) == 0xFFFF)

    let quads = cast(#simd [4] s32) [1, -2, 3, 4]
    @assert(@vecreduceadd(quads) == 6)
    @assert(@vecreducemin(quads) == -2)
    @assert(@vecreducemax(quads) == 4)

    let wrapping = cast(#simd [4] s32) [2_147_483_647, 1, 0, 0]
    @assert(@vecreduceadd(wrapping) == -2_147_483_648)

    let unsignedQuads = cast(#simd [4] u32) [1, 0xFFFF_FFFF, 3, 4]
    @assert(@vecreducemax(unsignedQuads) == 0xFFFF_FFFF)
    @assert(@vecreducemin(unsignedQuads) == 1)

    // The 64-bit minimum and maximum have no instruction: they ride a compare
    // and a blend, signed and unsigned alike.
    let pairs = cast(#simd [2] s64) [ReduceS64Min, 7_000_000_000]
    @assert(@vecreducemin(pairs) == ReduceS64Min)
    @assert(@vecreducemax(pairs) == 7_000_000_000)
    @assert(@vecreduceadd(pairs) == ReduceS64Min + 7_000_000_000)

    let unsignedPairs = cast(#simd [2] u64) [0xFFFF_FFFF_FFFF_FFFF, 1]
    @assert(@vecreducemin(unsignedPairs) == 1)
    @assert(@vecreducemax(unsignedPairs) == 0xFFFF_FFFF_FFFF_FFFF)
    @assert(@vecreduceand(unsignedPairs) == 1)
    @assert(@vecreduceor(unsignedPairs) == 0xFFFF_FFFF_FFFF_FFFF)
}

#test
{
    // Float reductions combine adjacent lanes first, which is the order the
    // sum of these four values observes.
    let floats = cast(#simd [4] f32) [1.5, -2.5, 8.0, 0.25]
    @assert(@vecreduceadd(floats) == 7.25)
    @assert(@vecreducemin(floats) == -2.5)
    @assert(@vecreducemax(floats) == 8.0)

    let doubles = cast(#simd [2] f64) [1.5, -2.5]
    @assert(@vecreduceadd(doubles) == -1.0)
    @assert(@vecreducemin(doubles) == -2.5)
    @assert(@vecreducemax(doubles) == 1.5)

    // A negative zero is not the minimum of a pair holding a positive one:
    // the compare treats them as equal and the element-wise minimum answers
    // its second operand.
    let zeroes = cast(#simd [4] f32) [0.0, -0.0, 0.0, -0.0]
    @assert(@vecreduceadd(zeroes) == 0.0)
}

#test
{
    // The absolute byte differences of each half reduce into one 64-bit lane
    // each, and the signed form biases both sides into the same instruction.
    var left:  [16] u8
    var right: [16] u8
    for i in 16
    {
        left[i]  = cast(u8) ((i * 13 + 7) % 256)
        right[i] = cast(u8) ((i * 5 + 200) % 256)
    }

    var lowSum  = 0'u64
    var highSum = 0'u64
    for i in 16
    {
        let difference = left[i] > right[i] ? cast(u64) (left[i] - right[i]) : cast(u64) (right[i] - left[i])
        if i < 8 do
            lowSum += difference
        else do
            highSum += difference
    }

    let sums = cast([2] u64) @vecsad(cast(#simd [16] u8) left, cast(#simd [16] u8) right)
    @assert(sums[0] == lowSum and sums[1] == highSum)

    let signedLeft  = cast(#simd [16] s8) [-100, 100, -1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    let signedRight = cast(#simd [16] s8) [100, -100, 1, -1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    let signedSums  = cast([2] u64) @vecsad(signedLeft, signedRight)
    @assert(signedSums[0] == 200 + 200 + 2 + 2 and signedSums[1] == 0)

    // The unsigned/signed byte dot product saturates its 16-bit sums.
    let unsignedBytes = cast(#simd [16] u8) [1, 2, 3, 4, 255, 255, 255, 255, 0, 0, 0, 0, 0, 0, 0, 0]
    let signedBytes   = cast(#simd [16] s8) [10, -20, 30, -40, 127, 127, -128, -128, 0, 0, 0, 0, 0, 0, 0, 0]
    let products      = cast([8] s16) @vecmaddubs(unsignedBytes, signedBytes)
    @assert(products[0] == -30 and products[1] == -70)
    @assert(products[2] == 32767 and products[3] == -32768)
}
