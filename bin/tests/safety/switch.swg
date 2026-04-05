#global fileprivate

#[Swag.Safety(.Switch, false)]
func switchSafetyDisabled()->bool
{
    return #safety(Swag.SafetyWhat.Switch)
}

#[Swag.Safety(.Switch, true)]
func switchSafetyEnabled()->bool
{
    return #safety(Swag.SafetyWhat.Switch)
}

#test
{
    const cfg      = #run dref @compiler.getBuildCfg()
    const expected = cfg.safetyGuards & Swag.SafetyWhat.Switch ? true : false
    #assert(#safety(Swag.SafetyWhat.Switch) == expected)
}

#test
{
    const value = #run switchSafetyDisabled()
    #assert(value == false)
}

#test
{
    const value = #run switchSafetyEnabled()
    #assert(value == true)
}

#test
{
    #[Swag.Safety(.Switch, true)]
    func completeScalarSwitchPanic(v: s32)->s32
    {
        #[Swag.Complete]
        switch v // swc-expected-error {{safety_err_runtime}}
        {
            case 1 to 3:
                return 10
        }

        return 77
    }

    const value = #run completeScalarSwitchPanic(9)
    @assert(value == 0)
}

#test
{
    #[Swag.Safety(.Switch, true)]
    func completeWhereSwitchPanic(v: s32)->s32
    {
        #[Swag.Complete]
        switch v // swc-expected-error {{safety_err_runtime}}
        {
            case 1 where false:
                return 10
        }

        return 77
    }

    const value = #run completeWhereSwitchPanic(1)
    @assert(value == 0)
}

#test
{
    #[Swag.Safety(.Switch, false)]
    func completeScalarSwitchDisabled(v: s32)->s32
    {
        #[Swag.Complete]
        switch v
        {
            case 1 to 3:
                return 10
        }

        return 77
    }

    const value = #run completeScalarSwitchDisabled(9)
    @assert(value == 77)
}
