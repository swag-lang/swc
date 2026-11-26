#global private

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
    const V = #run sub(50.5_f64, 8.5_f64)
    #assert(#typeof(V) == f64)
    #assert(V == 42.0_f64)
}

#test
{
    #[Swag.Optimize(false)]
    func subChainFloat(a: f64, b: f64, c: f64)->f64 { return a - b - c }
    const V = #run subChainFloat(50.0_f64, 4.0_f64, 4.0_f64)
    #assert(#typeof(V) == f64)
    #assert(V == 42.0_f64)
}

#test
{
    func subStrict(a: s32, b: s32)->s32 { return a - b }
    const V = #run subStrict(50, 8, 1)     // swc-expected-error {{sema_err_too_many_arguments}}
}

#test
{
    var value: s32
    Swag.init(value)(1, 2)     // swc-expected-error {{sema_err_too_many_arguments}}
}

struct ArgumentCountPair
{
    first, second: s32
}

#test
{
    var value: ArgumentCountPair
    Swag.init(value)(1, 2, 3)     // swc-expected-error {{sema_err_too_many_arguments}}
}
