#global private
using Swag

// A vector constant - a broadcast lane, a rounding term, a mask - lives in
// the constant pool, and the read of it needs no address in a general
// register: the pool is reached from the instruction pointer. The values must
// be the same whether the access holds an address or names the pool.

#[Swag.Optimize(true)]
func roundRows(dst: [*] s16, src: const [*] s16, rows: u64)
{
    let twos  = cast(#simd [8] s16) Swag.vecsplat(2's16)
    let mask  = cast(#simd [8] s16) [0xFF, 0xFF, 0xFF, 0xFF, 0, 0, 0, 0]
    for row in rows
    {
        let values = (cast(const [*] #simd [8] s16) (src + row * 8))[0]
        (cast([*] #simd [8] s16) (dst + row * 8))[0] = ((values + twos) >> 2) & mask
    }
}

#[Swag.Optimize(true)]
func tableOffsets(dst: [*] u8, src: const [*] u8)
{
    // Two constants of the same shape, read at two different lanes: each one
    // is its own pool entry, and neither may be confused with the other.
    let bytes = (cast(const [*] #simd [16] u8) src)[0]
    let ones  = cast(#simd [16] u8) Swag.vecsplat(1'u8)
    let twos  = cast(#simd [16] u8) Swag.vecsplat(2'u8)
    (cast([*] #simd [16] u8) dst)[0]        = bytes + ones
    (cast([*] #simd [16] u8) (dst + 16))[0] = bytes + twos
}

#[Swag.Optimize(true)]
func widenConstant(dst: [*] s32)
{
    // A constant read with nothing else to keep it company: the whole value
    // of the function comes out of the pool.
    (cast([*] #simd [4] s32) dst)[0] = cast(#simd [4] s32) [11, 22, 33, 44]
}

#test
{
    var src: [4 * 8] s16
    var dst: [4 * 8] s16
    for i in 4 * 8 do
        src[i] = cast(s16) (i * 3)
    roundRows(&dst[0], &src[0], 4)
    Swag.assert(dst[0] == ((0 + 2) >> 2) & 0xFF and dst[3] == ((9 + 2) >> 2) & 0xFF)
    Swag.assert(dst[4] == 0 and dst[7] == 0)
    Swag.assert(dst[8] == ((24 + 2) >> 2) & 0xFF and dst[31] == 0)

    var bytes: [16] u8
    var out:   [32] u8
    for i in 16 do
        bytes[i] = cast(u8) (i * 5)
    tableOffsets(&out[0], &bytes[0])
    Swag.assert(out[0] == 1 and out[15] == 75 + 1)
    Swag.assert(out[16] == 2 and out[31] == 75 + 2)

    var words: [4] s32
    widenConstant(&words[0])
    Swag.assert(words[0] == 11 and words[1] == 22 and words[2] == 33 and words[3] == 44)
}
