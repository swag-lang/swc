#global private
using Swag

const IntrinsicS64Min = -9_223_372_036_854_775_807's64 - 1

// The packed intrinsic vocabulary, checked lane by lane: broadcast, saturation,
// packs, interleaves, widens, average, multiply-add, horizontal sum, float-to-integer conversion,
// gather, permute, select, movemask, and the vector overloads of the scalar math intrinsics.

#[Swag.NoInline]
func splatS32(value: s32)->#simd [4] s32 => Swag.vecsplat(value)

#[Swag.NoInline]
func splatU8(value: u8)->#simd [16] u8 => Swag.vecsplat(value)

#test
{
    // Four independent unsigned indices gather signed dwords in lane order.
    var table: [257] s32
    for i in 257 do
        table[i] = cast(s32) i * 13 - 1000

    let base     = table.buffer
    let indices  = cast(#simd [4] u32) [256, 0, 127, 5]
    let gathered = cast([4] s32) Swag.vecgather(base, indices)
    Swag.assert(gathered[0] == 2328 and gathered[1] == -1000 and gathered[2] == 651 and gathered[3] == -935)
}

#test
{
    // The broadcast fills every lane, from a constant and from a runtime value
    // alike, and the lane type of the scalar names the shape.
    let bytes = cast([16] u8) Swag.vecsplat(7'u8)
    Swag.assert(bytes[0] == 7 and bytes[15] == 7)

    let words = cast([8] s16) Swag.vecsplat(-300's16)
    Swag.assert(words[0] == -300 and words[7] == -300)

    let quads = cast([4] u32) Swag.vecsplat(0xDEAD_BEEF'u32)
    Swag.assert(quads[0] == 0xDEAD_BEEF and quads[3] == 0xDEAD_BEEF)

    let pairs = cast([2] u64) Swag.vecsplat(0x0102_0304_0506_0708'u64)
    Swag.assert(pairs[0] == 0x0102_0304_0506_0708 and pairs[1] == 0x0102_0304_0506_0708)

    let floats = cast([4] f32) Swag.vecsplat(-1.5'f32)
    Swag.assert(floats[0] == -1.5 and floats[3] == -1.5)

    let doubles = cast([2] f64) Swag.vecsplat(2.25'f64)
    Swag.assert(doubles[0] == 2.25 and doubles[1] == 2.25)

    // A runtime scalar takes the same path; the value crosses through a register.
    var byteValue: u8 = 37
    let liveBytes     = cast([16] u8) splatU8(byteValue)
    for byte in liveBytes do
        Swag.assert(byte == byteValue)

    var n: s32 = -9
    let live   = cast([4] s32) splatS32(n)
    Swag.assert(live[0] == -9 and live[3] == -9)

    // A broadcast of a constant is itself a constant.
    const Filled      = Swag.vecsplat(3's32)
    const FilledLanes = cast([4] s32) Filled
    #assert(FilledLanes[0] == 3 and FilledLanes[3] == 3)
}

#test
{
    // Saturating byte arithmetic clamps instead of wrapping.
    let a = Swag.vecsplat(200'u8)
    let b = Swag.vecsplat(100'u8)
    var r = cast([16] u8) Swag.vecsatadd(a, b)
    Swag.assert(r[0] == 255 and r[15] == 255)
    r = cast([16] u8) Swag.vecsatsub(b, a)
    Swag.assert(r[0] == 0 and r[15] == 0)

    let sa = cast(#simd [8] s16) [32000, -32000, 100, -100, 1, -1, 30000, -30000]
    let sb = cast(#simd [8] s16) [1000, -1000, 1, -1, 0, 0, 3000, -3000]
    let sr = cast([8] s16) Swag.vecsatadd(sa, sb)
    Swag.assert(sr[0] == 32767 and sr[1] == -32768 and sr[2] == 101 and sr[3] == -101 and sr[6] == 32767 and sr[7] == -32768)
}

#test
{
    // The saturating narrowing packs: s16 -> u8 clamps to [0, 255].
    let lo = cast(#simd [8] s16) [-5, 0, 100, 255, 256, 300, 42, -1]
    let hi = cast(#simd [8] s16) [1, 2, 3, 4, 5, 6, 7, 8]
    let r  = cast([16] u8) Swag.vecpackus(lo, hi)
    Swag.assert(r[0] == 0 and r[1] == 0 and r[2] == 100 and r[3] == 255 and r[4] == 255 and r[5] == 255 and r[6] == 42 and r[7] == 0)
    Swag.assert(r[8] == 1 and r[15] == 8)

    let rs = cast([8] s16) Swag.vecpackss(cast(#simd [4] s32) [70000, -70000, 5, -5], cast(#simd [4] s32) [1, 2, 3, 4])
    Swag.assert(rs[0] == 32767 and rs[1] == -32768 and rs[2] == 5 and rs[3] == -5 and rs[4] == 1 and rs[7] == 4)
}

#test
{
    // Low and high interleaves alternate the corresponding input halves.
    let bytes0 = cast(#simd [16] u8) [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15]
    let bytes1 = cast(#simd [16] u8) [100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115]
    let low8   = cast([16] u8) Swag.vecinterleavelo(bytes0, bytes1)
    let high8  = cast([16] u8) Swag.vecinterleavehi(bytes0, bytes1)
    Swag.assert(low8[0] == 0 and low8[1] == 100 and low8[14] == 7 and low8[15] == 107)
    Swag.assert(high8[0] == 8 and high8[1] == 108 and high8[14] == 15 and high8[15] == 115)

    let words0 = cast(#simd [8] u16) [0, 1, 2, 3, 4, 5, 6, 7]
    let words1 = cast(#simd [8] u16) [100, 101, 102, 103, 104, 105, 106, 107]
    let low16  = cast([8] u16) Swag.vecinterleavelo(words0, words1)
    let high16 = cast([8] u16) Swag.vecinterleavehi(words0, words1)
    Swag.assert(low16[0] == 0 and low16[1] == 100 and low16[6] == 3 and low16[7] == 103)
    Swag.assert(high16[0] == 4 and high16[1] == 104 and high16[6] == 7 and high16[7] == 107)

    let quads0 = cast(#simd [4] u32) [0, 1, 2, 3]
    let quads1 = cast(#simd [4] u32) [100, 101, 102, 103]
    let low32  = cast([4] u32) Swag.vecinterleavelo(quads0, quads1)
    let high32 = cast([4] u32) Swag.vecinterleavehi(quads0, quads1)
    Swag.assert(low32[0] == 0 and low32[1] == 100 and low32[2] == 1 and low32[3] == 101)
    Swag.assert(high32[0] == 2 and high32[1] == 102 and high32[2] == 3 and high32[3] == 103)

    let octs0  = cast(#simd [2] u64) [0, 1]
    let octs1  = cast(#simd [2] u64) [100, 101]
    let low64  = cast([2] u64) Swag.vecinterleavelo(octs0, octs1)
    let high64 = cast([2] u64) Swag.vecinterleavehi(octs0, octs1)
    Swag.assert(low64[0] == 0 and low64[1] == 100)
    Swag.assert(high64[0] == 1 and high64[1] == 101)
}

#test
{
    // Widening: zero-extension for unsigned lanes, sign-extension for signed.
    let bytes = cast(#simd [16] u8) [1, 2, 3, 4, 5, 6, 7, 8, 250, 251, 252, 253, 254, 255, 0, 128]
    var wl    = cast([8] u16) Swag.vecwidenlo(bytes)
    Swag.assert(wl[0] == 1 and wl[7] == 8)
    var wh = cast([8] u16) Swag.vecwidenhi(bytes)
    Swag.assert(wh[0] == 250 and wh[5] == 255 and wh[6] == 0 and wh[7] == 128)

    let signedBytes = cast(#simd [16] s8) [-1, -2, 3, 4, 5, 6, 7, 8, -120, 9, 10, 11, 12, 13, 14, 15]
    let swl         = cast([8] s16) Swag.vecwidenlo(signedBytes)
    Swag.assert(swl[0] == -1 and swl[1] == -2 and swl[2] == 3)
    let swh = cast([8] s16) Swag.vecwidenhi(signedBytes)
    Swag.assert(swh[0] == -120 and swh[7] == 15)
}

#test
{
    // Rounding average, and the pairwise multiply-add.
    let a = cast(#simd [16] u8) [0, 1, 2, 3, 10, 20, 30, 40, 100, 101, 102, 103, 200, 201, 254, 255]
    let b = cast(#simd [16] u8) [1, 1, 3, 3, 11, 21, 31, 41, 103, 104, 105, 106, 201, 202, 255, 255]
    let r = cast([16] u8) Swag.vecavgr(a, b)
    Swag.assert(r[0] == 1 and r[1] == 1 and r[2] == 3 and r[3] == 3)
    Swag.assert(r[8] == 102 and r[12] == 201 and r[14] == 255 and r[15] == 255)

    let m1 = cast(#simd [8] s16) [1, 2, 3, 4, -5, 6, 100, 100]
    let m2 = cast(#simd [8] s16) [10, 10, 10, 10, 10, 10, 300, 300]
    let mr = cast([4] s32) Swag.vecmadd(m1, m2)
    Swag.assert(mr[0] == 30 and mr[1] == 70 and mr[2] == 10 and mr[3] == 60000)

    Swag.assert(Swag.vecreduceadd(cast(#simd [4] s32) [1, 2, 3, 4]) == 10)
    Swag.assert(Swag.vecreduceadd(cast(#simd [4] s32) [2_147_483_647, 1, 0, 0]) == -2_147_483_648)
}

#test
{
    // Packed float-to-s32 conversion truncates toward zero. Invalid lanes use
    // the machine integer-indefinite value, 's32.Min'.
    let finite = cast(#simd [4] f32) [1.9, -1.9, 32767.99, -32768.99]
    let ints   = cast([4] s32) Swag.vectruncs32(finite)
    Swag.assert(ints[0] == 1 and ints[1] == -1 and ints[2] == 32767 and ints[3] == -32768)

    let invalid  = cast(#simd [4] f32) [3_000_000_000.0, -3_000_000_000.0, cast #bit(f32) 0x7FC0_0000'u32, 0.0]
    let fallback = cast([4] s32) Swag.vectruncs32(invalid)
    Swag.assert(fallback[0] == -2_147_483_648 and fallback[1] == -2_147_483_648 and fallback[2] == -2_147_483_648 and fallback[3] == 0)
}

#test
{
    // Dynamic byte permute: a reversal table, and the zeroing high bit.
    let v     = cast(#simd [16] u8) [10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25]
    let table = cast(#simd [16] u8) [15, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 0]
    var r     = cast([16] u8) Swag.vecperm(v, table)
    Swag.assert(r[0] == 25 and r[15] == 10 and r[7] == 18)

    let zeroing = cast(#simd [16] u8) [0, 0x80, 1, 0x81, 2, 0x82, 3, 0x83, 4, 5, 6, 7, 8, 9, 10, 11]
    r = cast([16] u8) Swag.vecperm(v, zeroing)
    Swag.assert(r[0] == 10 and r[1] == 0 and r[2] == 11 and r[3] == 0 and r[4] == 12 and r[5] == 0)
}

#test
{
    // Per-lane select through a compare mask, and the mask reductions.
    let a    = cast(#simd [4] s32) [1, 50, 3, 70]
    let b    = cast(#simd [4] s32) [10, 20, 30, 40]
    let mask = a > b
    let r    = cast([4] s32) Swag.vecselect(mask, a, b)
    Swag.assert(r[0] == 10 and r[1] == 50 and r[2] == 30 and r[3] == 70)

    Swag.assert(Swag.vecmask(mask) == 0b1010)
    Swag.assert(Swag.vecany(mask))
    Swag.assert(!Swag.vecall(mask))

    let full = a == a
    Swag.assert(Swag.vecall(full))
    Swag.assert(Swag.vecmask(full) == 0b1111)

    let none = a != a
    Swag.assert(!Swag.vecany(none))
    Swag.assert(Swag.vecmask(none) == 0)

    // Byte and word masks route through the byte movemask.
    let b8 = Swag.vecsplat(1'u8)
    let m8 = b8 == b8
    Swag.assert(Swag.vecmask(m8) == 0xFFFF)
    Swag.assert(Swag.vecall(m8))

    let w16 = Swag.vecsplat(3'u16)
    let m16 = w16 == w16
    Swag.assert(Swag.vecmask(m16) == 0xFF)
    Swag.assert(Swag.vecall(m16) and Swag.vecany(m16))
}

#test
{
    // Vector overloads of the scalar math intrinsics.
    let a = cast(#simd [4] s32) [5, -3, 100, -100]
    let b = cast(#simd [4] s32) [4, 4, -50, 50]
    var r = cast([4] s32) Swag.min(a, b)
    Swag.assert(r[0] == 4 and r[1] == -3 and r[2] == -50 and r[3] == -100)
    r = cast([4] s32) Swag.max(a, b)
    Swag.assert(r[0] == 5 and r[1] == 4 and r[2] == 100 and r[3] == 50)
    r = cast([4] s32) Swag.abs(a)
    Swag.assert(r[0] == 5 and r[1] == 3 and r[2] == 100 and r[3] == 100)

    let s64a   = cast(#simd [2] s64) [IntrinsicS64Min, 9_000_000_000]
    let s64b   = cast(#simd [2] s64) [-7, 10_000_000_000]
    let s64min = cast([2] s64) Swag.min(s64a, s64b)
    let s64max = cast([2] s64) Swag.max(s64a, s64b)
    let s64abs = cast([2] s64) Swag.abs(s64a)
    Swag.assert(s64min[0] == IntrinsicS64Min and s64min[1] == 9_000_000_000)
    Swag.assert(s64max[0] == -7 and s64max[1] == 10_000_000_000)
    Swag.assert(s64abs[0] == IntrinsicS64Min and s64abs[1] == 9_000_000_000)

    let u64a   = cast(#simd [2] u64) [0, 0xFFFF_FFFF_FFFF_FFFF]
    let u64b   = cast(#simd [2] u64) [0xFFFF_FFFF_FFFF_FFFF, 4_000_000_000]
    let u64min = cast([2] u64) Swag.min(u64a, u64b)
    let u64max = cast([2] u64) Swag.max(u64a, u64b)
    Swag.assert(u64min[0] == 0 and u64min[1] == 4_000_000_000)
    Swag.assert(u64max[0] == 0xFFFF_FFFF_FFFF_FFFF and u64max[1] == 0xFFFF_FFFF_FFFF_FFFF)

    let ua = cast(#simd [16] u8) [1, 200, 3, 200, 1, 200, 1, 200, 1, 200, 1, 200, 1, 200, 1, 200]
    let ub = Swag.vecsplat(100'u8)
    let ur = cast([16] u8) Swag.max(ua, ub)
    Swag.assert(ur[0] == 100 and ur[1] == 200 and ur[2] == 100)

    let f  = cast(#simd [4] f32) [1.0, 4.0, 9.0, 16.0]
    let fr = cast([4] f32) Swag.sqrt(f)
    Swag.assert(fr[0] == 1.0 and fr[1] == 2.0 and fr[2] == 3.0 and fr[3] == 4.0)

    let g  = cast(#simd [4] f32) [1.5, -1.5, 2.5, -2.5]
    var gr = cast([4] f32) Swag.floor(g)
    Swag.assert(gr[0] == 1.0 and gr[1] == -2.0 and gr[2] == 2.0 and gr[3] == -3.0)
    gr = cast([4] f32) Swag.ceil(g)
    Swag.assert(gr[0] == 2.0 and gr[1] == -1.0 and gr[2] == 3.0 and gr[3] == -2.0)
    gr = cast([4] f32) Swag.trunc(g)
    Swag.assert(gr[0] == 1.0 and gr[1] == -1.0 and gr[2] == 2.0 and gr[3] == -2.0)

    let h  = Swag.vecsplat(2.0'f32)
    let hr = cast([4] f32) Swag.muladd(g, h, f)
    Swag.assert(hr[0] == 4.0 and hr[1] == 1.0 and hr[2] == 14.0 and hr[3] == 11.0)
}
