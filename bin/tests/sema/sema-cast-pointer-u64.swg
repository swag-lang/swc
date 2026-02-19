#global internal

#test
{
    const P = cast(*void) 0x1234'u64
    const V = cast(u64) P
    #assert(#typeof(P) == *void)
    #assert(#typeof(V) == u64)
    #assert(V == 0x1234'u64)
    #assert(P == cast(*void) V)
}

#test
{
    const P = cast([*]u8) 0xABCD'u64
    const V = cast(u64) P
    #assert(#typeof(P) == [*]u8)
    #assert(#typeof(V) == u64)
    #assert(V == 0xABCD'u64)
    #assert(P == cast([*]u8) V)
}

#test
{
    const P0 = cast(*void) 0x1234'u64
    const P1 = cast(*void) 0x1235'u64
    #assert(P0 != P1)
    #assert(P0 == cast(*void) 0x1234'u64)
}

#test
{
    const P: *void = 0x1234'u64 // swc-expected-error {{sema_err_cannot_cast}}
}

#test
{
    const P = cast(*void) 1'u32 // swc-expected-error {{sema_err_cannot_cast}}
}

#test
{
    const A: u64 = cast(*void) 1'u64 // swc-expected-error {{sema_err_cannot_cast}}
}

#test
{
    const B = cast([*]u8) 1'u32 // swc-expected-error {{sema_err_cannot_cast}}
}
