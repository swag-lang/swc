#global fileprivate // 

func bitXor(a: u32, b: u32)->u32
{
    return a ^ b
}

func bitXorChain(a: u32, b: u32, c: u32)->u32
{
    return a ^ b ^ c
}

func bitXorSelf(a: u32)->u32
{
    return a ^ a
}

func bitXorWide(a: u64, b: u64)->u64
{
    return a ^ b
}

#test
{
    let v0 = bitXor(47'u32, 5'u32)
    let v1 = bitXorChain(58'u32, 24'u32, 8'u32)
    let v2 = bitXorSelf(0xABCD_1234'u32)
    let v3 = bitXorWide(0xFF00_FF00_FF00_FF00'u64, 0x00FF_00FF_00FF_00FF'u64)

    #assert(#typeof(v0) == u32)
    #assert(#typeof(v3) == u64)

    @assert(v0 == 42'u32)
    @assert(v1 == 42'u32)
    @assert(v2 == 0'u32)
    @assert(v3 == 0xFFFF_FFFF_FFFF_FFFF'u64)
}
