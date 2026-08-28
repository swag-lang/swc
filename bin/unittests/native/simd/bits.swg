#global private
using Swag

// The packed bit vocabulary, checked lane by lane against the scalar intrinsic
// it repeats: rotations at every count, population counts, the two zero counts,
// and byte reversal.

const Bytes: [16] u8 = [0, 1, 2, 3, 0x0F, 0x10, 0x55, 0x7F, 0x80, 0xAA, 0xC3, 0xE0, 0xF0, 0xFE, 0xFF, 0x18]
const Words: [8] u16 = [0, 1, 0x00FF, 0x0100, 0x1234, 0x8000, 0xAAAA, 0xFFFF]
const Quads: [4] u32 = [0, 1, 0x1234_5678, 0xFFFF_FFFF]
const Pairs: [2] u64 = [0, 0x0102_0304_0506_0708]

#[Swag.NoInline]
func rolLive(value: #simd [16] u8, count: u8)->#simd [16] u8 => @rol(value, count)

#[Swag.NoInline]
func rorLive(value: #simd [2] u64, count: u8)->#simd [2] u64 => @ror(value, count)

// Rotations answer, lane by lane, what the scalar rotation answers for that
// lane, at every count including the ones past the lane width.
#test
{
    let bytes = cast(#simd [16] u8) Bytes
    let words = cast(#simd [8] u16) Words
    let quads = cast(#simd [4] u32) Quads
    let pairs = cast(#simd [2] u64) Pairs

    for c in 72
    {
        let count = cast(u8) c

        let rolBytes = cast([16] u8) @rol(bytes, count)
        let rorBytes = cast([16] u8) @ror(bytes, count)
        for i in 16
        {
            @assert(rolBytes[i] == @rol(Bytes[i], count))
            @assert(rorBytes[i] == @ror(Bytes[i], count))
        }

        let rolWords = cast([8] u16) @rol(words, count)
        let rorWords = cast([8] u16) @ror(words, count)
        for i in 8
        {
            @assert(rolWords[i] == @rol(Words[i], count))
            @assert(rorWords[i] == @ror(Words[i], count))
        }

        let rolQuads = cast([4] u32) @rol(quads, count)
        let rorQuads = cast([4] u32) @ror(quads, count)
        for i in 4
        {
            @assert(rolQuads[i] == @rol(Quads[i], count))
            @assert(rorQuads[i] == @ror(Quads[i], count))
        }

        let rolPairs = cast([2] u64) @rol(pairs, count)
        let rorPairs = cast([2] u64) @ror(pairs, count)
        for i in 2
        {
            @assert(rolPairs[i] == @rol(Pairs[i], count))
            @assert(rorPairs[i] == @ror(Pairs[i], count))
        }
    }
}

// A count known at compile time takes the immediate lowering; the answers are
// the same, and a zero count is the identity.
#test
{
    let bytes = cast(#simd [16] u8) Bytes
    let quads = cast(#simd [4] u32) Quads

    var r8 = cast([16] u8) @rol(bytes, 3)
    @assert(r8[0] == 0 and r8[1] == 8 and r8[8] == 4 and r8[14] == 0xFF)
    r8 = cast([16] u8) @ror(bytes, 3)
    @assert(r8[1] == 0x20 and r8[8] == 0x10 and r8[14] == 0xFF)
    r8 = cast([16] u8) @rol(bytes, 0)
    for i in 16 do
        @assert(r8[i] == Bytes[i])
    r8 = cast([16] u8) @rol(bytes, 8)
    for i in 16 do
        @assert(r8[i] == Bytes[i])

    var r32 = cast([4] u32) @rol(quads, 8)
    @assert(r32[1] == 0x100 and r32[2] == 0x3456_7812 and r32[3] == 0xFFFF_FFFF)
    r32 = cast([4] u32) @ror(quads, 4)
    @assert(r32[1] == 0x1000_0000 and r32[2] == 0x8123_4567)

    // A live count reaches the register lowering instead.
    var live: u8 = 3
    let liveRol  = cast([16] u8) rolLive(bytes, live)
    for i in 16 do
        @assert(liveRol[i] == @rol(Bytes[i], live))

    live = 40
    let liveRor = cast([2] u64) rorLive(cast(#simd [2] u64) Pairs, live)
    for i in 2 do
        @assert(liveRor[i] == @ror(Pairs[i], live))
}

// The counts repeat the scalar intrinsics per lane, an empty lane answering
// the lane width.
#test
{
    let bytes = cast(#simd [16] u8) Bytes
    let words = cast(#simd [8] u16) Words
    let quads = cast(#simd [4] u32) Quads
    let pairs = cast(#simd [2] u64) Pairs

    let nzBytes = cast([16] u8) @bitcountnz(bytes)
    let tzBytes = cast([16] u8) @bitcounttz(bytes)
    let lzBytes = cast([16] u8) @bitcountlz(bytes)
    for i in 16
    {
        @assert(nzBytes[i] == @bitcountnz(Bytes[i]))
        @assert(tzBytes[i] == @bitcounttz(Bytes[i]))
        @assert(lzBytes[i] == @bitcountlz(Bytes[i]))
    }

    let nzWords = cast([8] u16) @bitcountnz(words)
    let tzWords = cast([8] u16) @bitcounttz(words)
    let lzWords = cast([8] u16) @bitcountlz(words)
    for i in 8
    {
        @assert(nzWords[i] == @bitcountnz(Words[i]))
        @assert(tzWords[i] == @bitcounttz(Words[i]))
        @assert(lzWords[i] == @bitcountlz(Words[i]))
    }

    let nzQuads = cast([4] u32) @bitcountnz(quads)
    let tzQuads = cast([4] u32) @bitcounttz(quads)
    let lzQuads = cast([4] u32) @bitcountlz(quads)
    for i in 4
    {
        @assert(nzQuads[i] == @bitcountnz(Quads[i]))
        @assert(tzQuads[i] == @bitcounttz(Quads[i]))
        @assert(lzQuads[i] == @bitcountlz(Quads[i]))
    }

    let nzPairs = cast([2] u64) @bitcountnz(pairs)
    let tzPairs = cast([2] u64) @bitcounttz(pairs)
    let lzPairs = cast([2] u64) @bitcountlz(pairs)
    for i in 2
    {
        @assert(nzPairs[i] == @bitcountnz(Pairs[i]))
        @assert(tzPairs[i] == @bitcounttz(Pairs[i]))
        @assert(lzPairs[i] == @bitcountlz(Pairs[i]))
    }

    // Every single-bit pattern of a byte lane, plus the empty one.
    var probe: [16] u8
    for bit in 8
    {
        for i in 16 do
            probe[i] = i == 0 ? 0 : cast(u8) (1 << bit)
        let packed = cast(#simd [16] u8) probe
        let tz     = cast([16] u8) @bitcounttz(packed)
        let lz     = cast([16] u8) @bitcountlz(packed)
        @assert(tz[0] == 8 and lz[0] == 8)
        for i in 1 until 16
        {
            @assert(tz[i] == cast(u8) bit)
            @assert(lz[i] == cast(u8) (7 - bit))
        }
    }
}

// Byte reversal inside every lane matches the scalar swap.
#test
{
    let words = cast(#simd [8] u16) Words
    let quads = cast(#simd [4] u32) Quads
    let pairs = cast(#simd [2] u64) Pairs

    let swappedWords = cast([8] u16) @byteswap(words)
    for i in 8 do
        @assert(swappedWords[i] == @byteswap(Words[i]))

    let swappedQuads = cast([4] u32) @byteswap(quads)
    for i in 4 do
        @assert(swappedQuads[i] == @byteswap(Quads[i]))

    let swappedPairs = cast([2] u64) @byteswap(pairs)
    for i in 2 do
        @assert(swappedPairs[i] == @byteswap(Pairs[i]))
}

// A float lane loses its sign bit and nothing else.
#test
{
    let values = cast(#simd [4] f32) [-1.5, 2.5, -0.0, -3.4028234663852886e+38]
    let result = cast([4] f32) @abs(values)
    @assert(result[0] == 1.5 and result[1] == 2.5 and result[2] == 0.0)
    @assert(result[3] == 3.4028234663852886e+38)

    // The negative zero became a positive one, which only its reciprocal shows.
    @assert(1.0 / result[2] > 0)

    let wide  = cast(#simd [2] f64) [-3.25, -0.0]
    let clear = cast([2] f64) @abs(wide)
    @assert(clear[0] == 3.25 and 1.0 / clear[1] > 0)

    // A NaN keeps its payload, so it stays a NaN instead of turning into one
    // of the boundary values.
    let nan     = cast #bit (#simd [4] f32) @vecsplat(0xFFC0_1234'u32)
    let cleared = cast #bit ([4] u32) @abs(nan)
    @assert(cleared[0] == 0x7FC0_1234)
}
