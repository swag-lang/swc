#global internal

#test
{
    func unaryPlusU32(a: u32)->u32 { return +a }
    const V = #run unaryPlusU32(42'u32)
    #assert(#typeof(V) == u32)
    #assert(V == 42'u32)
}

#test
{
    func unaryPlusF64(a: f64)->f64 { return +a }
    const V = #run unaryPlusF64(42.5'f64)
    #assert(#typeof(V) == f64)
    #assert(V == 42.5'f64)
}

#test
{
    func unaryPlusBad(a: s32)->s32 { return +a } // swc-expected-error {{sema_err_negate_unsigned}}
}

#test
{
    func unaryPlusU64(a: u64)->u64 { return +a }
    const V = #run unaryPlusU64(42'u64)
    #assert(#typeof(V) == u64)
    #assert(V == 42'u64)
}

#test
{
    func unaryPlusChain(a: f32)->f32 { return +(+a) }
    const V = #run unaryPlusChain(42.5'f32)
    #assert(#typeof(V) == f32)
    #assert(V == 42.5'f32)
}
