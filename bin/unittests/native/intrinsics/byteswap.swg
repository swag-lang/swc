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
    const a: u16 = Swag.byteSwap(0x1234_u16)
    const b: u16 = Swag.byteSwap(0_u16)
    const c: u16 = Swag.byteSwap(0xFFFF_u16)
    #assert(a == 0x3412_u16)
    #assert(b == 0_u16)
    #assert(c == 0xFFFF_u16)

    const d: u32 = Swag.byteSwap(0x12345678_u32)
    const e: u32 = Swag.byteSwap(0_u32)
    const f: u32 = Swag.byteSwap(0xFFFFFFFF_u32)
    const g: u32 = Swag.byteSwap(0x01020304_u32)
    #assert(d == 0x78563412_u32)
    #assert(e == 0_u32)
    #assert(f == 0xFFFFFFFF_u32)
    #assert(g == 0x04030201_u32)

    const h: u64 = Swag.byteSwap(0x01234567_89ABCDEF_u64)
    const i: u64 = Swag.byteSwap(0_u64)
    const j: u64 = Swag.byteSwap(0xFFFFFFFF_FFFFFFFF_u64)
    #assert(h == 0xEFCDAB89_67452301_u64)
    #assert(i == 0_u64)
    #assert(j == 0xFFFFFFFF_FFFFFFFF_u64)
}

// u16
#test
{
    Swag.require(bswapU16(0x1234_u16) == 0x3412_u16)
    Swag.require(bswapU16(0_u16) == 0_u16)
    Swag.require(bswapU16(0xFFFF_u16) == 0xFFFF_u16)
    Swag.require(bswapU16(0xFF00_u16) == 0x00FF_u16)
    Swag.require(bswapU16(0x00FF_u16) == 0xFF00_u16)
    Swag.require(bswapU16(0x0100_u16) == 0x0001_u16)
    Swag.require(bswapU16(0xABCD_u16) == 0xCDAB_u16)
}

// u32
#test
{
    Swag.require(bswapU32(0x12345678_u32) == 0x78563412_u32)
    Swag.require(bswapU32(0_u32) == 0_u32)
    Swag.require(bswapU32(0xFFFFFFFF_u32) == 0xFFFFFFFF_u32)
    Swag.require(bswapU32(0xFF000000_u32) == 0x000000FF_u32)
    Swag.require(bswapU32(0x000000FF_u32) == 0xFF000000_u32)
    Swag.require(bswapU32(0x00FF0000_u32) == 0x0000FF00_u32)
    Swag.require(bswapU32(0x0000FF00_u32) == 0x00FF0000_u32)
    Swag.require(bswapU32(0x01020304_u32) == 0x04030201_u32)
}

// u64
#test
{
    Swag.require(bswapU64(0x01234567_89ABCDEF_u64) == 0xEFCDAB89_67452301_u64)
    Swag.require(bswapU64(0_u64) == 0_u64)
    Swag.require(bswapU64(0xFFFFFFFF_FFFFFFFF_u64) == 0xFFFFFFFF_FFFFFFFF_u64)
    Swag.require(bswapU64(0xFF000000_00000000_u64) == 0x00000000_000000FF_u64)
    Swag.require(bswapU64(0x00000000_000000FF_u64) == 0xFF000000_00000000_u64)
    Swag.require(bswapU64(0x01020304_05060708_u64) == 0x08070605_04030201_u64)
}

// Double swap is identity
#test
{
    Swag.require(bswapU16(bswapU16(0xBEEF_u16)) == 0xBEEF_u16)
    Swag.require(bswapU32(bswapU32(0xDEADBEEF_u32)) == 0xDEADBEEF_u32)
    Swag.require(bswapU64(bswapU64(0xCAFEBABE_DEADBEEF_u64)) == 0xCAFEBABE_DEADBEEF_u64)
}

// Single byte isolation
#test
{
    Swag.require(bswapU32(0x00000001_u32) == 0x01000000_u32)
    Swag.require(bswapU32(0x00000100_u32) == 0x00010000_u32)
    Swag.require(bswapU32(0x00010000_u32) == 0x00000100_u32)
    Swag.require(bswapU32(0x01000000_u32) == 0x00000001_u32)
}

// Uniform byte patterns are invariant
#test
{
    Swag.require(bswapU16(0xAAAA_u16) == 0xAAAA_u16)
    Swag.require(bswapU16(0x1111_u16) == 0x1111_u16)
}

// Strict aliases
#test
{
    const a = Swag.byteSwap(cast(ByteSwapStrictU32, 0x12345678_u32))

    #assert(#typeof(a) == ByteSwapStrictU32)

    Swag.require(a == cast(ByteSwapStrictU32, 0x78563412_u32))
}

#test
{
    let a = bswapStrictU32(cast(ByteSwapStrictU32, 0x01020304_u32))

    #assert(#typeof(a) == ByteSwapStrictU32)

    Swag.require(a == cast(ByteSwapStrictU32, 0x04030201_u32))
}
