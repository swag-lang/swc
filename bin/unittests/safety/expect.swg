#global private

func mayThrowValue(v: s32)->s32 fail
{
    return v
}

func alwaysThrowValue()->s32 fail
{
    fail Swag.BaseError{"expect failed"}
}

#[Swag.Safety(.Expect, false)]
func expectSafetyDisabled()->bool
{
    return #safety(Swag.SafetyWhat.Expect)
}

#[Swag.Safety(.Expect, true)]
func expectSafetyEnabled()->bool
{
    return #safety(Swag.SafetyWhat.Expect)
}

#test
{
    const cfg      = #run dref notnull @compiler.getBuildCfg()
    const expected = cfg.safetyGuards & Swag.SafetyWhat.Expect ? true : false
    #assert(#safety(Swag.SafetyWhat.Expect) == expected)
}

#test
{
    const value = #run expectSafetyDisabled()
    #assert(value == false)
}

#test
{
    const value = #run expectSafetyEnabled()
    #assert(value == true)
}

#test
{
    #[Swag.Safety(.Expect, true)]
    func expectSuccess()->s32
    {
        return expect mayThrowValue(42)
    }

    const value = #run expectSuccess()
    #assert(value == 42)
}

#test
{
    #[Swag.Safety(.Expect, true)]
    func expectFailurePanic()->s32
    {
        return expect alwaysThrowValue()     // swc-expected-error {{sema_err_compiler_panic}}
    }

    const value = #run expectFailurePanic()
}

#test
{
    #[Swag.Safety(.Expect, true)]
    func expectNullableFailurePanic()->bool
    {
        let value: #null *s32 = null
        let ptr               = notnull value     // swc-expected-error {{safety_err_runtime}}
        return ptr != null
    }

    const value = #run expectNullableFailurePanic()
}

#test
{
    #[Swag.Safety(.Expect, false)]
    func expectFailureDisabled()->s32
    {
        return expect alwaysThrowValue()
    }

    const value = #run expectFailureDisabled()
    #assert(value == 0)
}
