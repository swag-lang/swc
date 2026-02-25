#global internal

#test
{
    func mod(a: s32, b: s32)->s32 { return a % b }
    const V = #run mod(100, 58)
    #assert(#typeof(V) == s32)
    #assert(V == 42)
}

#test
{
    func mod(a: u32, b: u32)->u32 { return a % b }
    const V = #run mod(100'u32, 58'u32)
    #assert(#typeof(V) == u32)
    #assert(V == 42'u32)
}

#test
{
    var a, b: s32
    a = b % 0 // swc-expected-error {{safety_err_division_zero}}
}

#test
{
    func mod(a: u64, b: u64)->u64 { return a % b }
    const V = #run mod(1000'u64, 64'u64)
    #assert(#typeof(V) == u64)
    #assert(V == 40'u64)
}

#test
{
    func modTooFew(a: s32, b: s32)->s32 { return a % b }
    const V = #run modTooFew(100) // swc-expected-error {{sema_err_too_few_arguments}}
}
