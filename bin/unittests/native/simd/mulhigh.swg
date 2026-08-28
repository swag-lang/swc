#global private
using Swag

// The high half of a lane product, at every lane width and both signednesses,
// checked against the scalar product computed in the next width up. The 64-bit
// lanes have no wider scalar type, so they check known products instead.

#[Swag.NoInline]
func liveMulHighS8(x, y: #simd [16] s8)->#simd [16] s8 => @vecmulhi(x, y)

#[Swag.NoInline]
func liveMulHighU16(x, y: #simd [8] u16)->#simd [8] u16 => @vecmulhi(x, y)

#[Swag.NoInline]
func liveMulHighS32(x, y: #simd [4] s32)->#simd [4] s32 => @vecmulhi(x, y)

#[Swag.NoInline]
func liveMulHighU64(x, y: #simd [2] u64)->#simd [2] u64 => @vecmulhi(x, y)

#[Swag.NoInline]
func liveMulHighS64(x, y: #simd [2] s64)->#simd [2] s64 => @vecmulhi(x, y)

#test
{
    var left:  [16] u8
    var right: [16] u8
    for i in 16
    {
        left[i]  = cast(u8) (i * 16 + 3)
        right[i] = cast(u8) (255 - i * 13)
    }

    let r = cast([16] u8) @vecmulhi(cast(#simd [16] u8) left, cast(#simd [16] u8) right)
    for i in 16
    {
        let expected = (cast(u16) left[i] * cast(u16) right[i]) >> 8
        @assert(r[i] == cast(u8) expected)
    }
}

#test
{
    var left:  [16] s8
    var right: [16] s8
    for i in 16
    {
        left[i]  = cast(s8) (cast(s32) i * 15 - 112)
        right[i] = cast(s8) (100 - cast(s32) i * 15)
    }

    let x = cast(#simd [16] s8) left
    let y = cast(#simd [16] s8) right

    var r = cast([16] s8) @vecmulhi(x, y)
    for i in 16
    {
        let expected = (cast(s16) left[i] * cast(s16) right[i]) >> 8
        @assert(r[i] == cast(s8) expected)
    }

    r = cast([16] s8) liveMulHighS8(x, y)
    for i in 16
    {
        let expected = (cast(s16) left[i] * cast(s16) right[i]) >> 8
        @assert(r[i] == cast(s8) expected)
    }
}

#test
{
    var left:  [8] u16
    var right: [8] u16
    for i in 8
    {
        left[i]  = cast(u16) (i * 8191 + 5)
        right[i] = cast(u16) (65535 - i * 4099)
    }

    let x = cast(#simd [8] u16) left
    let y = cast(#simd [8] u16) right

    var r = cast([8] u16) @vecmulhi(x, y)
    for i in 8
    {
        let expected = (cast(u32) left[i] * cast(u32) right[i]) >> 16
        @assert(r[i] == cast(u16) expected)
    }

    r = cast([8] u16) liveMulHighU16(x, y)
    for i in 8 do
        @assert(r[i] == cast(u16) ((cast(u32) left[i] * cast(u32) right[i]) >> 16))
}

#test
{
    var left:  [8] s16
    var right: [8] s16
    for i in 8
    {
        left[i]  = cast(s16) (cast(s32) i * 8191 - 32768)
        right[i] = cast(s16) (32767 - cast(s32) i * 7919)
    }

    let r = cast([8] s16) @vecmulhi(cast(#simd [8] s16) left, cast(#simd [8] s16) right)
    for i in 8
    {
        let expected = (cast(s32) left[i] * cast(s32) right[i]) >> 16
        @assert(r[i] == cast(s16) expected)
    }
}

#test
{
    var left:  [4] u32
    var right: [4] u32
    for i in 4
    {
        left[i]  = cast(u32) (i * 1_073_741_827 + 11)
        right[i] = cast(u32) (4_294_967_295 - i * 999_999_937)
    }

    let r = cast([4] u32) @vecmulhi(cast(#simd [4] u32) left, cast(#simd [4] u32) right)
    for i in 4
    {
        let expected = (cast(u64) left[i] * cast(u64) right[i]) >> 32
        @assert(r[i] == cast(u32) expected)
    }
}

#test
{
    var left:  [4] s32
    var right: [4] s32
    for i in 4
    {
        left[i]  = cast(s32) (cast(s64) i * 536_870_913 - 2_147_483_648)
        right[i] = cast(s32) (2_147_483_647 - cast(s64) i * 999_999_937)
    }

    let x = cast(#simd [4] s32) left
    let y = cast(#simd [4] s32) right

    var r = cast([4] s32) @vecmulhi(x, y)
    for i in 4
    {
        let expected = (cast(s64) left[i] * cast(s64) right[i]) >> 32
        @assert(r[i] == cast(s32) expected)
    }

    r = cast([4] s32) liveMulHighS32(x, y)
    for i in 4 do
        @assert(r[i] == cast(s32) ((cast(s64) left[i] * cast(s64) right[i]) >> 32))
}

#test
{
    // 2^64 - 1 squared has 2^64 - 2 above the low half, and a product that
    // fits in 64 bits has nothing there at all.
    let ones = cast(#simd [2] u64) [0xFFFF_FFFF_FFFF_FFFF, 0xFFFF_FFFF_FFFF_FFFF]
    var r    = cast([2] u64) @vecmulhi(ones, ones)
    @assert(r[0] == 0xFFFF_FFFF_FFFF_FFFE and r[1] == r[0])

    let small = cast(#simd [2] u64) [0xFFFF_FFFF, 3]
    r = cast([2] u64) @vecmulhi(small, small)
    @assert(r[0] == 0 and r[1] == 0)

    // Each half of the operands contributes, so a value straddling bit 32
    // exercises the middle column and its carry.
    let straddle = cast(#simd [2] u64) [0x1_0000_0001, 0xFFFF_FFFF_0000_0001]
    let other    = cast(#simd [2] u64) [0xFFFF_FFFF_FFFF_FFFF, 0x8000_0000_0000_0003]
    r = cast([2] u64) @vecmulhi(straddle, other)
    @assert(r[0] == 0x1_0000_0000)
    @assert(r[1] == 0x7FFF_FFFF_8000_0003)

    r = cast([2] u64) liveMulHighU64(straddle, other)
    @assert(r[0] == 0x1_0000_0000 and r[1] == 0x7FFF_FFFF_8000_0003)
}

#test
{
    // A negative operand answers the signed high half, which the unsigned one
    // overstates by the other operand.
    let minusOne = cast(#simd [2] s64) [-1, -1]
    var r        = cast([2] s64) @vecmulhi(minusOne, minusOne)
    @assert(r[0] == 0 and r[1] == 0)

    let big  = cast(#simd [2] s64) [0x4000_0000_0000_0000, -0x4000_0000_0000_0000]
    let four = cast(#simd [2] s64) [4, 4]
    r = cast([2] s64) @vecmulhi(big, four)
    @assert(r[0] == 1 and r[1] == -1)

    let mixed = cast(#simd [2] s64) [-0x1_0000_0001, 0x1_0000_0001]
    let scale = cast(#simd [2] s64) [0x1_0000_0000, -0x1_0000_0000]
    r = cast([2] s64) @vecmulhi(mixed, scale)
    @assert(r[0] == -2 and r[1] == -2)

    r = cast([2] s64) liveMulHighS64(mixed, scale)
    @assert(r[0] == -2 and r[1] == -2)
}
