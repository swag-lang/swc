#global private
using Swag

// Compile-time execution drives the same packed lowering as the native
// backend: the vector arithmetic below runs inside the compiler.

#[Swag.NoInline]
func horizontalSum(v: #simd [4] s32)->s32
{
    return @vecsum(v)
}

#[Swag.NoInline]
func compute()->s32
{
    let a = cast(#simd [4] s32) [1, 2, 3, 4]
    let b = a * a + a - 1
    return horizontalSum(b << 1)
}

const Computed = #run compute()
#assert(Computed == (1 + 5 + 11 + 19) * 2)

#test
{
    let a = cast(#simd [8] s16) [1, 2, 3, 4, 5, 6, 7, 8]
    let m = cast([8] u16) (a > @vecsplat(4's16))
    @assert(m[0] == 0 and m[3] == 0 and m[4] == 0xFFFF and m[7] == 0xFFFF)

    let f = cast(#simd [4] f32) [2.0, 4.0, 8.0, 16.0]
    let h = cast([4] f32) (f / @vecsplat(2.0'f32))
    @assert(h[0] == 1.0 and h[3] == 8.0)
}
