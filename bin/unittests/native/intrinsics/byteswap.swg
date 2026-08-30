#global private     //

#[Swag.Strict]
alias ByteSwapStrictU32 = u32

#[Swag.NoInline]
func bswapU16(value: u16)->u16 => Swag.byteSwap(value)

#[Swag.NoInline]
func bswapU32(value: u32)->u32 => Swag.byteSwap(value)

#[Swag.NoInline]
func bswapU64(value: u64)->u64 => Swag.byteSwap(value)

#[Swag.NoInline]
func bswapStrictU32(value: ByteSwapStrictU32)->ByteSwapStrictU32 => Swag.byteSwap(value)

// Compile-time
#test
{
    const a: u16 = Swag.byteSwap(0x1234'u16)
    const b: u16 = Swag.byteSwap(0'u16)
    const c: u16 = Swag.byteSwap(0xFFFF'u16)
    #assert(a == 0x3412'u16)
    #assert(b == 0'u16)
    #assert(c == 0xFFFF'u16)

    const d: u32 = Swag.byteSwap(0x12345678'u32)
    const e: u32 = Swag.byteSwap(0'u32)
    const f: u32 = Swag.byteSwap(0xFFFFFFFF'u32)
    const g: u32 = Swag.byteSwap(0x01020304'u32)
    #assert(d == 0x78563412'u32)
    #assert(e == 0'u32)
    #assert(f == 0xFFFFFFFF'u32)
    #assert(g == 0x04030201'u32)

    const h: u64 = Swag.byteSwap(0x01234567_89ABCDEF'u64)
    const i: u64 = Swag.byteSwap(0'u64)
    const j: u64 = Swag.byteSwap(0xFFFFFFFF_FFFFFFFF'u64)
    #assert(h == 0xEFCDAB89_67452301'u64)
    #assert(i == 0'u64)
    #assert(j == 0xFFFFFFFF_FFFFFFFF'u64)
}

// u16
#test
{
    Swag.assert(bswapU16(0x1234'u16) == 0x3412'u16)
    Swag.assert(bswapU16(0'u16) == 0'u16)
    Swag.assert(bswapU16(0xFFFF'u16) == 0xFFFF'u16)
    Swag.assert(bswapU16(0xFF00'u16) == 0x00FF'u16)
    Swag.assert(bswapU16(0x00FF'u16) == 0xFF00'u16)
    Swag.assert(bswapU16(0x0100'u16) == 0x0001'u16)
    Swag.assert(bswapU16(0xABCD'u16) == 0xCDAB'u16)
}

// u32
#test
{
    Swag.assert(bswapU32(0x12345678'u32) == 0x78563412'u32)
    Swag.assert(bswapU32(0'u32) == 0'u32)
    Swag.assert(bswapU32(0xFFFFFFFF'u32) == 0xFFFFFFFF'u32)
    Swag.assert(bswapU32(0xFF000000'u32) == 0x000000FF'u32)
    Swag.assert(bswapU32(0x000000FF'u32) == 0xFF000000'u32)
    Swag.assert(bswapU32(0x00FF0000'u32) == 0x0000FF00'u32)
    Swag.assert(bswapU32(0x0000FF00'u32) == 0x00FF0000'u32)
    Swag.assert(bswapU32(0x01020304'u32) == 0x04030201'u32)
}

// u64
#test
{
    Swag.assert(bswapU64(0x01234567_89ABCDEF'u64) == 0xEFCDAB89_67452301'u64)
    Swag.assert(bswapU64(0'u64) == 0'u64)
    Swag.assert(bswapU64(0xFFFFFFFF_FFFFFFFF'u64) == 0xFFFFFFFF_FFFFFFFF'u64)
    Swag.assert(bswapU64(0xFF000000_00000000'u64) == 0x00000000_000000FF'u64)
    Swag.assert(bswapU64(0x00000000_000000FF'u64) == 0xFF000000_00000000'u64)
    Swag.assert(bswapU64(0x01020304_05060708'u64) == 0x08070605_04030201'u64)
}

// Double swap is identity
#test
{
    Swag.assert(bswapU16(bswapU16(0xBEEF'u16)) == 0xBEEF'u16)
    Swag.assert(bswapU32(bswapU32(0xDEADBEEF'u32)) == 0xDEADBEEF'u32)
    Swag.assert(bswapU64(bswapU64(0xCAFEBABE_DEADBEEF'u64)) == 0xCAFEBABE_DEADBEEF'u64)
}

// Single byte isolation
#test
{
    Swag.assert(bswapU32(0x00000001'u32) == 0x01000000'u32)
    Swag.assert(bswapU32(0x00000100'u32) == 0x00010000'u32)
    Swag.assert(bswapU32(0x00010000'u32) == 0x00000100'u32)
    Swag.assert(bswapU32(0x01000000'u32) == 0x00000001'u32)
}

// Uniform byte patterns are invariant
#test
{
    Swag.assert(bswapU16(0xAAAA'u16) == 0xAAAA'u16)
    Swag.assert(bswapU16(0x1111'u16) == 0x1111'u16)
}

// Strict aliases
#test
{
    const a = Swag.byteSwap(cast(ByteSwapStrictU32) 0x12345678'u32)

    #assert(#typeof(a) == ByteSwapStrictU32)

    Swag.assert(a == cast(ByteSwapStrictU32) 0x78563412'u32)
}

#test
{
    let a = bswapStrictU32(cast(ByteSwapStrictU32) 0x01020304'u32)

    #assert(#typeof(a) == ByteSwapStrictU32)

    Swag.assert(a == cast(ByteSwapStrictU32) 0x04030201'u32)
}
