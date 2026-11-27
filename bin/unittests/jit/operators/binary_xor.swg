#global private

#test
{
    func bitXor(a: u32, b: u32)->u32 { return a ^ b }
    const V = #run bitXor(47_u32, 5_u32)
    #assert(#typeof(V) == u32)
    #assert(V == 42_u32)
}

#test
{
    func bitXorChain(a: u32, b: u32, c: u32)->u32 { return a ^ b ^ c }
    const V = #run bitXorChain(58_u32, 24_u32, 8_u32)
    #assert(#typeof(V) == u32)
    #assert(V == 42_u32)
}

#test
{
    func bitXorStrict(a: u32, b: u32)->u32 { return a ^ b }
    const V = #run bitXorStrict(47_u32, 5_u32, 1_u32)     // swc-expected-error {{sema_err_too_many_arguments}}
}

#test
{
    func bitXorSelf(a: u32)->u32 { return a ^ a }
    const V = #run bitXorSelf(0xABCD_1234_u32)
    #assert(#typeof(V) == u32)
    #assert(V == 0_u32)
}

#test
{
    func bitXorTooFew(a: u32, b: u32)->u32 { return a ^ b }
    const V = #run bitXorTooFew(47_u32)     // swc-expected-error {{sema_err_too_few_arguments}}
}
