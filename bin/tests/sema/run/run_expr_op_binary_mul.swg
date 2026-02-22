#global internal

#test
{
    func mul(a: s32, b: s32)->s32 { return a * b }
    const V = #run mul(6, 7)
    #assert(#typeof(V) == s32)
    #assert(V == 42)
}

#test
{
    func mul(a: f32, b: f32)->f32 { return a * b }
    const V = #run mul(6.0'f32, 7.0'f32)
    #assert(#typeof(V) == f32)
    #assert(V == 42.0'f32)
}

#test
{
    #[Swag.Optimize(.O2)]
    func mulChain(a: s64, b: s64, c: s64)->s64 { return a * b * c }
    const V = #run mulChain(3's64, 2's64, 7's64)
    #assert(#typeof(V) == s64)
    #assert(V == 42's64)
}

#test
{
    func mulStrict(a: s32, b: s32)->s32 { return a * b }
    const V = #run mulStrict(6, 7, 1) // swc-expected-error {{sema_err_too_many_arguments}}
}

#test
{
    func mul(a: u64, b: u64)->u64 { return a * b }
    const V = #run mul(6'u64, 7'u64)
    #assert(#typeof(V) == u64)
    #assert(V == 42'u64)
}

#test
{
    func mulTooFew(a: s32, b: s32)->s32 { return a * b }
    const V = #run mulTooFew(6) // swc-expected-error {{sema_err_too_few_arguments}}
}
