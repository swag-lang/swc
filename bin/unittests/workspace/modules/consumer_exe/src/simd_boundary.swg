#global private
using Swag, ExportApi

// A vector crosses the module boundary in the Swag calling convention only:
// the provider's generated export re-parses the '#simd' spelling, and the
// value rides one float register through the foreign call.
#test
{
    let a = cast(#simd [4] s32) [1, 2, 3, 4]
    let b = cast(#simd [4] s32) [10, 20, 30, 40]
    let r = cast([4] s32) depAddVectors(a, b)
    @assert(r[0] == 11 and r[1] == 22 and r[2] == 33 and r[3] == 44)

    let x = cast(#simd [16] u8) 200'u8
    let s = cast([16] u8) depSatAddVectors(x, x)
    @assert(s[0] == 255 and s[15] == 255)

    // Non-constant operands: this call cannot fold at compile time, so the
    // vector really crosses the module boundary at run time.
    var lanes: [4] s32
    lanes[0] = 1
    lanes[1] = 2
    lanes[2] = 3
    lanes[3] = 4
    let av = cast(#simd [4] s32) lanes
    let rv = cast([4] s32) depAddVectors(av, av)
    @assert(rv[0] == 2 and rv[1] == 4 and rv[2] == 6 and rv[3] == 8)
}
