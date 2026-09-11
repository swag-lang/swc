#global private
using Swag

// An array of vectors declared first in the function is indexed through the
// frame base itself; the vectors loaded beside it must still reach their
// readers, in registers or not.

#[Swag.Optimize(true)]
func centerRows(dst: [*] u16, src: const [*] u8, stride: u64, height: u64)
{
    var sums: [21] #simd [8] u16
    for row in height + 5
    {
        let line = src + row * stride
        let r0   = (cast(const [*] #simd [16] u8) line)[0]
        let r1   = (cast(const [*] #simd [16] u8) (line + 1))[0]
        sums[row] = Swag.vecwidenlo(r0) + Swag.vecwidenlo(r1) + Swag.vecwidenhi(r0)
    }

    for row in height
    {
        (cast([*] #simd [8] u16) (dst + row * 8))[0] = sums[row] + sums[row + 2] + sums[row + 5]
    }
}

#[Swag.Optimize(true)]
func sumTable(values: const [*] u32, count: u64)->u32
{
    var table: [16] u32
    var total = 0'u32
    for i in count do
        table[i] = values[i] * 2
    for i in count do
        total += table[i]
    return total + cast(u32) count
}

#test
{
    var plane: [16 * 64] u8
    var out:   [4 * 8] u16
    for i in 16 * 64 do
        plane[i] = cast(u8) (i & 0x3F)
    centerRows(&out[0], &plane[0], 64, 4)

    // Lane 0 of row r of `sums` is p[r*64] + p[r*64 + 1] + p[r*64 + 8].
    var expected: [9] u16
    for r in 9
    {
        let a = cast(u16) plane[r * 64]
        let b = cast(u16) plane[r * 64 + 1]
        let c = cast(u16) plane[r * 64 + 8]
        expected[r] = a + b + c
    }
    for row in 4 do
        Swag.assert(out[row * 8] == expected[row] + expected[row + 2] + expected[row + 5])

    var values: [6] u32 = [1, 2, 3, 4, 5, 6]
    Swag.assert(sumTable(&values[0], 6) == 42 + 6)
}
