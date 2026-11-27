#global private

#test
{
    func unaryPlusU32(a: u32)->u32 { return +a }
    const V = #run unaryPlusU32(42_u32)
    #assert(#typeof(V) == u32)
    #assert(V == 42_u32)
}

#test
{
    func unaryPlusF64(a: f64)->f64 { return +a }
    const V = #run unaryPlusF64(42.5_f64)
    #assert(#typeof(V) == f64)
    #assert(V == 42.5_f64)
}

#test
{
    func unaryPlusS32(a: s32)->s32 { return +a }
    const V = #run unaryPlusS32(-42)
    #assert(#typeof(V) == s32)
    #assert(V == -42)
}

#test
{
    func unaryPlusU64(a: u64)->u64 { return +a }
    const V = #run unaryPlusU64(42_u64)
    #assert(#typeof(V) == u64)
    #assert(V == 42_u64)
}

#test
{
    func unaryPlusChain(a: f32)->f32 { return +(+a) }
    const V = #run unaryPlusChain(42.5_f32)
    #assert(#typeof(V) == f32)
    #assert(V == 42.5_f32)
}
