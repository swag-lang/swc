#global private
using Swag

// A vector load or store whose address is a base plus a register, or a base
// plus a scaled register, takes the indexed address form instead of an add of
// its own. The functions are forced to the optimizing backend; the results
// are checked against the scalar arithmetic.

var Plane: [8 * 64] u8
var Out:   [4 * 64] u8

func fillPlane()
{
    for i in 8 * 64 do
        Plane[i] = cast(u8) ((i * 5 + 1) & 0x7F)
}

// Six rows spaced by a runtime stride, summed lane by lane.
#[Swag.Optimize(true)]
func sumSixRows(line: const [*] u8, stride: u64)->#simd [16] u8
{
    let r0 = (cast(const [*] #simd [16] u8) line)[0]
    let r1 = (cast(const [*] #simd [16] u8) (line + stride))[0]
    let r2 = (cast(const [*] #simd [16] u8) (line + 2 * stride))[0]
    let r3 = (cast(const [*] #simd [16] u8) (line + 3 * stride))[0]
    let r4 = (cast(const [*] #simd [16] u8) (line + 4 * stride))[0]
    let r5 = (cast(const [*] #simd [16] u8) (line + 5 * stride))[0]
    return r0 + r1 + r2 + r3 + r4 + r5
}

// The store side: rows written through a base plus a scaled index.
#[Swag.Optimize(true)]
func spreadRows(dst: [*] u8, stride: u64, value: #simd [16] u8, rows: u64)
{
    for row in rows do
        (cast([*] #simd [16] u8) (dst + row * stride))[0] = value + cast(u8) row
}

#test
{
    fillPlane()
    let base = cast(const [*] u8) &Plane[64]
    let sums = cast([16] u8) sumSixRows(base, 64)
    for lane in 16
    {
        var expected: u32
        for k in 6 do
            expected += cast(u32) Plane[64 + k * 64 + lane]
        Swag.assert(sums[lane] == cast(u8) (expected & 0xFF))
    }

    let seed = cast(#simd [16] u8) [1'u8, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16]
    spreadRows(&Out[0], 64, seed, 4)
    for row in 4'u64
    {
        for lane in 16'u64 do
            Swag.assert(Out[row * 64 + lane] == cast(u8) (lane + 1 + row))
    }
}
