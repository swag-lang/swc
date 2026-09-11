#global private
using Swag

// A vector literal whose lanes are scalars in registers is built in the
// register file instead of through a frame temporary: the first lane through
// movd, the others inserted, a lane repeated over its neighbor by
// interleaving, a repeating unit by broadcast. Every shape of repetition the
// deblocking filters use, and the plain distinct case, must come out lane for
// lane.

#[Swag.Optimize(true)]
func halves(dst: [*] u16, a, b: u16)
{
    (cast([*] #simd [8] u16) dst)[0] = cast(#simd [8] u16) [a, a, a, a, b, b, b, b]
}

#[Swag.Optimize(true)]
func pairs(dst: [*] u16, a, b, c, d: u16)
{
    (cast([*] #simd [8] u16) dst)[0] = cast(#simd [8] u16) [a, a, b, b, c, c, d, d]
}

#[Swag.Optimize(true)]
func alternate(dst: [*] s16, x, y: s16)
{
    (cast([*] #simd [8] s16) dst)[0] = cast(#simd [8] s16) [x, y, x, y, x, y, x, y]
}

#[Swag.Optimize(true)]
func withZeros(dst: [*] s16, x, y, r: s16)
{
    (cast([*] #simd [8] s16) dst)[0] = cast(#simd [8] s16) [x, y, r, 0, x, y, r, 0]
}

#[Swag.Optimize(true)]
func oneLane(dst: [*] s16, r: s16)
{
    (cast([*] #simd [8] s16) dst)[0] = cast(#simd [8] s16) [0, 0, r, 0, 0, 0, r, 0]
}

#[Swag.Optimize(true)]
func distinctWords(dst: [*] u16, a, b, c, d, e, f, g, h: u16)
{
    (cast([*] #simd [8] u16) dst)[0] = cast(#simd [8] u16) [a, b, c, d, e, f, g, h]
}

#[Swag.Optimize(true)]
func sameWord(dst: [*] u16, a: u16)
{
    (cast([*] #simd [8] u16) dst)[0] = cast(#simd [8] u16) [a, a, a, a, a, a, a, a]
}

#[Swag.Optimize(true)]
func dwords(dst: [*] u32, a, b, c, d: u32)
{
    (cast([*] #simd [4] u32) dst)[0] = cast(#simd [4] u32) [a, b, c, d]
}

#[Swag.Optimize(true)]
func bytes(dst: [*] u8, a, b: u8)
{
    (cast([*] #simd [16] u8) dst)[0] = cast(#simd [16] u8) [a, b, 0, 0, a, b, 0, 0, a, b, 0, 0, a, b, 0, 0]
}

#[Swag.Optimize(true)]
func readTwice(dst: [*] u16, a, b: u16)->u16
{
    // The lanes are also read one by one: the frame copy stays, and both
    // readings must agree.
    let lanes = [a, a, a, a, b, b, b, b]
    (cast([*] #simd [8] u16) dst)[0] = cast(#simd [8] u16) lanes
    return lanes[1] + lanes[6]
}

#[Swag.Optimize(true)]
func computedLanes(dst: [*] u16, a, b: u16)
{
    // The lanes are computed values, still in registers when the vector is
    // read, and the literal feeds an operation instead of a store.
    let sum = cast(u16) (a + b)
    (cast([*] #simd [8] u16) dst)[0] = (cast(#simd [8] u16) [a, a, sum, sum, b, b, sum, sum]) + cast(#simd [8] u16) [1, 1, 1, 1, 1, 1, 1, 1]
}

struct Strength
{
    bs: [4] u32
}

#[Swag.Optimize(true)]
func fillStrength(out: *Strength, bs: u32)
{
    // The aggregate is cleared before its lanes are stored, and the vector
    // is copied into a field: a broadcast, no frame temporary.
    var strengths: Strength
    strengths.bs = [bs, bs, bs, bs]
    out.bs       = strengths.bs
}

#[Swag.Optimize(true)]
func fillPartial(out: *Strength, a: u32)
{
    // Only two lanes are named; the cleared aggregate supplies the zeros.
    var strengths: Strength
    strengths.bs[1] = a
    strengths.bs[2] = a
    out.bs = strengths.bs
}

#[Swag.NoInline]
func sumWords(words: *[16] u32)->u32
{
    var sum = 0'u32
    for i in 16 do
        sum += words[][i]
    return sum
}

#[Swag.Optimize(true)]
func fillCopyAndPass(out: [*] u32, a, b, c, d: u32)
{
    // The words are stored one by one, the array is copied whole - four
    // vector loads over the stored words - and then passed by address. The
    // address is the first word's, before the later vectors' slots: the
    // stores behind those slots must stay, since the callee reads them.
    var words: [16] u32
    words[0]  = 1
    words[1]  = 2
    words[2]  = 3
    words[3]  = 4
    words[4]  = a
    words[5]  = b
    words[6]  = c
    words[7]  = d
    words[8]  = d
    words[9]  = c
    words[10] = b
    words[11] = a
    words[12] = a
    words[13] = a
    words[14] = b
    words[15] = b
    var copy = words
    copy[5] = 100
    out[0]  = sumWords(&words)
    out[1]  = copy[5]
    out[2]  = copy[13]
}

#test
{
    var out: [8] u16
    halves(&out[0], 3, 5)
    Swag.assert(out[0] == 3 and out[3] == 3 and out[4] == 5 and out[7] == 5)
    pairs(&out[0], 1, 2, 3, 4)
    Swag.assert(out[0] == 1 and out[1] == 1 and out[2] == 2 and out[3] == 2 and out[4] == 3 and out[6] == 4 and out[7] == 4)
    distinctWords(&out[0], 10, 20, 30, 40, 50, 60, 70, 0xFFFF)
    Swag.assert(out[0] == 10 and out[1] == 20 and out[2] == 30 and out[3] == 40 and out[4] == 50 and out[5] == 60 and out[6] == 70 and out[7] == 0xFFFF)
    sameWord(&out[0], 0xABCD)
    for i in 8 do
        Swag.assert(out[i] == 0xABCD)

    var signed: [8] s16
    alternate(&signed[0], -7, 9)
    Swag.assert(signed[0] == -7 and signed[1] == 9 and signed[6] == -7 and signed[7] == 9)
    withZeros(&signed[0], -1, 2, -3)
    Swag.assert(signed[0] == -1 and signed[1] == 2 and signed[2] == -3 and signed[3] == 0 and signed[4] == -1 and signed[5] == 2 and signed[6] == -3 and signed[7] == 0)
    oneLane(&signed[0], 77)
    Swag.assert(signed[0] == 0 and signed[1] == 0 and signed[2] == 77 and signed[3] == 0 and signed[4] == 0 and signed[5] == 0 and signed[6] == 77 and signed[7] == 0)

    var wide: [4] u32
    dwords(&wide[0], 1, 0x80000000, 3, 0xFFFFFFFF)
    Swag.assert(wide[0] == 1 and wide[1] == 0x80000000 and wide[2] == 3 and wide[3] == 0xFFFFFFFF)

    var narrow: [16] u8
    bytes(&narrow[0], 0xAB, 0xCD)
    Swag.assert(narrow[0] == 0xAB and narrow[1] == 0xCD and narrow[2] == 0 and narrow[3] == 0 and narrow[12] == 0xAB and narrow[13] == 0xCD and narrow[15] == 0)

    Swag.assert(readTwice(&out[0], 100, 200) == 300)
    Swag.assert(out[0] == 100 and out[3] == 100 and out[4] == 200 and out[7] == 200)

    computedLanes(&out[0], 5, 6)
    Swag.assert(out[0] == 6 and out[1] == 6 and out[2] == 12 and out[3] == 12 and out[4] == 7 and out[5] == 7 and out[6] == 12 and out[7] == 12)

    var strength: Strength
    fillStrength(&strength, 7)
    Swag.assert(strength.bs[0] == 7 and strength.bs[1] == 7 and strength.bs[2] == 7 and strength.bs[3] == 7)
    fillPartial(&strength, 9)
    Swag.assert(strength.bs[0] == 0 and strength.bs[1] == 9 and strength.bs[2] == 9 and strength.bs[3] == 0)

    var words: [3] u32
    fillCopyAndPass(&words[0], 10, 20, 30, 40)
    // 10 + 2 * (10 + 20 + 30 + 40) + 2 * 10 + 2 * 20
    Swag.assert(words[0] == 270 and words[1] == 100 and words[2] == 10)
}
