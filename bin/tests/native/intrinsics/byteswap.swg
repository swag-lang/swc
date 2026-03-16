#global fileprivate // swc-option suite-test

#[Swag.NoInline]
func bswapU16(value: u16)->u16 => @byteswap(value)

#[Swag.NoInline]
func bswapU32(value: u32)->u32 => @byteswap(value)

#[Swag.NoInline]
func bswapU64(value: u64)->u64 => @byteswap(value)

#test
{
    @assert(bswapU16(0x1234'u16) == 0x3412'u16)
    @assert(bswapU32(0x12345678'u32) == 0x78563412'u32)
    @assert(bswapU64(0x01234567_89ABCDEF'u64) == 0xEFCDAB89_67452301'u64)
}

#test
{
    @assert(bswapU16(0'u16) == 0'u16)
    @assert(bswapU32(0xFF000000'u32) == 0x000000FF'u32)
}
