#global fileprivate // 

func unaryTildeU32(a: u32)->u32
{
    return ~a
}

func unaryTildeChain(a: u32)->u32
{
    return ~(~a)
}

func unaryTildeU64(a: u64)->u64
{
    return ~a
}

func unaryTildeMask(a: u32)->u32
{
    return ~a & 0xFF'u32
}

#test
{
    let v0 = unaryTildeU32(0xFFFF_FFD5'u32)
    let v1 = unaryTildeChain(42'u32)
    let v2 = unaryTildeU64(0xFFFF_FFFF_FFFF_FFD5'u64)
    let v3 = unaryTildeMask(0xD5'u32)

    #assert(#typeof(v0) == u32)
    #assert(#typeof(v2) == u64)

    @assert(v0 == 42'u32)
    @assert(v1 == 42'u32)
    @assert(v2 == 42'u64)
    @assert(v3 == 42'u32)
}
