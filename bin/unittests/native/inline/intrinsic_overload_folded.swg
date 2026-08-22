#global private

// A constant-folded overloaded intrinsic call inside an auto-inlined body keeps its overload.
// Cloning the body into the caller pinned the callee on the first overload of the set — the
// one the intrinsic identifier stores — and a call folded to a constant had no selected
// function of its own to override that pin, so `@vecsplat(1'u32)` came back as sixteen bytes
// and `@min(1'u32, ...)` lost its width. Only the release build inlines these automatically.

func addOneU32(v: #simd [4] u32)->#simd [4] u32 => v + @vecsplat(1'u32)

func addTwoS16(v: #simd [8] s16)->#simd [8] s16 => v + @vecsplat(2's16)

func addLocalConst(v: #simd [4] u32)->#simd [4] u32
{
    let one: u32 = 1
    return v + @vecsplat(one)
}

func clampedMin(x: u32)->u32 => @min(x, @max(300'u32, 200))

#test
{
    let v = cast(#simd [4] u32) [1, 2, 3, 4]
    let a = cast([4] u32) addOneU32(v)
    @assert(a[0] == 2 and a[3] == 5)

    let w = cast(#simd [8] s16) [1, 2, 3, 4, 5, 6, 7, 8]
    let b = cast([8] s16) addTwoS16(w)
    @assert(b[0] == 3 and b[7] == 10)

    let c = cast([4] u32) addLocalConst(v)
    @assert(c[1] == 3 and c[2] == 4)

    @assert(clampedMin(1000) == 300)
    @assert(clampedMin(10) == 10)
}
