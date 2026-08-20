#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Math

// The aliases name the '#simd' types themselves.
#test
{
    var nativeBytes: #simd [16] u8
    var namedBytes:  Simd.U8x16
    @assert(#typeof(namedBytes) == #typeof(nativeBytes))

    var nativeWords: #simd [8] s16
    var namedWords:  Simd.S16x8
    @assert(#typeof(namedWords) == #typeof(nativeWords))

    var quads:  Simd.U32x4
    var floats: Simd.F32x4
    @assert(#sizeof(quads) == 16 and #alignof(floats) == 16)
}

// Loads and stores move one unaligned vector; the narrow stores write only the low bytes.
#test
{
    var source: [17] u8
    for i in 17 do
        source[i] = cast(u8) (i + 1)

    // An offset of one makes the load deliberately unaligned.
    let v = Simd.load(@dataof(source) + 1)
    @assert(v[0] == 2 and v[15] == 17)

    var full: [16] u8
    Simd.store(@dataof(full), v)
    @assert(full[0] == 2 and full[15] == 17)

    var narrow: [16] u8
    Simd.storeLow8(@dataof(narrow), v)
    @assert(narrow[7] == 9 and narrow[8] == 0)
    Simd.storeLow4(@dataof(narrow) + 8, v)
    @assert(narrow[8] == 2 and narrow[11] == 5 and narrow[12] == 0)

    var quads: [4] s32 = [1, 2, 3, 4]
    let w              = Simd.load(@dataof(quads))
    @assert(w[3] == 4)
}

// Saturating arithmetic clamps instead of wrapping, and the rounding average rounds up.
#test
{
    let big   = Simd.splat(200'u8)
    let small = Simd.splat(100'u8)
    @assert(Simd.addSaturating(big, small)[0] == 255)
    @assert(Simd.subSaturating(small, big)[0] == 0)
    @assert(Simd.average(big, small)[15] == 150)
    @assert(Simd.average(Simd.splat(1'u8), Simd.splat(2'u8))[0] == 2)

    let words = cast(Simd.S16x8) [1's16, 2, 3, 4, 5, 6, 7, 8]
    let pairs = Simd.mulAddPairs(words, words)
    @assert(pairs[0] == 1 * 1 + 2 * 2 and pairs[3] == 7 * 7 + 8 * 8)

    @assert(Simd.sum(cast(Simd.S32x4) [1's32, 2, 3, 4]) == 10)
    @assert(Simd.sum(cast(Simd.S32x4) [2_147_483_647's32, 1, 0, 0]) == -2_147_483_648)
}

// Packs narrow with saturation, and the widening halves extend with the lane's signedness.
#test
{
    let sums = cast(Simd.S16x8) [-20's16, 0, 128, 300, 255, 256, 64, 1]
    let px   = Simd.packUnsigned(sums, sums)
    @assert(px[0] == 0 and px[2] == 128 and px[3] == 255 and px[8] == 0)
    let sx = Simd.packSigned(sums, sums)
    @assert(sx[0] == -20 and sx[3] == 127)

    let bytes = Simd.splat(-3's8)
    @assert(Simd.widenLow(bytes)[0] == -3 and Simd.widenHigh(bytes)[7] == -3)
    let wide = Simd.widenHigh(Simd.splat(200'u8))
    @assert(wide[0] == 200)
}

// The dynamic byte shuffle reverses through a table, and a high bit clears the lane.
#test
{
    var lanes: [16] u8
    for i in 16 do
        lanes[i] = cast(u8) (i * 3)
    let value    = Simd.load(@dataof(lanes))
    let reversed = Simd.shuffle(value, cast(Simd.U8x16) [15'u8, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 0])
    @assert(reversed[0] == 45 and reversed[15] == 0)
    let cleared = Simd.shuffle(value, cast(Simd.U8x16) [128'u8, 1, 128, 3, 128, 5, 128, 7, 128, 9, 128, 11, 128, 13, 128, 15])
    @assert(cleared[0] == 0 and cleared[1] == 3)
}

// Comparisons produce masks, and select, bitmask, any and all consume them.
#test
{
    let a = cast(Simd.S32x4) [1's32, 50, 3, 70]
    let b = cast(Simd.S32x4) [10's32, 20, 30, 40]

    let mask    = a > b
    let clamped = Simd.select(mask, b, a)
    @assert(clamped[0] == 1 and clamped[1] == 20 and clamped[2] == 3 and clamped[3] == 40)
    @assert(Simd.bitmask(mask) == 0b1010)
    @assert(Simd.anyTrue(mask) and !Simd.allTrue(mask))
    @assert(!Simd.anyTrue(a > Simd.splat(100's32)))
    @assert(Simd.allTrue(a < Simd.splat(100's32)))
}

// The element-wise Math functions accept the vector types, including the generic min and max.
#test
{
    let a = cast(Simd.S16x8) [-5's16, 10, -300, 4, 0, 1, -1, 32767]
    let r = Math.abs(a)
    @assert(r[0] == 5 and r[2] == 300 and r[7] == 32767)

    let x = cast(Simd.F32x4) [1'f32, 4, 9, 16]
    let s = Math.sqrt(x)
    @assert(s[0] == 1 and s[3] == 4)
    @assert(Math.floor(Simd.splat(1.5'f32))[0] == 1)
    @assert(Math.ceil(Simd.splat(1.5'f32))[0] == 2)
    @assert(Math.trunc(Simd.splat(-1.5'f64))[0] == -1)
    @assert(Math.mulAdd(x, x, x)[1] == 20)

    let lo = Math.min(a, Simd.splat(0's16))
    let hi = Math.max(a, Simd.splat(0's16))
    @assert(lo[0] == -5 and lo[1] == 0)
    @assert(hi[0] == 0 and hi[1] == 10)
}
