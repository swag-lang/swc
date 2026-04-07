#global fileprivate

#[Swag.Safety(.Unreachable, false)]
func unreachableSafetyDisabled()->bool
{
    return #safety(Swag.SafetyWhat.Unreachable)
}

#[Swag.Safety(.Unreachable, true)]
func unreachableSafetyEnabled()->bool
{
    return #safety(Swag.SafetyWhat.Unreachable)
}

#test
{
    const cfg      = #run dref @compiler.getBuildCfg()
    const expected = cfg.safetyGuards & Swag.SafetyWhat.Unreachable ? true : false
    #assert(#safety(Swag.SafetyWhat.Unreachable) == expected)
}

#test
{
    const value = #run unreachableSafetyDisabled()
    #assert(value == false)
}

#test
{
    const value = #run unreachableSafetyEnabled()
    #assert(value == true)
}

#test
{
    #[Swag.Safety(.Unreachable, true)]
    func hitUnreachable()->s32
    {
        unreachable // swc-expected-error {{safety_err_runtime}}
        return 42
    }

    const value = #run hitUnreachable()
    @assert(value == 0)
}

#test
{
    #[Swag.Safety(.Unreachable, false)]
    func ignoreUnreachable()->s32
    {
        unreachable
        return 42
    }

    const value = #run ignoreUnreachable()
    @assert(value == 42)
}

// Unreachable in a conditional branch
#test
{
    #[Swag.Safety(.Unreachable, true)]
    func unreachableInBranch(v: s32)->s32
    {
        if v > 0
        {
            unreachable // swc-expected-error {{safety_err_runtime}}
        }

        return 42
    }

    const value = #run unreachableInBranch(1)
}

// Unreachable not reached: branch not taken, no panic
#test
{
    #[Swag.Safety(.Unreachable, true)]
    func unreachableNotReached(v: s32)->s32
    {
        if v > 0
        {
            unreachable
        }

        return 42
    }

    const value = #run unreachableNotReached(-1)
    @assert(value == 42)
}
