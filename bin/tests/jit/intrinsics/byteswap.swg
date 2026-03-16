#global fileprivate // swc-option suite-jit

#test
{
    #[Swag.NoInline]
    func bswapU16(v: u16)->u16 => @byteswap(v)
    #[Swag.NoInline]
    func bswapU32(v: u32)->u32 => @byteswap(v)
    #[Swag.NoInline]
    func bswapU64(v: u64)->u64 => @byteswap(v)

    const A = #run bswapU16(0x1234'u16)
    const B = #run bswapU32(0x12345678'u32)
    const C = #run bswapU64(0x01234567_89ABCDEF'u64)

    #assert(A == 0x3412)
    #assert(B == 0x78563412)
    #assert(C == 0xEFCDAB89_67452301)
}
