#global internal

#test
{
    func bitAnd(a: u32, b: u32)->u32 { return a & b }
    const V = #run bitAnd(0b00101010'u32, 0b10101010'u32)
    #assert(#typeof(V) == u32)
    #assert(V == 42'u32)
}

#test
{
    func bitAndChain(a: u32, b: u32, c: u32)->u32 { return a & b & c }
    const V = #run bitAndChain(0x3E'u32, 0x2F'u32, 0x2A'u32)
    #assert(#typeof(V) == u32)
    #assert(V == 42'u32)
}

#test
{
    func bitAndStrict(a: u32, b: u32)->u32 { return a & b }
    const V = #run bitAndStrict(42'u32, 255'u32, 1'u32) // swc-expected-error {{sema_err_too_many_arguments}}
}

#test
{
    func bitAndU64(a: u64, b: u64)->u64 { return a & b }
    const V = #run bitAndU64(0xFF00_FF00_FF00_FF00'u64, 0x0F0F_0F0F_FFFF_0000'u64)
    #assert(#typeof(V) == u64)
    #assert(V == 0x0F00_0F00_FF00_0000'u64)
}

#test
{
    func bitAndTooFew(a: u32, b: u32)->u32 { return a & b }
    const V = #run bitAndTooFew(42'u32) // swc-expected-error {{sema_err_too_few_arguments}}
}
