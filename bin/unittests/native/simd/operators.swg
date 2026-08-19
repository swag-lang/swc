#global private
using Swag

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
    let a = makeS32(1, 2, 3, 4)
    let b = makeS32(10, 20, 30, 40)
    let c = a
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
    let big  = cast(#simd [4] s32) 2_147_483_647
    let one  = cast(#simd [4] s32) 1
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
    r = lanesOf(-a)
    @assert(r[0] == -12 and r[2] == 1 and r[3] == 0)
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
}

#test
{
    // Sixteen u8 lanes and eight s16 lanes.
    let a8 = cast(#simd [16] u8) 200'u8
    let b8 = cast(#simd [16] u8) 100'u8
    let r8 = cast([16] u8) (a8 + b8)
    @assert(r8[0] == 44 and r8[15] == 44)

    let a16 = cast(#simd [8] s16) [1, -2, 3, -4, 5, -6, 7, -8]
    let b16 = cast(#simd [8] s16) 10's16
    let r16 = cast([8] s16) (a16 * b16)
    @assert(r16[0] == 10 and r16[1] == -20 and r16[7] == -80)
}

#test
{
    // Float lanes: the four arithmetic operators.
    let a = cast(#simd [4] f32) [1.0, 2.0, 3.0, 4.0]
    let b = cast(#simd [4] f32) 2.0'f32
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
    let fb = cast(#simd [4] f32) 2.5'f32
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

#test
{
    let r = lanesOf(addAll(makeS32(1, 2, 3, 4), makeS32(10, 20, 30, 40), makeS32(100, 200, 300, 400)))
    @assert(r[0] == 111 and r[1] == 222 and r[2] == 333 and r[3] == 444)
}

// Global vectors live in aligned storage and are readable at startup.
var g_Vector = cast(#simd [4] s32) [7, 8, 9, 10]

#test
{
    @assert(g_Vector[0] == 7)
    g_Vector += 1
    @assert(g_Vector[3] == 11)
}
