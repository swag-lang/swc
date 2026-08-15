#global private

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
    const V = #run shiftRightStrict(168'u32, 2'u32, 1'u32)     // swc-expected-error {{sema_err_too_many_arguments}}
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
    func shiftRightMixedUnsigned(a: u8, b: u64)->u8 { return a >> b }
    func shiftRightMixedSigned(a: s8, b: u64)->s8 { return a >> b }

    const V0 = #run shiftRightMixedUnsigned(0x80'u8, 256'u64)
    const V1 = #run shiftRightMixedSigned(-128's8, 256'u64)
    const V2 = #run shiftRightMixedUnsigned(0x80'u8, 0x1_0000_0000'u64)
    #assert(V0 == 0'u8)
    #assert(V1 == -1's8)
    #assert(V2 == 0'u8)
}

#test
{
    func shiftRightTooFew(a: u32, b: u32)->u32 { return a >> b }
    const V = #run shiftRightTooFew(168'u32)     // swc-expected-error {{sema_err_too_few_arguments}}
}
