#global private

#test
{
    func shiftLeft(a: u32, b: u32)->u32 { return a << b }
    const V = #run shiftLeft(21_u32, 1_u32)
    #assert(#typeof(V) == u32)
    #assert(V == 42_u32)
}

#test
{
    func shiftLeftChain(a: u32, b: u32, c: u32)->u32 { return (a << b) << c }
    const V = #run shiftLeftChain(5_u32, 2_u32, 1_u32)
    #assert(#typeof(V) == u32)
    #assert(V == 40_u32)
}

#test
{
    func shiftLeftStrict(a: u32, b: u32)->u32 { return a << b }
    const V = #run shiftLeftStrict(21_u32, 1_u32, 1_u32)     // swc-expected-error {{sema_err_too_many_arguments}}
}

#test
{
    func shiftLeftWide(a: u64, b: u32)->u64 { return a << b }
    const V = #run shiftLeftWide(1_u64, 40_u32)
    #assert(#typeof(V) == u64)
    #assert(V == 0x0000_0100_0000_0000_u64)
}

#test
{
    // A left shift truncates the bits it pushes out; the amount stays below the width.
    #[Swag.Safety(.Overflow, true)]
    func shiftLeftTruncates(a: u8, b: u64)->u8 { return a << b }

    const V0 = #run shiftLeftTruncates(0x80_u8, 1_u64)
    const V1 = #run shiftLeftTruncates(0x81_u8, 7_u64)
    #assert(V0 == 0_u8)
    #assert(V1 == 0x80_u8)
}

#test
{
    // An amount at or above the width is a fault under overflow safety.
    #[Swag.Safety(.Overflow, true)]
    func shiftLeftLargeAmount(a: u8, b: u64)->u8
    {
        return a << b     // swc-expected-error {{safety_err_runtime}}
    }

    const V = #run shiftLeftLargeAmount(1_u8, 8_u64)
}

#test
{
    func shiftLeftTooFew(a: u32, b: u32)->u32 { return a << b }
    const V = #run shiftLeftTooFew(21_u32)     // swc-expected-error {{sema_err_too_few_arguments}}
}

// A shift's result type is the LEFT operand's type; the (constant) shift amount
// must never re-sign it. Regression for `s32 << constU32` becoming unsigned,
// which silently turned later arithmetic `>>` into logical shifts (broke the
// JPEG idct fixed-point math).
#test
{
    let n = 12_u32
    // The shift keeps the LEFT operand's type; the unsigned amount must not
    // widen it or flip a signed value to unsigned.
    #assert(#typeof(1_s32 << n) == s32)
    #assert(#typeof(1_u32 << n) == u32)
    #assert(#typeof(1_s16 << n) == s16)
    #assert(#typeof(1_u16 << n) == u16)
}

#test
{
    // With a constant shift amount the inner `<< (n-1)` must keep the left signed
    // so the outer `>>` is an arithmetic (sign-extending) shift.
    func descale(x: s32)->s32
    {
        let n = 18_u32
        return cast(s32, ((x + (1_s32 << (n - 1))) >> n))
    }
    const V = #run descale(-4546560_s32)
    #assert(#typeof(V) == s32)
    #assert(V == -17_s32)     // arithmetic >>; a logical shift would yield 16367
}

#test
{
    // Unsigned shifts must stay logical (no regression to arithmetic).
    func logical()->u32
    {
        let n = 4_u32
        return (1_u32 << 31_u32) >> n
    }
    const V = #run logical()
    #assert(V == 0x0800_0000_u32)     // logical >>; arithmetic would sign-extend
}
