#global internal

#test
{
    func bitOr(a: u32, b: u32)->u32 { return a | b }
    const V = #run bitOr(40'u32, 2'u32)
    #assert(#typeof(V) == u32)
    #assert(V == 42'u32)
}

#test
{
    func bitOrChain(a: u32, b: u32, c: u32)->u32 { return a | b | c }
    const V = #run bitOrChain(32'u32, 8'u32, 2'u32)
    #assert(#typeof(V) == u32)
    #assert(V == 42'u32)
}

#test
{
    func bitOrStrict(a: u32, b: u32)->u32 { return a | b }
    const V = #run bitOrStrict(40'u32, 2'u32, 1'u32) // swc-expected-error {{sema_err_too_many_arguments}}
}

#test
{
    func bitOrU64(a: u64, b: u64)->u64 { return a | b }
    const V = #run bitOrU64(0x1000_0000_0000_0000'u64, 0x0000_00FF_0000_0000'u64)
    #assert(#typeof(V) == u64)
    #assert(V == 0x1000_00FF_0000_0000'u64)
}

#test
{
    func bitOrTooFew(a: u32, b: u32)->u32 { return a | b }
    const V = #run bitOrTooFew(40'u32) // swc-expected-error {{sema_err_too_few_arguments}}
}
