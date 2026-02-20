#global internal

#test
{
    func sub(a: s32, b: s32)->s32 { return a - b }
    const V = #run sub(52, 10)
    #assert(#typeof(V) == s32)
    #assert(V == 42)
}

#test
{
    func sub(a: f64, b: f64)->f64 { return a - b }
    const V = #run sub(50.5'f64, 8.5'f64)
    #assert(#typeof(V) == f64)
    #assert(V == 42.0'f64)
}

#test
{
    #[Swag.Optimize(.O0)]
    func subChainFloat(a: f64, b: f64, c: f64)->f64 { return a - b - c }
    const V = #run subChainFloat(50.0'f64, 4.0'f64, 4.0'f64)
    #assert(#typeof(V) == f64)
    #assert(V == 42.0'f64)
}

#test
{
    func subStrict(a: s32, b: s32)->s32 { return a - b }
    const V = #run subStrict(50, 8, 1) // swc-expected-error {{sema_err_too_many_arguments}}
}
