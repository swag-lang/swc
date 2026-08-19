// An overloaded intrinsic call passed directly as an inline-call argument must keep the
// overload it resolved to: cloning the argument into the expansion used to re-pin the
// cloned callee on the first overload of the set and fail the re-match.

#[Swag.Inline]
func addF(a, b: f32)->f32 => a + b

#[Swag.Inline]
func addU(a, b: u64)->u64 => a + b

#[Swag.Inline]
func addQuad(a, b: #simd [4] s32)->#simd [4] s32 => a + b

#test
{
    let f = addF(@min(1.5'f32, 2.5), @max(1.5'f32, 2.5))
    @assert(f == 4.0)

    let u = addU(@min(3'u64, 4), @max(3'u64, 4))
    @assert(u == 7)
}

#test
{
    var v: #simd [8] s16
    v += 5
    let r = cast([4] s32) addQuad(@vecwidenlo(v), @vecwidenhi(v))
    @assert(r[0] == 10 and r[3] == 10)
}
