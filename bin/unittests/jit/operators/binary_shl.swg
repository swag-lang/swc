#global private

#test
{
    func shiftLeft(a: u32, b: u32)->u32 { return a << b }
    const V = #run shiftLeft(21'u32, 1'u32)
    #assert(#typeof(V) == u32)
    #assert(V == 42'u32)
}

#test
{
    func shiftLeftChain(a: u32, b: u32, c: u32)->u32 { return (a << b) << c }
    const V = #run shiftLeftChain(5'u32, 2'u32, 1'u32)
    #assert(#typeof(V) == u32)
    #assert(V == 40'u32)
}

#test
{
    func shiftLeftStrict(a: u32, b: u32)->u32 { return a << b }
    const V = #run shiftLeftStrict(21'u32, 1'u32, 1'u32)     // swc-expected-error {{sema_err_too_many_arguments}}
}

#test
{
    func shiftLeftWide(a: u64, b: u32)->u64 { return a << b }
    const V = #run shiftLeftWide(1'u64, 40'u32)
    #assert(#typeof(V) == u64)
    #assert(V == 0x0000_0100_0000_0000'u64)
}

#test
{
    #[Swag.Safety(.Overflow, true)]
    func shiftLeftTruncates(a: u8, b: u64)->u8 { return a << b }

    const V0 = #run shiftLeftTruncates(0x80'u8, 1'u64)
    const V1 = #run shiftLeftTruncates(1'u8, 8'u64)
    const V2 = #run shiftLeftTruncates(1'u8, 256'u64)
    #assert(V0 == 0'u8)
    #assert(V1 == 0'u8)
    #assert(V2 == 0'u8)
}

#test
{
    func shiftLeftTooFew(a: u32, b: u32)->u32 { return a << b }
    const V = #run shiftLeftTooFew(21'u32)     // swc-expected-error {{sema_err_too_few_arguments}}
}

// A shift's result type is the LEFT operand's type; the (constant) shift amount
// must never re-sign it. Regression for `s32 << constU32` becoming unsigned,
// which silently turned later arithmetic `>>` into logical shifts (broke the
// JPEG idct fixed-point math).
#test
{
    let n = 18'u32
    // The shift keeps the LEFT operand's type; the unsigned amount must not
    // widen it or flip a signed value to unsigned.
    #assert(#typeof(1's32 << n) == s32)
    #assert(#typeof(1'u32 << n) == u32)
    #assert(#typeof(1's16 << n) == s16)
    #assert(#typeof(1'u16 << n) == u16)
}

#test
{
    // With a constant shift amount the inner `<< (n-1)` must keep the left signed
    // so the outer `>>` is an arithmetic (sign-extending) shift.
    func descale(x: s32)->s32
    {
        let n = 18'u32
        return cast(s32) ((x + (1's32 << (n - 1))) >> n)
    }
    const V = #run descale(-4546560's32)
    #assert(#typeof(V) == s32)
    #assert(V == -17's32)     // arithmetic >>; a logical shift would yield 16367
}

#test
{
    // Unsigned shifts must stay logical (no regression to arithmetic).
    func logical()->u32
    {
        let n = 4'u32
        return (1'u32 << 31'u32) >> n
    }
    const V = #run logical()
    #assert(V == 0x0800_0000'u32)     // logical >>; arithmetic would sign-extend
}
