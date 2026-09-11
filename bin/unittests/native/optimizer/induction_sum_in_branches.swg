#global private
using Swag

// A pointer built from the row counter in each branch of the loop body: the
// stores must land at the same addresses whichever way the sums are carried.

#[Swag.Optimize(true)]
func storeRows(dst: [*] u8, dstStride: u64, src: const [*] u8, srcStride: u64, rows: u64, width: s32)
{
    for row in rows
    {
        let bytes   = (cast(const [*] #simd [16] u8) (src + row * srcStride))[0]
        let doubled = bytes + bytes
        if width == 8 do
            (cast([*] u64) (dst + row * dstStride))[0] = (cast #bit(#simd [2] u64) doubled)[0]
        else do
            (cast([*] u32) (dst + row * dstStride))[0] = (cast #bit(#simd [4] u32) doubled)[0]
    }
}

#[Swag.Optimize(true)]
func fillRows(dst: [*] u32, stride: u64, rows: u64, odd: u32, even: u32)
{
    for row in rows
    {
        if row & 1 == 1 do
            dst[row * stride] = odd
        else do
            dst[row * stride + 1] = even
    }
}

#test
{
    var plane: [4 * 64] u8
    var out:   [4 * 16] u8
    for i in 4 * 64 do
        plane[i] = cast(u8) (i & 0x3F)

    storeRows(&out[0], 16, &plane[0], 64, 4, 8)
    Swag.assert(out[0] == 0 and out[7] == 14 and out[8] == 0)
    Swag.assert(out[16] == 0 and out[17] == 2 and out[48] == 0 and out[55] == 14)

    storeRows(&out[0], 16, &plane[0], 64, 4, 4)
    Swag.assert(out[3] == 6 and out[7] == 14 and out[51] == 6)

    var words: [4 * 8] u32
    fillRows(&words[0], 8, 4, 7, 9)
    Swag.assert(words[0] == 0 and words[1] == 9 and words[8] == 7 and words[9] == 0)
    Swag.assert(words[16] == 0 and words[17] == 9 and words[24] == 7)
}
