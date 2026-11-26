#global private

#test
{
    func div(a: s32, b: s32)->s32 { return a / b }
    const V = #run div(126, 3)
    #assert(#typeof(V) == s32)
    #assert(V == 42)
}

#test
{
    func div(a: u32, b: u32)->u32 { return a / b }
    const V = #run div(126_u32, 3_u32)
    #assert(#typeof(V) == u32)
    #assert(V == 42_u32)
}

#test
{
    func div(a: f64, b: f64)->f64 { return a / b }
    const V = #run div(84.0_f64, 2.0_f64)
    #assert(#typeof(V) == f64)
    #assert(V == 42.0_f64)
}

#test
{
    var a, b: s32
    a = b / 0     // swc-expected-error {{safety_err_division_zero}}
}

#test
{
    func div(a: s64, b: s64)->s64 { return a / b }
    const V = #run div(-84_s64, 2_s64)
    #assert(#typeof(V) == s64)
    #assert(V == -42_s64)
}

#test
{
    func divTooFew(a: s32, b: s32)->s32 { return a / b }
    const V = #run divTooFew(126)     // swc-expected-error {{sema_err_too_few_arguments}}
}
