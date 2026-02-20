#global internal

#test
{
    func bitXor(a: u32, b: u32)->u32 { return a ^ b }
    const V = #run bitXor(47'u32, 5'u32)
    #assert(#typeof(V) == u32)
    #assert(V == 42'u32)
}

#test
{
    func bitXorChain(a: u32, b: u32, c: u32)->u32 { return a ^ b ^ c }
    const V = #run bitXorChain(58'u32, 24'u32, 8'u32)
    #assert(#typeof(V) == u32)
    #assert(V == 42'u32)
}

#test
{
    func bitXorStrict(a: u32, b: u32)->u32 { return a ^ b }
    const V = #run bitXorStrict(47'u32, 5'u32, 1'u32) // swc-expected-error {{sema_err_too_many_arguments}}
}
