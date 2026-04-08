#global fileprivate //

#[Swag.NoInline]
func bswapU16(value: u16)->u16 => @byteswap(value)

#[Swag.NoInline]
func bswapU32(value: u32)->u32 => @byteswap(value)

#[Swag.NoInline]
func bswapU64(value: u64)->u64 => @byteswap(value)

// Compile-time
#test
{
    const a: u16 = @byteswap(0x1234'u16)
    const b: u16 = @byteswap(0'u16)
    const c: u16 = @byteswap(0xFFFF'u16)
    #assert(a == 0x3412'u16)
    #assert(b == 0'u16)
    #assert(c == 0xFFFF'u16)

    const d: u32 = @byteswap(0x12345678'u32)
    const e: u32 = @byteswap(0'u32)
    const f: u32 = @byteswap(0xFFFFFFFF'u32)
    const g: u32 = @byteswap(0x01020304'u32)
    #assert(d == 0x78563412'u32)
    #assert(e == 0'u32)
    #assert(f == 0xFFFFFFFF'u32)
    #assert(g == 0x04030201'u32)

    const h: u64 = @byteswap(0x01234567_89ABCDEF'u64)
    const i: u64 = @byteswap(0'u64)
    const j: u64 = @byteswap(0xFFFFFFFF_FFFFFFFF'u64)
    #assert(h == 0xEFCDAB89_67452301'u64)
    #assert(i == 0'u64)
    #assert(j == 0xFFFFFFFF_FFFFFFFF'u64)
}

// u16
#test
{
    @assert(bswapU16(0x1234'u16) == 0x3412'u16)
    @assert(bswapU16(0'u16) == 0'u16)
    @assert(bswapU16(0xFFFF'u16) == 0xFFFF'u16)
    @assert(bswapU16(0xFF00'u16) == 0x00FF'u16)
    @assert(bswapU16(0x00FF'u16) == 0xFF00'u16)
    @assert(bswapU16(0x0100'u16) == 0x0001'u16)
    @assert(bswapU16(0xABCD'u16) == 0xCDAB'u16)
}

// u32
#test
{
    @assert(bswapU32(0x12345678'u32) == 0x78563412'u32)
    @assert(bswapU32(0'u32) == 0'u32)
    @assert(bswapU32(0xFFFFFFFF'u32) == 0xFFFFFFFF'u32)
    @assert(bswapU32(0xFF000000'u32) == 0x000000FF'u32)
    @assert(bswapU32(0x000000FF'u32) == 0xFF000000'u32)
    @assert(bswapU32(0x00FF0000'u32) == 0x0000FF00'u32)
    @assert(bswapU32(0x0000FF00'u32) == 0x00FF0000'u32)
    @assert(bswapU32(0x01020304'u32) == 0x04030201'u32)
}

// u64
#test
{
    @assert(bswapU64(0x01234567_89ABCDEF'u64) == 0xEFCDAB89_67452301'u64)
    @assert(bswapU64(0'u64) == 0'u64)
    @assert(bswapU64(0xFFFFFFFF_FFFFFFFF'u64) == 0xFFFFFFFF_FFFFFFFF'u64)
    @assert(bswapU64(0xFF000000_00000000'u64) == 0x00000000_000000FF'u64)
    @assert(bswapU64(0x00000000_000000FF'u64) == 0xFF000000_00000000'u64)
    @assert(bswapU64(0x01020304_05060708'u64) == 0x08070605_04030201'u64)
}

// Double swap is identity
#test
{
    @assert(bswapU16(bswapU16(0xBEEF'u16)) == 0xBEEF'u16)
    @assert(bswapU32(bswapU32(0xDEADBEEF'u32)) == 0xDEADBEEF'u32)
    @assert(bswapU64(bswapU64(0xCAFEBABE_DEADBEEF'u64)) == 0xCAFEBABE_DEADBEEF'u64)
}

// Single byte isolation
#test
{
    @assert(bswapU32(0x00000001'u32) == 0x01000000'u32)
    @assert(bswapU32(0x00000100'u32) == 0x00010000'u32)
    @assert(bswapU32(0x00010000'u32) == 0x00000100'u32)
    @assert(bswapU32(0x01000000'u32) == 0x00000001'u32)
}

// Uniform byte patterns are invariant
#test
{
    @assert(bswapU16(0xAAAA'u16) == 0xAAAA'u16)
    @assert(bswapU16(0x1111'u16) == 0x1111'u16)
}
