#global private
using Swag

// The low lanes of a vector written to memory: the value must reach memory
// whether the store goes through a general register or straight from the
// vector register.

#[Swag.Optimize(true)]
func storeLowRows(dst: [*] u8, dstStride: u64, src: const [*] u8, srcStride: u64, rows: u64)
{
    for row in rows
    {
        let bytes   = (cast(const [*] #simd [16] u8) (src + row * srcStride))[0]
        let doubled = bytes + bytes
        (cast([*] u64) (dst + row * dstStride))[0] = (cast #bit(#simd [2] u64) doubled)[0]
    }
}

#[Swag.Optimize(true)]
func storeLow4(dst: [*] u8, value: #simd [16] u8)
{
    (cast([*] u32) dst)[0] = (cast #bit(#simd [4] u32) value)[0]
}

#[Swag.Optimize(true)]
func storeLow4Indexed(dst: [*] u8, index: u64, value: #simd [16] u8)
{
    (cast([*] u32) (dst + index))[0] = (cast #bit(#simd [4] u32) value)[0]
}

#[Swag.Optimize(true)]
func storeBits(dst: [*] u64, value: f64)
{
    dst[0] = cast #bit(u64) value
}

#test
{
    var plane: [4 * 64] u8
    var out:   [4 * 16] u8
    for i in 4 * 64 do
        plane[i] = cast(u8) (i & 0x3F)

    storeLowRows(&out[0], 16, &plane[0], 64, 4)
    Swag.assert(out[0] == 0 and out[1] == 2 and out[7] == 14)
    Swag.assert(out[8] == 0 and out[16] == 0 and out[17] == 2 and out[23] == 14)
    Swag.assert(out[48] == 0 and out[55] == 14)

    let digits = cast(#simd [16] u8) [9, 8, 7, 6, 5, 4, 3, 2, 1, 0, 0, 0, 0, 0, 0, 0]
    storeLow4(&out[8], digits)
    Swag.assert(out[8] == 9 and out[11] == 6 and out[12] == 0)

    storeLow4Indexed(&out[0], 28, digits)
    Swag.assert(out[27] == 0 and out[28] == 9 and out[31] == 6 and out[32] == 0)

    var bits: [1] u64
    storeBits(&bits[0], 1.0)
    Swag.assert(bits[0] == 0x3FF0_0000_0000_0000)
}
