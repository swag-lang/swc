#global fileprivate

#[Swag.Safety(.Overflow, false)]
func overflowSafetyDisabled()->bool
{
    return #safety(Swag.SafetyWhat.Overflow)
}

#[Swag.Safety(.Overflow, true)]
func overflowSafetyEnabled()->bool
{
    return #safety(Swag.SafetyWhat.Overflow)
}

#test
{
    const cfg      = #run dref @compiler.getBuildCfg()
    const expected = cfg.safetyGuards & Swag.SafetyWhat.Overflow ? true : false
    #assert(#safety(Swag.SafetyWhat.Overflow) == expected)
}

#test
{
    const value = #run overflowSafetyDisabled()
    #assert(value == false)
}

#test
{
    const value = #run overflowSafetyEnabled()
    #assert(value == true)
}

#test
{
    #[Swag.Safety(.Overflow, true)]
    func addOverflow(a, b: s8)->s8
    {
        return a + b // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run addOverflow(120's8, 8's8)
}

#test
{
    #[Swag.Safety(.Overflow, true)]
    func mulOverflow(a, b: s16)->s16
    {
        return a * b // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run mulOverflow(300's16, 200's16)
}

#test
{
    #[Swag.Safety(.Overflow, true)]
    func divOverflow(a, b: s32)->s32
    {
        return a / b // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run divOverflow(-2147483648's32, -1)
}

#test
{
    #[Swag.Safety(.Overflow, true)]
    func unaryMinusOverflow(v: s8)->s8
    {
        return -v // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run unaryMinusOverflow(-128's8)
}

#test
{
    #[Swag.Safety(.Overflow, true)]
    func shiftLeftOverflow(a, count: s8)->s8
    {
        return a << count // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run shiftLeftOverflow(64's8, 1's8)
}

#test
{
    #[Swag.Safety(.Overflow, true)]
    func shiftRightNegative(a, count: s32)->s32
    {
        return a >> count // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run shiftRightNegative(42, -1)
}

#test
{
    #[Swag.Safety(.Overflow, true)]
    func addAssignOverflow()->s8
    {
        var value: s8 = 120
        value += 8 // swc-expected-error {{safety_err_runtime}}
        return value
    }

    const value = #run addAssignOverflow()
}

#test
{
    #[Swag.Safety(.Overflow, true)]
    func shiftAssignOverflow()->s8
    {
        var value: s8 = 64
        value <<= 1 // swc-expected-error {{safety_err_runtime}}
        return value
    }

    const value = #run shiftAssignOverflow()
}

#test
{
    #[Swag.Safety(.Overflow, true)]
    func narrowCastOverflow(v: u16)->u8
    {
        return cast(u8) v // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run narrowCastOverflow(256'u16)
}

#test
{
    #[Swag.Safety(.Overflow, true)]
    func floatCastOverflow(v: f64)->s8
    {
        return cast(s8) v // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run floatCastOverflow(128.0)
}

#test
{
    #[Swag.Safety(.Overflow, true)]
    func addWrap(a, b: u8)->u8
    {
        return a + #wrap b
    }

    const value = #run addWrap(255'u8, 1'u8)
    @assert(value == 0'u8)
}

#test
{
    #[Swag.Safety(.Overflow, true)]
    func shiftLeftWrap(a, count: u8)->u8
    {
        return a << #wrap count
    }

    const value = #run shiftLeftWrap(1'u8, 8'u8)
    @assert(value == 0'u8)
}

#test
{
    #[Swag.Safety(.Overflow, true)]
    func addPromoted(a, b: s8)->s32
    {
        return a + #prom b
    }

    const value = #run addPromoted(127's8, 1's8)
    @assert(value == 128)
}

#test
{
    #[Swag.Safety(.Overflow, true)]
    func wrapCast(v: u16)->u8
    {
        return cast #wrap(u8) v
    }

    const value = #run wrapCast(257'u16)
    @assert(value == 1'u8)
}
