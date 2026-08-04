#global private

func mayFailValue(v: s32)->s32 fail
{
    return v
}

func alwaysFailValue()->s32 fail
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
    const cfg      = #run dref @compiler.getBuildCfg()!
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
        return expect mayFailValue(42)
    }

    const value = #run expectSuccess()
    #assert(value == 42)
}

#test
{
    #[Swag.Safety(.Expect, true)]
    func expectFailurePanic()->s32
    {
        return expect alwaysFailValue()     // swc-expected-error {{sema_err_compiler_panic}}
    }

    const value = #run expectFailurePanic()
}

#test
{
    #[Swag.Safety(.Expect, true)]
    func expectNullableFailurePanic()->bool
    {
        let value: #null *s32 = null
        let ptr               = value!     // swc-expected-error {{safety_err_runtime}}
        return ptr != null
    }

    const value = #run expectNullableFailurePanic()
}

#test
{
    #[Swag.Safety(.Expect, false)]
    func expectFailureDisabled()->s32
    {
        return expect alwaysFailValue()
    }

    const value = #run expectFailureDisabled()
    #assert(value == 0)
}

struct ExpectAccessNode
{
    value: s32
}

var g_expectAccessNode = ExpectAccessNode{value: 42}

func expectAccessNode(present: bool)->#null *ExpectAccessNode => present ? &g_expectAccessNode : null

#test
{
    #[Swag.Safety(.Expect, true)]
    func notNullAccessPanic()->s32
    {
        return expectAccessNode(false)!.value     // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run notNullAccessPanic()
}

#test
{
    #[Swag.Safety(.Expect, true)]
    func notNullAccessSuccess()->s32
    {
        return expectAccessNode(true)!.value
    }

    const value = #run notNullAccessSuccess()
    #assert(value == 42)
}

// 'cast #unnull' crosses the nullable boundary under the same safety category.
func expectRawNode(present: bool)->#null *void => present ? cast(*void) &g_expectAccessNode : null

#test
{
    #[Swag.Safety(.Expect, true)]
    func unNullCastPanic()->s32
    {
        let node = cast #unnull (*ExpectAccessNode) expectRawNode(false)     // swc-expected-error {{safety_err_runtime}}
        return node.value
    }

    const value = #run unNullCastPanic()
}

#test
{
    #[Swag.Safety(.Expect, true)]
    func unNullCastSuccess()->s32
    {
        let node = cast #unnull (*ExpectAccessNode) expectRawNode(true)
        return node.value
    }

    const value = #run unNullCastSuccess()
    #assert(value == 42)
}
