#global private
using Swag

// Both halves of a loaded byte vector widened to words: the low half through
// the widening itself, the high half through the unsigned high widening. The
// loaded bytes must reach the words whether the widening reads a register or
// the memory the vector came from.

#[Swag.Optimize(true)]
func sumRows(dst: [*] u16, src: const [*] u8, stride: u64, rows: u64)
{
    for row in rows
    {
        let bytes = (cast(const [*] #simd [16] u8) (src + row * stride))[0]
        let lo    = Swag.vecwidenlo(bytes)
        let hi    = Swag.vecwidenhi(bytes)
        (cast([*] #simd [8] u16) (dst + row * 8))[0] = lo + hi
    }
}

#[Swag.Optimize(true)]
func widenWords(dst: [*] u32, src: const [*] u16)
{
    let words = (cast(const [*] #simd [8] u16) src)[0]
    (cast([*] #simd [4] u32) dst)[0]       = Swag.vecwidenlo(words)
    (cast([*] #simd [4] u32) (dst + 4))[0] = Swag.vecwidenhi(words)
}

#[Swag.Optimize(true)]
func widenSigned(dst: [*] s16, src: const [*] s8)
{
    let bytes = (cast(const [*] #simd [16] s8) src)[0]
    (cast([*] #simd [8] s16) dst)[0] = Swag.vecwidenlo(bytes)
}

#[Swag.Optimize(true)]
func gatherRows(dst: [*] u16, src: const [*] u8, offsets: const [*] u64, rows: u64)
{
    // Each row sits at an offset read from a table: the vector is loaded
    // through an indexed address.
    for row in rows
    {
        let bytes = (cast(const [*] #simd [16] u8) (src + offsets[row]))[0]
        (cast([*] #simd [8] u16) (dst + row * 8))[0] = Swag.vecwidenlo(bytes) + Swag.vecwidenhi(bytes)
    }
}

#[Swag.Optimize(true)]
func widenAfterStore(dst: [*] u16, buffer: [*] u8)
{
    // The store between the load and the widening overwrites the bytes that
    // were loaded: the widening must see them as they were loaded.
    let bytes = (cast(const [*] #simd [16] u8) buffer)[0]
    buffer[0] = 200
    (cast([*] #simd [8] u16) dst)[0] = Swag.vecwidenlo(bytes)
}

#[Swag.Optimize(true)]
func maskRows(dst: [*] u16, pix: const [*] u8, stride: u64, a, b: u16)
{
    // The two rows are loaded before the mask is built in frame temporaries;
    // the widenings read the rows after those stores. The rows come through
    // an argument, which cannot point into the frame, so the widenings may
    // read the memory the rows were loaded from.
    let p0   = (cast(const [*] #simd [16] u8) (pix - stride))[0]
    let q0   = (cast(const [*] #simd [16] u8) pix)[0]
    let mask = cast(#simd [8] u16) [a, a, a, a, b, b, b, b]
    let lo   = (Swag.vecwidenlo(p0) + Swag.vecwidenlo(q0)) & mask
    let hi   = (Swag.vecwidenhi(p0) + Swag.vecwidenhi(q0)) & mask
    (cast([*] #simd [8] u16) dst)[0]       = lo
    (cast([*] #simd [8] u16) (dst + 8))[0] = hi
}

#[Swag.Optimize(true)]
func widenLocalPastStore(dst: [*] u16, value: u8)
{
    // The vector lives in the frame and a frame store follows its load:
    // the widening must see the bytes as they were loaded.
    var bytes: [16] u8
    for i in 16 do
        bytes[i] = cast(u8) i
    let loaded = (cast(const [*] #simd [16] u8) &bytes[0])[0]
    bytes[0] = value
    (cast([*] #simd [8] u16) dst)[0] = Swag.vecwidenlo(loaded) + Swag.vecwidenhi(loaded) + cast(u16) bytes[0]
}

#test
{
    var plane: [4 * 64] u8
    var out:   [4 * 8] u16
    for i in 4 * 64 do
        plane[i] = cast(u8) (i & 0xFF)
    sumRows(&out[0], &plane[0], 64, 4)
    Swag.assert(out[0] == 0 + 8 and out[7] == 7 + 15)
    Swag.assert(out[8] == 64 + 72 and out[31] == (3 * 64 + 7) + (3 * 64 + 15))

    var words:  [8] u16 = [1, 2, 3, 4, 5, 6, 7, 0xFFFF]
    var dwords: [8] u32
    widenWords(&dwords[0], &words[0])
    Swag.assert(dwords[0] == 1 and dwords[3] == 4 and dwords[4] == 5 and dwords[7] == 0xFFFF)

    var signed: [16] s8 = [-1, -2, 3, 4, 5, 6, 7, -128, 9, 10, 11, 12, 13, 14, 15, 16]
    var wide:   [8] s16
    widenSigned(&wide[0], &signed[0])
    Swag.assert(wide[0] == -1 and wide[1] == -2 and wide[7] == -128)

    var offsets:  [3] u64 = [0, 64, 192]
    var gathered: [3 * 8] u16
    gatherRows(&gathered[0], &plane[0], &offsets[0], 3)
    Swag.assert(gathered[0] == 0 + 8 and gathered[8] == 64 + 72 and gathered[16] == 192 + 200 and gathered[23] == 199 + 207)

    var buffer: [16] u8
    for i in 16 do
        buffer[i] = cast(u8) i
    var seen: [8] u16
    widenAfterStore(&seen[0], &buffer[0])
    Swag.assert(seen[0] == 0 and seen[1] == 1 and buffer[0] == 200)

    var masked: [16] u16
    maskRows(&masked[0], &plane[64], 64, 0xFFFF, 0)
    Swag.assert(masked[0] == 0 + 64 and masked[3] == 3 + 67 and masked[4] == 0 and masked[7] == 0)
    Swag.assert(masked[8] == 8 + 72 and masked[11] == 11 + 75 and masked[12] == 0 and masked[15] == 0)

    var local: [8] u16
    widenLocalPastStore(&local[0], 200)
    Swag.assert(local[0] == 0 + 8 + 200 and local[7] == 7 + 15 + 200)
}
