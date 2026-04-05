#global fileprivate

#[Swag.Safety(.All, .BoundCheck, false)]
func boundCheckDisabled()->bool
{
    return #safety(Swag.SafetyWhat.BoundCheck)
}

#[Swag.Safety(.All, .BoundCheck, true)]
func boundCheckEnabled()->bool
{
    return #safety(Swag.SafetyWhat.BoundCheck)
}

#test
{
    const cfg      = #run dref @compiler.getBuildCfg()
    const expected = cfg.safetyGuards & Swag.SafetyWhat.BoundCheck ? true : false
    #assert(#safety(Swag.SafetyWhat.BoundCheck) == expected)
}

#test
{
    const value = #run boundCheckDisabled()
    #assert(value == false)
}

#test
{
    const value = #run boundCheckEnabled()
    #assert(value == true)
}

#test
{
    #[Swag.Safety(.All, .BoundCheck, true)]
    func arrayBoundCheck()->s32
    {
        var values: [2] s32
        values[0] = 1
        values[1] = 2
        return values[2] // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run arrayBoundCheck()
    @assert(value == 0)
}

#test
{
    #[Swag.Safety(.All, .BoundCheck, true)]
    func sliceBoundCheck()->s32
    {
        var values: [2] s32
        values[0] = 1
        values[1] = 2
        var slice: [..] s32 = values
        return slice[2] // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run sliceBoundCheck()
    @assert(value == 0)
}

#test
{
    #[Swag.Safety(.All, .BoundCheck, true)]
    func stringBoundCheck()->u8
    {
        var text: string = "ab"
        return text[2] // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run stringBoundCheck()
    @assert(value == 0)
}

#test
{
    #[Swag.Safety(.All, .BoundCheck, true)]
    func multiArrayBoundCheck()->s32
    {
        var values: [2, 2] s32
        values[0, 0] = 1
        values[0, 1] = 2
        values[1, 0] = 3
        values[1, 1] = 4
        return values[1, 2] // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run multiArrayBoundCheck()
    @assert(value == 0)
}
