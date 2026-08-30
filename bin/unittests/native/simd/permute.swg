#global private
using Swag

// Lane permutation, two-source permutation and byte alignment, each checked
// with the pattern known at compile time and with the same pattern built at run
// time, since the two take different lowerings.

#[Swag.NoInline]
func liveShuffleBytes(value, pattern: #simd [16] u8)->#simd [16] u8 => Swag.vecshuffle(value, pattern)

#[Swag.NoInline]
func liveShuffleWords(value, pattern: #simd [8] u16)->#simd [8] u16 => Swag.vecshuffle(value, pattern)

#[Swag.NoInline]
func liveShuffleQuads(value, pattern: #simd [4] u32)->#simd [4] u32 => Swag.vecshuffle(value, pattern)

#[Swag.NoInline]
func liveShufflePairs(value, pattern: #simd [2] u64)->#simd [2] u64 => Swag.vecshuffle(value, pattern)

#[Swag.NoInline]
func liveShuffle2Quads(x, y, pattern: #simd [4] u32)->#simd [4] u32 => Swag.vecshuffle2(x, y, pattern)

#[Swag.NoInline]
func liveShuffle2Bytes(x, y, pattern: #simd [16] u8)->#simd [16] u8 => Swag.vecshuffle2(x, y, pattern)

#[Swag.NoInline]
func liveAlign(low, high: #simd [16] u8, count: u8)->#simd [16] u8 => Swag.vecalign(low, high, count)

#test
{
    var source:  [16] u8
    var reverse: [16] u8
    for i in 16
    {
        source[i]  = cast(u8) (i * 3 + 1)
        reverse[i] = cast(u8) (15 - i)
    }

    let bytes   = cast(#simd [16] u8) source
    let pattern = cast(#simd [16] u8) reverse

    var r = cast([16] u8) Swag.vecshuffle(bytes, cast(#simd [16] u8) [15, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 0])
    for i in 16 do
        Swag.assert(r[i] == source[15 - i])

    r = cast([16] u8) liveShuffleBytes(bytes, pattern)
    for i in 16 do
        Swag.assert(r[i] == source[15 - i])

    // Every index reduces modulo the lane count, so no pattern is out of range.
    var wide: [16] u8
    for i in 16 do
        wide[i] = cast(u8) (i + 16)
    r = cast([16] u8) liveShuffleBytes(bytes, cast(#simd [16] u8) wide)
    for i in 16 do
        Swag.assert(r[i] == source[i])
}

#test
{
    let words     = cast(#simd [8] u16) [10, 20, 30, 40, 50, 60, 70, 80]
    let wordsBack = cast(#simd [8] u16) [7, 6, 5, 4, 3, 2, 1, 0]

    var w = cast([8] u16) Swag.vecshuffle(words, cast(#simd [8] u16) [7, 6, 5, 4, 3, 2, 1, 0])
    Swag.assert(w[0] == 80 and w[7] == 10)
    w = cast([8] u16) liveShuffleWords(words, wordsBack)
    Swag.assert(w[0] == 80 and w[7] == 10)

    // A duplication is as legal as a permutation.
    w = cast([8] u16) Swag.vecshuffle(words, cast(#simd [8] u16) [0, 0, 0, 0, 7, 7, 7, 7])
    Swag.assert(w[0] == 10 and w[3] == 10 and w[4] == 80 and w[7] == 80)

    let quads     = cast(#simd [4] u32) [10, 20, 30, 40]
    let quadsBack = cast(#simd [4] u32) [3, 2, 1, 0]
    var q         = cast([4] u32) Swag.vecshuffle(quads, cast(#simd [4] u32) [3, 2, 1, 0])
    Swag.assert(q[0] == 40 and q[3] == 10)
    q = cast([4] u32) liveShuffleQuads(quads, quadsBack)
    Swag.assert(q[0] == 40 and q[3] == 10)

    let pairs     = cast(#simd [2] u64) [111, 222]
    let pairsBack = cast(#simd [2] u64) [1, 0]
    var p         = cast([2] u64) Swag.vecshuffle(pairs, cast(#simd [2] u64) [1, 0])
    Swag.assert(p[0] == 222 and p[1] == 111)
    p = cast([2] u64) liveShufflePairs(pairs, pairsBack)
    Swag.assert(p[0] == 222 and p[1] == 111)

    let floats = cast(#simd [4] f32) [1.5, 2.5, 3.5, 4.5]
    let f      = cast([4] f32) Swag.vecshuffle(floats, cast(#simd [4] u32) [2, 3, 0, 1])
    Swag.assert(f[0] == 3.5 and f[1] == 4.5 and f[2] == 1.5 and f[3] == 2.5)

    let signed = cast(#simd [8] s16) [-1, -2, -3, -4, -5, -6, -7, -8]
    let sr     = cast([8] s16) Swag.vecshuffle(signed, cast(#simd [8] u16) [7, 6, 5, 4, 3, 2, 1, 0])
    Swag.assert(sr[0] == -8 and sr[7] == -1)
}

#test
{
    let x = cast(#simd [4] u32) [10, 20, 30, 40]
    let y = cast(#simd [4] u32) [50, 60, 70, 80]

    // The low half from one vector and the high half from the other is one
    // 'shufps'; the interleaved patterns take two byte tables.
    var r = cast([4] u32) Swag.vecshuffle2(x, y, cast(#simd [4] u32) [0, 2, 5, 7])
    Swag.assert(r[0] == 10 and r[1] == 30 and r[2] == 60 and r[3] == 80)

    r = cast([4] u32) Swag.vecshuffle2(x, y, cast(#simd [4] u32) [4, 0, 6, 2])
    Swag.assert(r[0] == 50 and r[1] == 10 and r[2] == 70 and r[3] == 30)

    // A pattern that stays inside one vector never reads the other.
    r = cast([4] u32) Swag.vecshuffle2(x, y, cast(#simd [4] u32) [3, 2, 1, 0])
    Swag.assert(r[0] == 40 and r[3] == 10)
    r = cast([4] u32) Swag.vecshuffle2(x, y, cast(#simd [4] u32) [7, 6, 5, 4])
    Swag.assert(r[0] == 80 and r[3] == 50)

    let interleaved = cast(#simd [4] u32) [4, 0, 6, 2]
    r = cast([4] u32) liveShuffle2Quads(x, y, interleaved)
    Swag.assert(r[0] == 50 and r[1] == 10 and r[2] == 70 and r[3] == 30)

    var lowBytes:   [16] u8
    var highBytes:  [16] u8
    var zipPattern: [16] u8
    for i in 16
    {
        lowBytes[i]   = cast(u8) i
        highBytes[i]  = cast(u8) (100 + i)
        zipPattern[i] = i % 2 == 0 ? cast(u8) (i / 2) : cast(u8) (16 + i / 2)
    }

    let bx = cast(#simd [16] u8) lowBytes
    let by = cast(#simd [16] u8) highBytes
    var br = cast([16] u8) Swag.vecshuffle2(bx, by, cast(#simd [16] u8) [0, 16, 1, 17, 2, 18, 3, 19, 4, 20, 5, 21, 6, 22, 7, 23])
    for i in 16
    {
        if i % 2 == 0 do
            Swag.assert(br[i] == cast(u8) (i / 2))
        else do
            Swag.assert(br[i] == cast(u8) (100 + i / 2))
    }

    br = cast([16] u8) liveShuffle2Bytes(bx, by, cast(#simd [16] u8) zipPattern)
    for i in 16
    {
        if i % 2 == 0 do
            Swag.assert(br[i] == cast(u8) (i / 2))
        else do
            Swag.assert(br[i] == cast(u8) (100 + i / 2))
    }
}

#test
{
    var low:  [16] u8
    var high: [16] u8
    for i in 16
    {
        low[i]  = cast(u8) i
        high[i] = cast(u8) (i + 16)
    }

    let lowVec  = cast(#simd [16] u8) low
    let highVec = cast(#simd [16] u8) high

    var r = cast([16] u8) Swag.vecalign(lowVec, highVec, 0)
    for i in 16 do
        Swag.assert(r[i] == cast(u8) i)

    r = cast([16] u8) Swag.vecalign(lowVec, highVec, 7)
    for i in 16 do
        Swag.assert(r[i] == cast(u8) (i + 7))

    r = cast([16] u8) Swag.vecalign(lowVec, highVec, 16)
    for i in 16 do
        Swag.assert(r[i] == cast(u8) (i + 16))

    // The window runs out of bytes past the concatenation.
    r = cast([16] u8) Swag.vecalign(lowVec, highVec, 31)
    Swag.assert(r[0] == 31)
    for i in 1 until 16 do
        Swag.assert(r[i] == 0)

    r = cast([16] u8) Swag.vecalign(lowVec, highVec, 32)
    for i in 16 do
        Swag.assert(r[i] == 0)

    // A count only known at run time answers the same, through the two-source
    // byte select instead of the immediate form.
    for c in 34
    {
        let count = cast(u8) c
        let live  = cast([16] u8) liveAlign(lowVec, highVec, count)
        for i in 16
        {
            let position = c + i
            Swag.assert(live[i] == (position < 32 ? cast(u8) position : 0'u8))
        }
    }
}
