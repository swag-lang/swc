#global private
using Swag

const OperatorS64Min = -9_223_372_036_854_775_807's64 - 1

// Element-wise '#simd' operators, checked lane by lane against scalar
// arithmetic on every shape the operator supports.

#[Swag.NoInline]
func makeS32(a, b, c, d: s32)->#simd [4] s32
{
    var lanes: [4] s32 = [a, b, c, d]
    return cast(#simd [4] s32) lanes
}

#[Swag.NoInline]
func lanesOf(v: #simd [4] s32)->[4] s32 => cast([4] s32) v

#test
{
    // Construction, copies, parameters and returns ride one xmm register.
    let a   = makeS32(1, 2, 3, 4)
    let b   = makeS32(10, 20, 30, 40)
    let c   = a
    var sum = lanesOf(a + b)
    @assert(sum[0] == 11 and sum[1] == 22 and sum[2] == 33 and sum[3] == 44)
    sum = lanesOf(b - c)
    @assert(sum[0] == 9 and sum[1] == 18 and sum[2] == 27 and sum[3] == 36)
    sum = lanesOf(a * b)
    @assert(sum[0] == 10 and sum[1] == 40 and sum[2] == 90 and sum[3] == 160)
}

#test
{
    // Wrapping is the definition, not an error: no overflow guard fires.
    let big  = @vecsplat(2_147_483_647's32)
    let one  = @vecsplat(1's32)
    let wrap = lanesOf(big + one)
    @assert(wrap[0] == -2_147_483_648)
    @assert(wrap[3] == -2_147_483_648)
}

#test
{
    // Scalar broadcast on either side, and the compound forms.
    var v = makeS32(1, 2, 3, 4)
    var r = lanesOf(v + 100)
    @assert(r[0] == 101 and r[3] == 104)
    r = lanesOf(1000 - v)
    @assert(r[0] == 999 and r[3] == 996)
    v += 5
    r = lanesOf(v)
    @assert(r[0] == 6 and r[3] == 9)
    v *= 2
    r = lanesOf(v)
    @assert(r[0] == 12 and r[3] == 18)
}

#test
{
    // Bitwise operators and unary forms.
    let a = makeS32(0b1100, 0b1010, -1, 0)
    let b = makeS32(0b1010, 0b0110, 0, -1)
    var r = lanesOf(a & b)
    @assert(r[0] == 0b1000 and r[1] == 0b0010 and r[2] == 0 and r[3] == 0)
    r = lanesOf(a | b)
    @assert(r[0] == 0b1110 and r[1] == 0b1110 and r[2] == -1 and r[3] == -1)
    r = lanesOf(a ^ b)
    @assert(r[0] == 0b0110 and r[1] == 0b1100 and r[2] == -1 and r[3] == -1)
    r = lanesOf(~a)
    @assert(r[0] == -13 and r[2] == 0 and r[3] == -1)
    r = lanesOf(+a)
    @assert(r[0] == 12 and r[1] == 10 and r[2] == -1 and r[3] == 0)
    r = lanesOf(-a)
    @assert(r[0] == -12 and r[2] == 1 and r[3] == 0)
}

#test
{
    // The same unary forms on a compile-time constant vector. A vector never folds:
    // the lanes are computed by the hardware here exactly as they are on a runtime
    // value, and the constant operand takes the same path.
    const Lanes: #simd [4] s32 = [0b1100, 0b1010, -1, 0]
    var r = lanesOf(-Lanes)
    @assert(r[0] == -12 and r[2] == 1 and r[3] == 0)
    r = lanesOf(+Lanes)
    @assert(r[0] == 12 and r[1] == 10 and r[2] == -1 and r[3] == 0)
    r = lanesOf(~Lanes)
    @assert(r[0] == -13 and r[2] == 0 and r[3] == -1)

    // A splat is a constant too, and so is the result of a constant cast.
    let splat = @vecsplat(5's32)
    r = lanesOf(-splat)
    @assert(r[0] == -5 and r[3] == -5)

    let literal: #simd [4] s32 = [1, 2, 3, 4]
    r = lanesOf(~literal)
    @assert(r[0] == -2 and r[3] == -5)
}

#test
{
    // Shifts by a constant and by a runtime count.
    let v = makeS32(1, 2, -4, 256)
    var r = lanesOf(v << 4)
    @assert(r[0] == 16 and r[1] == 32 and r[3] == 4096)
    r = lanesOf(v >> 1)
    @assert(r[0] == 0 and r[1] == 1 and r[2] == -2 and r[3] == 128)

    var count: u32 = 2
    r = lanesOf(v << count)
    @assert(r[0] == 4 and r[1] == 8 and r[3] == 1024)

    // Unsigned lanes shift logically.
    let u  = cast(#simd [4] u32) [0x8000_0000, 4, 2, 1]
    let ru = cast([4] u32) (u >> 1)
    @assert(ru[0] == 0x4000_0000 and ru[1] == 2)

    // Byte lanes widen and repack in registers.
    let bytes = cast(#simd [16] u8) [0x81, 0x7F, 1, 0, 255, 128, 64, 3, 1, 2, 3, 4, 5, 6, 7, 8]
    let bytesLeft = cast([16] u8) (bytes << 1)
    let bytesRight = cast([16] u8) (bytes >> 1)
    @assert(bytesLeft[0] == 2 and bytesLeft[1] == 254 and bytesLeft[4] == 254)
    @assert(bytesRight[0] == 0x40 and bytesRight[1] == 0x3F and bytesRight[4] == 127)

    let signedBytes = cast(#simd [16] s8) [-128, -3, 127, 1, -1, 0, 2, -2, 1, 2, 3, 4, 5, 6, 7, 8]
    let signedRight = cast([16] s8) (signedBytes >> 1)
    @assert(signedRight[0] == -64 and signedRight[1] == -2 and signedRight[2] == 63 and signedRight[3] == 0)

    count = 8
    let bytesGone = cast([16] u8) (bytes << count)
    let signsOnly = cast([16] s8) (signedBytes >> count)
    @assert(bytesGone[0] == 0 and bytesGone[15] == 0)
    @assert(signsOnly[0] == -1 and signsOnly[1] == -1 and signsOnly[2] == 0)

    let wide = cast(#simd [2] s64) [-8, 0x4000_0000_0000_0000]
    let wideRight = cast([2] s64) (wide >> 2)
    @assert(wideRight[0] == -2 and wideRight[1] == 0x1000_0000_0000_0000)

    count = 64
    let wideSigns = cast([2] s64) (wide >> count)
    @assert(wideSigns[0] == -1 and wideSigns[1] == 0)
}

#test
{
    // Sixteen u8 lanes and eight s16 lanes.
    let a8 = @vecsplat(200'u8)
    let b8 = @vecsplat(100'u8)
    let r8 = cast([16] u8) (a8 + b8)
    @assert(r8[0] == 44 and r8[15] == 44)

    let mul8a = cast(#simd [16] u8) [200, 255, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16]
    let mul8 = cast([16] u8) (mul8a * @vecsplat(2'u8))
    @assert(mul8[0] == 144 and mul8[1] == 254 and mul8[15] == 32)

    let signedMul8a = cast(#simd [16] s8) [-100, -128, -3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16]
    let signedMul8 = cast([16] s8) (signedMul8a * @vecsplat(3's8))
    @assert(signedMul8[0] == -44 and signedMul8[1] == -128 and signedMul8[2] == -9)

    let a16 = cast(#simd [8] s16) [1, -2, 3, -4, 5, -6, 7, -8]
    let b16 = @vecsplat(10's16)
    let r16 = cast([8] s16) (a16 * b16)
    @assert(r16[0] == 10 and r16[1] == -20 and r16[7] == -80)

    let u64a = cast(#simd [2] u64) [0xFFFF_FFFF_FFFF_FFFF, 0x1_0000_0001]
    let u64b = cast(#simd [2] u64) [2, 0x1_0000_0001]
    let mul64 = cast([2] u64) (u64a * u64b)
    @assert(mul64[0] == 0xFFFF_FFFF_FFFF_FFFE and mul64[1] == 0x2_0000_0001)

    let signedMul64a = cast(#simd [2] s64) [-3, OperatorS64Min]
    let signedMul64b = cast(#simd [2] s64) [-7, 3]
    let signedMul64 = cast([2] s64) (signedMul64a * signedMul64b)
    @assert(signedMul64[0] == 21 and signedMul64[1] == OperatorS64Min)
}

#test
{
    // Float lanes: the four arithmetic operators.
    let a = cast(#simd [4] f32) [1.0, 2.0, 3.0, 4.0]
    let b = @vecsplat(2.0'f32)
    var r = cast([4] f32) (a * b)
    @assert(r[0] == 2.0 and r[3] == 8.0)
    r = cast([4] f32) (a / b)
    @assert(r[0] == 0.5 and r[3] == 2.0)
    r = cast([4] f32) (a + b)
    @assert(r[1] == 4.0)
    r = cast([4] f32) (a - b)
    @assert(r[2] == 1.0)

    let d  = cast(#simd [2] f64) [1.5, -2.5]
    let rd = cast([2] f64) (d + d)
    @assert(rd[0] == 3.0 and rd[1] == -5.0)
}

#test
{
    // Comparisons produce unsigned masks: all-ones where the compare holds.
    let a = makeS32(1, 5, 3, -7)
    let b = makeS32(2, 5, 1, 7)
    var m = cast([4] u32) (a == b)
    @assert(m[0] == 0 and m[1] == 0xFFFF_FFFF and m[2] == 0 and m[3] == 0)
    m = cast([4] u32) (a != b)
    @assert(m[0] == 0xFFFF_FFFF and m[1] == 0)
    m = cast([4] u32) (a < b)
    @assert(m[0] == 0xFFFF_FFFF and m[1] == 0 and m[2] == 0 and m[3] == 0xFFFF_FFFF)
    m = cast([4] u32) (a >= b)
    @assert(m[0] == 0 and m[1] == 0xFFFF_FFFF and m[2] == 0xFFFF_FFFF and m[3] == 0)

    // Unsigned ordering goes through the sign-bias lowering.
    let ua = cast(#simd [4] u32) [0xFFFF_FFFF, 1, 0x8000_0000, 0]
    let ub = cast(#simd [4] u32) [1, 0xFFFF_FFFF, 0x7FFF_FFFF, 0]
    m = cast([4] u32) (ua > ub)
    @assert(m[0] == 0xFFFF_FFFF and m[1] == 0 and m[2] == 0xFFFF_FFFF and m[3] == 0)

    // Float compares use the hardware predicates.
    let fa = cast(#simd [4] f32) [1.0, 2.0, 3.0, 4.0]
    let fb = @vecsplat(2.5'f32)
    m = cast([4] u32) (fa < fb)
    @assert(m[0] == 0xFFFF_FFFF and m[1] == 0xFFFF_FFFF and m[2] == 0 and m[3] == 0)
}

#test
{
    // Lane access: constant and dynamic indices, reads and writes.
    var v = makeS32(10, 20, 30, 40)
    @assert(v[0] == 10 and v[3] == 40)
    v[1] = 99
    @assert(v[1] == 99)

    var idx: u64 = 2
    @assert(v[idx] == 30)
    v[idx] = -5
    @assert(v[2] == -5)

    // Lane access on an rvalue goes through the spill slot.
    @assert((v + v)[1] == 198)
}

#test
{
    // Reinterpretations: '#bit' between shapes, and the array round trip.
    let v  = cast(#simd [4] u32) [0x04030201, 0x08070605, 0x0C0B0A09, 0x100F0E0D]
    let b  = cast #bit(#simd [16] u8) v
    let rb = cast([16] u8) b
    @assert(rb[0] == 1 and rb[1] == 2 and rb[15] == 16)

    var arr: [4] u32 = [5, 6, 7, 8]
    let w            = cast(#simd [4] u32) arr
    let back         = cast([4] u32) w
    @assert(back[0] == 5 and back[3] == 8)
}

// A vector crossing a Swag-convention module boundary is exercised by the
// workspace suite; here the same convention drives a plain local call chain.
#[Swag.NoInline]
func addAll(a, b, c: #simd [4] s32)->#simd [4] s32 => a + b + c

#[Swag.NoInline]
func addEight(a, b, c, d, e, f, g, h: #simd [4] s32)->#simd [4] s32 => a + b + c + d + e + f + g + h

#test
{
    let r = lanesOf(addAll(makeS32(1, 2, 3, 4), makeS32(10, 20, 30, 40), makeS32(100, 200, 300, 400)))
    @assert(r[0] == 111 and r[1] == 222 and r[2] == 333 and r[3] == 444)

    let one   = @vecsplat(1's32)
    let two   = @vecsplat(2's32)
    let three = @vecsplat(3's32)
    let four  = @vecsplat(4's32)
    let five  = @vecsplat(5's32)
    let six   = @vecsplat(6's32)
    let seven = @vecsplat(7's32)
    let eight = @vecsplat(8's32)
    let many  = lanesOf(addEight(one, two, three, four, five, six, seven, eight))
    @assert(many[0] == 36 and many[1] == 36 and many[2] == 36 and many[3] == 36)
}

// Global vectors live in aligned storage and are readable at startup.
var g_Vector = cast(#simd [4] s32) [7, 8, 9, 10]

#test
{
    @assert(g_Vector[0] == 7)
    g_Vector += 1
    @assert(g_Vector[3] == 11)
}
