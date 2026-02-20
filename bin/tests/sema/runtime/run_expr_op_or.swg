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
