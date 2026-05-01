#global fileprivate // 

#[Swag.Strict]
alias UnaryTildeStrictU32 = u32

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

func unaryTildeStrictU32(a: UnaryTildeStrictU32)->UnaryTildeStrictU32
{
    return ~a
}

func unaryTildeRune(a: rune)->rune
{
    return ~a
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

#test
{
    let runtimeValue = unaryTildeStrictU32(cast(UnaryTildeStrictU32) 0xFFFF_FFD5'u32)
    const constantValue = ~cast(UnaryTildeStrictU32) 0xFFFF_FFD5'u32

    #assert(#typeof(runtimeValue) == UnaryTildeStrictU32)
    #assert(#typeof(constantValue) == UnaryTildeStrictU32)

    @assert(runtimeValue == cast(UnaryTildeStrictU32) 42'u32)
    @assert(constantValue == cast(UnaryTildeStrictU32) 42'u32)
}

#test
{
    let runtimeValue = unaryTildeRune(cast(rune) 0xFFFF_FFD5'u32)
    const constantValue = ~cast(rune) 0xFFFF_FFD5'u32

    #assert(#typeof(runtimeValue) == rune)
    #assert(#typeof(constantValue) == rune)

    @assert(runtimeValue == cast(rune) 42'u32)
    @assert(constantValue == cast(rune) 42'u32)
}
