#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Math

const CoreSimdS64Min = -9_223_372_036_854_775_807's64 - 1

// The aliases name the '#simd' types themselves.
#test
{
    var nativeBytes: #simd [16] u8
    var namedBytes:  Simd.U8x16
    Swag.assert(#typeof(namedBytes) == #typeof(nativeBytes))

    var nativeWords: #simd [8] s16
    var namedWords:  Simd.S16x8
    Swag.assert(#typeof(namedWords) == #typeof(nativeWords))

    var quads:  Simd.U32x4
    var floats: Simd.F32x4
    Swag.assert(#sizeof(quads) == 16 and #alignof(floats) == 16)
}

// Loads and stores move one unaligned vector; the narrow stores write only the low bytes.
#test
{
    var source: [17] u8
    for i in 17 do
        source[i] = cast(u8) (i + 1)

    // An offset of one makes the load deliberately unaligned.
    let v = Simd.load(source.buffer + 1)
    Swag.assert(v[0] == 2 and v[15] == 17)

    var full: [16] u8
    Simd.store(full.buffer, v)
    Swag.assert(full[0] == 2 and full[15] == 17)

    var narrow: [16] u8
    Simd.storeLow8(narrow.buffer, v)
    Swag.assert(narrow[7] == 9 and narrow[8] == 0)
    Simd.storeLow4(narrow.buffer + 8, v)
    Swag.assert(narrow[8] == 2 and narrow[11] == 5 and narrow[12] == 0)

    var quads: [4] s32 = [1, 2, 3, 4]
    let w              = Simd.load(quads.buffer)
    Swag.assert(w[3] == 4)
}

// Saturating arithmetic clamps instead of wrapping, and the rounding average rounds up.
#test
{
    let big   = Simd.splat(200'u8)
    let small = Simd.splat(100'u8)
    Swag.assert(Simd.addSaturating(big, small)[0] == 255)
    Swag.assert(Simd.subSaturating(small, big)[0] == 0)
    Swag.assert(Simd.average(big, small)[15] == 150)
    Swag.assert(Simd.average(Simd.splat(1'u8), Simd.splat(2'u8))[0] == 2)

    let words = cast(Simd.S16x8) [1's16, 2, 3, 4, 5, 6, 7, 8]
    let pairs = Simd.mulAddPairs(words, words)
    Swag.assert(pairs[0] == 1 * 1 + 2 * 2 and pairs[3] == 7 * 7 + 8 * 8)

    Swag.assert(Simd.sum(cast(Simd.S32x4) [1's32, 2, 3, 4]) == 10)
    Swag.assert(Simd.sum(cast(Simd.S32x4) [2_147_483_647's32, 1, 0, 0]) == -2_147_483_648)

    let truncated = Simd.truncateToS32(cast(Simd.F32x4) [1.9'f32, -1.9, 32767.9, -32768.9])
    Swag.assert(truncated[0] == 1 and truncated[1] == -1 and truncated[2] == 32767 and truncated[3] == -32768)
}

// Gather follows four independent indices, including repeats and non-monotonic order.
#test
{
    var table: [17] s32
    for i in 17 do
        table[i] = cast(s32) i * cast(s32) i - 31

    let gathered = Simd.gather(table.buffer, cast(Simd.U32x4) [16'u32, 3, 3, 9])
    Swag.assert(gathered[0] == 225 and gathered[1] == -22 and gathered[2] == -22 and gathered[3] == 50)
}

// Interleaving alternates lanes from the corresponding low or high input halves.
#test
{
    let x    = cast(Simd.U8x16) [0'u8, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15]
    let y    = cast(Simd.U8x16) [100'u8, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115]
    let low  = Simd.interleaveLow(x, y)
    let high = Simd.interleaveHigh(x, y)
    Swag.assert(low[0] == 0 and low[1] == 100 and low[14] == 7 and low[15] == 107)
    Swag.assert(high[0] == 8 and high[1] == 108 and high[14] == 15 and high[15] == 115)

    let wordLow = Simd.interleaveLow(cast(Simd.U16x8) [0'u16, 1, 2, 3, 4, 5, 6, 7], cast(Simd.U16x8) [10'u16, 11, 12, 13, 14, 15, 16, 17])
    Swag.assert(wordLow[0] == 0 and wordLow[1] == 10 and wordLow[6] == 3 and wordLow[7] == 13)

    let quadLow  = Simd.interleaveLow(cast(Simd.U32x4) [0'u32, 1, 2, 3], cast(Simd.U32x4) [10'u32, 11, 12, 13])
    let quadHigh = Simd.interleaveHigh(cast(Simd.U32x4) [0'u32, 1, 2, 3], cast(Simd.U32x4) [10'u32, 11, 12, 13])
    Swag.assert(quadLow[0] == 0 and quadLow[1] == 10 and quadLow[2] == 1 and quadLow[3] == 11)
    Swag.assert(quadHigh[0] == 2 and quadHigh[1] == 12 and quadHigh[2] == 3 and quadHigh[3] == 13)

    let octLow  = Simd.interleaveLow(cast(Simd.U64x2) [0'u64, 1], cast(Simd.U64x2) [10'u64, 11])
    let octHigh = Simd.interleaveHigh(cast(Simd.U64x2) [0'u64, 1], cast(Simd.U64x2) [10'u64, 11])
    Swag.assert(octLow[0] == 0 and octLow[1] == 10)
    Swag.assert(octHigh[0] == 1 and octHigh[1] == 11)
}

// Packs narrow with saturation, and the widening halves extend with the lane's signedness.
#test
{
    let sums = cast(Simd.S16x8) [-20's16, 0, 128, 300, 255, 256, 64, 1]
    let px   = Simd.packUnsigned(sums, sums)
    Swag.assert(px[0] == 0 and px[2] == 128 and px[3] == 255 and px[8] == 0)
    let sx = Simd.packSigned(sums, sums)
    Swag.assert(sx[0] == -20 and sx[3] == 127)

    let bytes = Simd.splat(-3's8)
    Swag.assert(Simd.widenLow(bytes)[0] == -3 and Simd.widenHigh(bytes)[7] == -3)
    let wide = Simd.widenHigh(Simd.splat(200'u8))
    Swag.assert(wide[0] == 200)
}

// The dynamic byte shuffle reverses through a table, and a high bit clears the lane.
#test
{
    var lanes: [16] u8
    for i in 16 do
        lanes[i] = cast(u8) (i * 3)
    let value    = Simd.load(lanes.buffer)
    let reversed = Simd.shuffle(value, cast(Simd.U8x16) [15'u8, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 0])
    Swag.assert(reversed[0] == 45 and reversed[15] == 0)
    let cleared = Simd.shuffle(value, cast(Simd.U8x16) [128'u8, 1, 128, 3, 128, 5, 128, 7, 128, 9, 128, 11, 128, 13, 128, 15])
    Swag.assert(cleared[0] == 0 and cleared[1] == 3)
}

// Comparisons produce masks, and select, bitmask, any and all consume them.
#test
{
    let a = cast(Simd.S32x4) [1's32, 50, 3, 70]
    let b = cast(Simd.S32x4) [10's32, 20, 30, 40]

    let mask    = a > b
    let clamped = Simd.select(mask, b, a)
    Swag.assert(clamped[0] == 1 and clamped[1] == 20 and clamped[2] == 3 and clamped[3] == 40)
    Swag.assert(Simd.bitmask(mask) == 0b1010)
    Swag.assert(Simd.anyTrue(mask) and !Simd.allTrue(mask))
    Swag.assert(!Simd.anyTrue(a > Simd.splat(100's32)))
    Swag.assert(Simd.allTrue(a < Simd.splat(100's32)))
}

// The element-wise Math functions accept the vector types, including the generic min and max.
#test
{
    let a = cast(Simd.S16x8) [-5's16, 10, -300, 4, 0, 1, -1, 32767]
    let r = Math.abs(a)
    Swag.assert(r[0] == 5 and r[2] == 300 and r[7] == 32767)
    let wide    = cast(Simd.S64x2) [CoreSimdS64Min, -9_000_000_000]
    let wideAbs = Math.abs(wide)
    Swag.assert(wideAbs[0] == CoreSimdS64Min and wideAbs[1] == 9_000_000_000)
    Swag.assert(Math.min(wide, Simd.splat(-7's64))[0] == CoreSimdS64Min)
    Swag.assert(Math.max(wide, Simd.splat(-7's64))[1] == -7)

    let x = cast(Simd.F32x4) [1'f32, 4, 9, 16]
    let s = Math.sqrt(x)
    Swag.assert(s[0] == 1 and s[3] == 4)
    Swag.assert(Math.floor(Simd.splat(1.5'f32))[0] == 1)
    Swag.assert(Math.ceil(Simd.splat(1.5'f32))[0] == 2)
    Swag.assert(Math.trunc(Simd.splat(-1.5'f64))[0] == -1)
    Swag.assert(Math.mulAdd(x, x, x)[1] == 20)

    let lo = Math.min(a, Simd.splat(0's16))
    let hi = Math.max(a, Simd.splat(0's16))
    Swag.assert(lo[0] == -5 and lo[1] == 0)
    Swag.assert(hi[0] == 0 and hi[1] == 10)
}

// The packed bit vocabulary repeats the scalar one, lane by lane.
#test
{
    let bytes = cast(Simd.U8x16) [0'u8, 1, 2, 3, 0x0F, 0x10, 0x55, 0x7F, 0x80, 0xAA, 0xC3, 0xE0, 0xF0, 0xFE, 0xFF, 0x18]
    let quads = cast(Simd.U32x4) [0'u32, 1, 0x1234_5678, 0xFFFF_FFFF]

    let rotated  = Math.rol(bytes, 3)
    let restored = Math.ror(rotated, 3)
    for i in 16
    {
        Swag.assert(rotated[i] == Math.rol(bytes[i], 3))
        Swag.assert(restored[i] == bytes[i])
    }

    let ones  = Math.countOnes(quads)
    let lead  = Math.leadingZeros(quads)
    let trail = Math.trailingZeros(quads)
    for i in 4
    {
        Swag.assert(ones[i] == Math.countOnes(quads[i]))
        Swag.assert(lead[i] == Math.leadingZeros(quads[i]))
        Swag.assert(trail[i] == Math.trailingZeros(quads[i]))
    }

    let swapped = Math.byteswap(quads)
    for i in 4 do
        Swag.assert(swapped[i] == Math.byteswap(quads[i]))

    let reversedBytes = Math.reverse(bytes)
    for i in 16 do
        Swag.assert(reversedBytes[i] == Math.reverse(bytes[i]))

    let reversedQuads = Math.reverse(quads)
    for i in 4 do
        Swag.assert(reversedQuads[i] == Math.reverse(quads[i]))

    let words         = cast(Simd.U16x8) [0'u16, 1, 0x00FF, 0x0100, 0x1234, 0x8000, 0xAAAA, 0xFFFF]
    let reversedWords = Math.reverse(words)
    for i in 8 do
        Swag.assert(reversedWords[i] == Math.reverse(words[i]))

    let pairs         = cast(Simd.U64x2) [0'u64, 0x0102_0304_0506_0708]
    let reversedPairs = Math.reverse(pairs)
    for i in 2 do
        Swag.assert(reversedPairs[i] == Math.reverse(pairs[i]))
}

// The elementary float lane operations: magnitude, sign transfer, sign, clamp
// and interpolation.
#test
{
    let values = cast(Simd.F32x4) [-1.5'f32, 2.5, -0.0, 8.25]

    let magnitude = Math.abs(values)
    Swag.assert(magnitude[0] == 1.5 and magnitude[1] == 2.5 and magnitude[3] == 8.25)
    Swag.assert(1.0 / magnitude[2] > 0)

    let negative = Math.copysign(values, Simd.splat(-1'f32))
    Swag.assert(negative[0] == -1.5 and negative[1] == -2.5 and negative[3] == -8.25)
    Swag.assert(1.0 / negative[2] < 0)
    for i in 4 do
        Swag.assert(negative[i] == Math.copysign(values[i], -1'f32))

    let signs = Math.sign(values)
    Swag.assert(signs[0] == -1 and signs[1] == 1 and signs[2] == 0 and signs[3] == 1)

    let bounded = Math.saturate(values)
    Swag.assert(bounded[0] == 0 and bounded[1] == 1 and bounded[3] == 1)

    let clamped = Math.clamp(values, Simd.splat(-1'f32), Simd.splat(2'f32))
    Swag.assert(clamped[0] == -1 and clamped[1] == 2 and clamped[3] == 2)

    let mixed = Math.lerp(Simd.splat(0'f32), Simd.splat(10'f32), Simd.splat(0.25'f32))
    Swag.assert(mixed[0] == 2.5 and mixed[3] == 2.5)

    let wide = cast(Simd.F64x2) [-3.25'f64, -0.0]
    Swag.assert(Math.abs(wide)[0] == 3.25 and 1.0 / Math.abs(wide)[1] > 0)
    Swag.assert(Math.copysign(wide, Simd.splat(1'f64))[0] == 3.25)
    Swag.assert(Math.sign(wide)[0] == -1 and Math.sign(wide)[1] == 0)
    Swag.assert(Math.saturate(wide)[0] == 0)
    Swag.assert(Math.lerp(Simd.splat(1'f64), Simd.splat(3'f64), Simd.splat(0.5'f64))[1] == 2)
}

// The horizontal reductions and their widening forms.
#test
{
    let quads = cast(Simd.S32x4) [1's32, -2, 3, 4]
    Swag.assert(Simd.sum(quads) == 6)
    Swag.assert(Simd.minimum(quads) == -2)
    Swag.assert(Simd.maximum(quads) == 4)

    let bits = cast(Simd.U32x4) [0b1110'u32, 0b1010, 0b1111, 0b0110]
    Swag.assert(Simd.bitwiseAnd(bits) == 0b0010)
    Swag.assert(Simd.bitwiseOr(bits) == 0b1111)
    Swag.assert(Simd.bitwiseXor(bits) == 0b1101)

    let floats = cast(Simd.F32x4) [1.5'f32, -2.5, 8, 0.25]
    Swag.assert(Simd.sum(floats) == 7.25)
    Swag.assert(Simd.minimum(floats) == -2.5)
    Swag.assert(Simd.maximum(floats) == 8)

    let mask = quads > Simd.splat(0's32)
    Swag.assert(Simd.countTrue(mask) == 3)

    // The widening sums cannot overflow their accumulator, whatever the lanes hold.
    Swag.assert(Simd.sumWide(Simd.splat(255'u8)) == 16 * 255)
    Swag.assert(Simd.sumWide(Simd.splat(65535'u16)) == 8 * 65535)
    Swag.assert(Simd.sumWide(Simd.splat(-128's8)) == 16 * -128)
    Swag.assert(Simd.sumWide(Simd.splat(-32768's16)) == 8 * -32768)
    Swag.assert(Simd.sumWide(Simd.splat(0xFFFF_FFFF'u32)) == 4'u64 * 0xFFFF_FFFF)
    Swag.assert(Simd.sumWide(Simd.splat(2_147_483_647's32)) == 4's64 * 2_147_483_647)

    // The narrow sums wrap in their own lane width.
    Swag.assert(Simd.sum(Simd.splat(255'u8)) == cast(u8) ((16 * 255) % 256))
}

// The sum of absolute differences and the byte dot product.
#test
{
    let left  = cast(Simd.U8x16) [10'u8, 20, 30, 40, 50, 60, 70, 80, 0, 0, 0, 0, 0, 0, 0, 0]
    let right = cast(Simd.U8x16) [1'u8, 2, 3, 4, 5, 6, 7, 8, 255, 0, 0, 0, 0, 0, 0, 0]

    let halves = Simd.absoluteDifferences(left, right)
    Swag.assert(halves[0] == 324 and halves[1] == 255)
    Swag.assert(Simd.sumAbsoluteDifferences(left, right) == 324 + 255)

    let unsignedBytes = cast(Simd.U8x16) [1'u8, 2, 3, 4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    let signedBytes   = cast(Simd.S8x16) [10's8, -20, 30, -40, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    let products      = Simd.mulAddPairs(unsignedBytes, signedBytes)
    Swag.assert(products[0] == -30 and products[1] == -70)
}

// Lane permutation, byte alignment, deinterleaving and the transposes.
#test
{
    let quads = cast(Simd.U32x4) [10'u32, 20, 30, 40]
    let other = cast(Simd.U32x4) [50'u32, 60, 70, 80]

    let reversed = Simd.permute(quads, cast(Simd.U32x4) [3'u32, 2, 1, 0])
    Swag.assert(reversed[0] == 40 and reversed[3] == 10)

    let mixed = Simd.permute2(quads, other, cast(Simd.U32x4) [0'u32, 4, 1, 5])
    Swag.assert(mixed[0] == 10 and mixed[1] == 50 and mixed[2] == 20 and mixed[3] == 60)

    let low  = cast(Simd.U8x16) [0'u8, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15]
    let high = cast(Simd.U8x16) [16'u8, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31]
    let slid = Simd.align(low, high, 4)
    for i in 16 do
        Swag.assert(slid[i] == cast(u8) (i + 4))

    let evens = Simd.deinterleaveEven(low, high)
    let odds  = Simd.deinterleaveOdd(low, high)
    for i in 16
    {
        Swag.assert(evens[i] == cast(u8) (i * 2))
        Swag.assert(odds[i] == cast(u8) (i * 2 + 1))
    }
}

// A transpose reads no lane one at a time: the interleave tree does all of it.
#test
{
    var rows: [4] Simd.U32x4
    for r in 4
    {
        var lanes: [4] u32
        for c in 4 do
            lanes[c] = cast(u32) (r * 4 + c)
        rows[r] = cast(Simd.U32x4) lanes
    }

    Simd.transpose4x4(&rows)
    for r in 4
    {
        for c in 4 do
            Swag.assert(rows[r][c] == cast(u32) (c * 4 + r))
    }

    var wide: [8] Simd.U16x8
    for r in 8
    {
        var lanes: [8] u16
        for c in 8 do
            lanes[c] = cast(u16) (r * 8 + c)
        wide[r] = cast(Simd.U16x8) lanes
    }

    Simd.transpose8x8(&wide)
    for r in 8
    {
        for c in 8 do
            Swag.assert(wide[r][c] == cast(u16) (c * 8 + r))
    }
}

// The high half of a lane product, and the widening products it composes into.
#test
{
    let x = cast(Simd.S16x8) [-32768's16, 32767, 1000, -1000, 3, -3, 0, 12345]
    let y = cast(Simd.S16x8) [32767's16, 32767, -2000, 2000, 5, 5, 12345, -1]

    let low  = x * y
    let high = Simd.mulHigh(x, y)
    for i in 8
    {
        // The full product read as bits, since half of it does not fit a lane.
        let exact = cast #bit (u32) (cast(s32) x[i] * cast(s32) y[i])
        Swag.assert(cast #bit (u16) low[i] == cast(u16) (exact & 0xFFFF))
        Swag.assert(cast #bit (u16) high[i] == cast(u16) (exact >> 16))
    }

    let wideLow  = Simd.mulWidenLow(x, y)
    let wideHigh = Simd.mulWidenHigh(x, y)
    for i in 4
    {
        Swag.assert(wideLow[i] == cast(s32) x[i] * cast(s32) y[i])
        Swag.assert(wideHigh[i] == cast(s32) x[i + 4] * cast(s32) y[i + 4])
    }

    // The unsigned form reads the same bits differently.
    let ux = cast #bit (Simd.U16x8) x
    let uy = cast #bit (Simd.U16x8) y
    let uh = Simd.mulHigh(ux, uy)
    for i in 8 do
        Swag.assert(uh[i] == cast(u16) ((cast(u32) ux[i] * cast(u32) uy[i]) >> 16))
}
