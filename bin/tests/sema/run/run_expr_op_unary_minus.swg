#global internal

#test
{
    func unaryMinusS32(a: s32)->s32 { return -a }
    const V = #run unaryMinusS32(42)
    #assert(#typeof(V) == s32)
    #assert(V == -42)
}

#test
{
    func unaryMinusF64(a: f64)->f64 { return -a }
    const V = #run unaryMinusF64(42.5'f64)
    #assert(#typeof(V) == f64)
    #assert(V == -42.5'f64)
}

#test
{
    func unaryMinusBad(a: u32)->u32 { return -a } // swc-expected-error {{sema_err_negate_unsigned}}
}
