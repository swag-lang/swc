#global internal

#test
{
    func shiftRight(a: u32, b: u32)->u32 { return a >> b }
    const V = #run shiftRight(168'u32, 2'u32)
    #assert(#typeof(V) == u32)
    #assert(V == 42'u32)
}

#test
{
    func shiftArithRight(a: s32, b: s32)->s32 { return a >> b }
    const V = #run shiftArithRight(-84, 1)
    #assert(#typeof(V) == s32)
    #assert(V == -42)
}

#test
{
    func shiftRightStrict(a: u32, b: u32)->u32 { return a >> b }
    const V = #run shiftRightStrict(168'u32, 2'u32, 1'u32) // swc-expected-error {{sema_err_too_many_arguments}}
}

#test
{
    func shiftRightWide(a: u64, b: u32)->u64 { return a >> b }
    const V = #run shiftRightWide(0x0001_0000_0000_0000'u64, 40'u32)
    #assert(#typeof(V) == u64)
    #assert(V == 0x100'u64)
}

#test
{
    func shiftRightTooFew(a: u32, b: u32)->u32 { return a >> b }
    const V = #run shiftRightTooFew(168'u32) // swc-expected-error {{sema_err_too_few_arguments}}
}
