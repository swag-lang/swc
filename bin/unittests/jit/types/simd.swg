#global private
using Swag

const JitS64Min = -9_223_372_036_854_775_807's64 - 1

// Compile-time execution drives the same packed lowering as the native
// backend: the vector arithmetic below runs inside the compiler.

#[Swag.NoInline]
func horizontalSum(v: #simd [4] s32)->s32
{
    return @vecsum(v)
}

#[Swag.NoInline]
func sumEight(a, b, c, d, e, f, g, h: #simd [4] s32)->s32
{
    return @vecsum(a + b + c + d + e + f + g + h)
}

#[Swag.NoInline]
func wideMath()->s64
{
    let a = cast(#simd [2] s64) [JitS64Min, -9_000_000_000]
    let b = cast(#simd [2] s64) [-7, 10_000_000_000]
    return @min(a, b)[0] + @max(a, b)[1] + @abs(a)[1] + (a >> 64)[1]
}

#[Swag.NoInline]
func byteShift()->u8
{
    let bytes = cast(#simd [16] u8) [0x81, 0x7F, 1, 0, 255, 128, 64, 3, 1, 2, 3, 4, 5, 6, 7, 8]
    return (bytes << 1)[0] + (bytes >> 1)[1]
}

#[Swag.NoInline]
func wideMultiply()->u64
{
    let a = cast(#simd [2] u64) [0xFFFF_FFFF_FFFF_FFFF, 0x1_0000_0001]
    let b = cast(#simd [2] u64) [2, 0x1_0000_0001]
    return (a * b)[1]
}

#[Swag.NoInline]
func compute()->s32
{
    let a = cast(#simd [4] s32) [1, 2, 3, 4]
    let b = +a * a + a - 1
    return horizontalSum(b << 1)
}

const Computed = #run compute()
#assert(Computed == (1 + 5 + 11 + 19) * 2)

const FoldedStackArgs = #run sumEight(@vecsplat(1's32), @vecsplat(2's32), @vecsplat(3's32), @vecsplat(4's32), @vecsplat(5's32), @vecsplat(6's32), @vecsplat(7's32), @vecsplat(8's32))
#assert(FoldedStackArgs == 144)

const FoldedWideMath = #run wideMath()
#assert(FoldedWideMath == JitS64Min + 18_999_999_999)

const FoldedByteShift = #run byteShift()
#assert(FoldedByteShift == 65)

const FoldedWideMultiply = #run wideMultiply()
#assert(FoldedWideMultiply == 0x2_0000_0001)

#test
{
    let a = cast(#simd [8] s16) [1, 2, 3, 4, 5, 6, 7, 8]
    let m = cast([8] u16) (a > @vecsplat(4's16))
    @assert(m[0] == 0 and m[3] == 0 and m[4] == 0xFFFF and m[7] == 0xFFFF)

    let f = cast(#simd [4] f32) [2.0, 4.0, 8.0, 16.0]
    let h = cast([4] f32) (f / @vecsplat(2.0'f32))
    @assert(h[0] == 1.0 and h[3] == 8.0)
}
