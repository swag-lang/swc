#global internal

#test
{
    func div(a: s32, b: s32)->s32 { return a / b }
    const V = #run div(126, 3)
    #assert(#typeof(V) == s32)
    #assert(V == 42)
}

#test
{
    #[Swag.PrintMicro]
    func div(a: u32, b: u32)->u32 { return a / b }
    const V = #run div(126'u32, 3'u32)
    #assert(#typeof(V) == u32)
    #assert(V == 42'u32)
}

#test
{
    func div(a: f64, b: f64)->f64 { return a / b }
    const V = #run div(84.0'f64, 2.0'f64)
    #assert(#typeof(V) == f64)
    #assert(V == 42.0'f64)
}

#test
{
    var a, b: s32
    a = b / 0 // swc-expected-error {{sema_err_division_zero}}
}
