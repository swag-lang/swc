#global internal

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
