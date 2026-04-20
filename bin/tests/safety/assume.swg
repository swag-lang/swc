#global fileprivate

func mayThrowValue(v: s32)->s32 throw
{
    return v
}

func alwaysThrowValue()->s32 throw
{
    throw Swag.BaseError{"assume failed"}
}

#[Swag.Safety(.Assume, false)]
func assumeSafetyDisabled()->bool
{
    return #safety(Swag.SafetyWhat.Assume)
}

#[Swag.Safety(.Assume, true)]
func assumeSafetyEnabled()->bool
{
    return #safety(Swag.SafetyWhat.Assume)
}

#test
{
    const cfg      = #run dref @compiler.getBuildCfg()
    const expected = cfg.safetyGuards & Swag.SafetyWhat.Assume ? true : false
    #assert(#safety(Swag.SafetyWhat.Assume) == expected)
}

#test
{
    const value = #run assumeSafetyDisabled()
    #assert(value == false)
}

#test
{
    const value = #run assumeSafetyEnabled()
    #assert(value == true)
}

#test
{
    #[Swag.Safety(.Assume, true)]
    func assumeSuccess()->s32
    {
        return assume mayThrowValue(42)
    }

    const value = #run assumeSuccess()
    #assert(value == 42)
}

#test
{
    #[Swag.Safety(.Assume, true)]
    func assumeFailurePanic()->s32
    {
        return assume alwaysThrowValue() // swc-expected-error {{sema_err_compiler_panic}}
    }

    const value = #run assumeFailurePanic()
}

#test
{
    #[Swag.Safety(.Assume, false)]
    func assumeFailureDisabled()->s32
    {
        return assume alwaysThrowValue()
    }

    const value = #run assumeFailureDisabled()
    #assert(value == 0)
}
