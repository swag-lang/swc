#global fileprivate // swc-option suite-jit

#test
{
    func unaryTildeU32(a: u32)->u32 { return ~a }
    const V = #run unaryTildeU32(0xFFFF_FFD5'u32)
    #assert(#typeof(V) == u32)
    #assert(V == 42'u32)
}

#test
{
    func unaryTildeChain(a: u32)->u32 { return ~(~a) }
    const V = #run unaryTildeChain(42'u32)
    #assert(#typeof(V) == u32)
    #assert(V == 42'u32)
}

#test
{
    func unaryTildeBad(a: f32)->f32 { return ~a } // swc-expected-error {{sema_err_unary_operand_type}}
}

#test
{
    func unaryTildeU64(a: u64)->u64 { return ~a }
    const V = #run unaryTildeU64(0xFFFF_FFFF_FFFF_FFD5'u64)
    #assert(#typeof(V) == u64)
    #assert(V == 42'u64)
}

#test
{
    func unaryTildeMask(a: u32)->u32 { return ~a & 0xFF'u32 }
    const V = #run unaryTildeMask(0xD5'u32)
    #assert(#typeof(V) == u32)
    #assert(V == 42'u32)
}
