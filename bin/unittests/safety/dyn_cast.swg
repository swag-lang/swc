#global private

// =============================================
// Safety flag configuration
// =============================================

#[Swag.Safety(.Assume, false)]
func dynCastSafetyDisabled()->bool
{
    return #safety(Swag.SafetyWhat.Assume)
}

#[Swag.Safety(.Assume, true)]
func dynCastSafetyEnabled()->bool
{
    return #safety(Swag.SafetyWhat.Assume)
}

#test
{
    const cfg      = #run Swag.compiler().getBuildCfg()![]
    const expected = cfg.safetyGuards & Swag.SafetyWhat.Assume ? true : false
    #assert(#safety(Swag.SafetyWhat.Assume) == expected)
}

#test
{
    const value = #run dynCastSafetyDisabled()
    #assert(value == false)
}

#test
{
    const value = #run dynCastSafetyEnabled()
    #assert(value == true)
}

// =============================================
// Cast from any to matching primitive type (should pass)
// =============================================

#test
{
    #[Swag.Safety(.Assume, true)]
    func castAnyToS32(a: any)->s32
    {
        return assume cast(s32, a)
    }

    const value = #run castAnyToS32(42)
    #assert(value == 42)
}

#test
{
    #[Swag.Safety(.Assume, true)]
    func castAnyToString(a: any)->string
    {
        return assume cast(string, a)
    }

    const value = #run castAnyToString("hello")
    #assert(value == "hello")
}

#test
{
    #[Swag.Safety(.Assume, true)]
    func castAnyToBool(a: any)->bool
    {
        return assume cast(bool, a)
    }

    const value = #run castAnyToBool(true)
    #assert(value == true)
}

// =============================================
// Cast from any to mismatching type (should panic)
// =============================================

#test
{
    #[Swag.Safety(.Assume, true)]
    func castAnyMismatch(a: any)->s32
    {
        return assume cast(s32, a)     // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run castAnyMismatch("not an int")
}

#test
{
    #[Swag.Safety(.Assume, true)]
    func castAnyBoolMismatch(a: any)->bool
    {
        return assume cast(bool, a)     // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run castAnyBoolMismatch(42)
}

// =============================================
// Cast from any with safety disabled (should not panic)
// =============================================

#test
{
    #[Swag.Safety(.Assume, false)]
    func castAnyNoSafety(a: any)->s32
    {
        return assume cast(s32, a)
    }

    const value = #run castAnyNoSafety("not an int")
}

// =============================================
// Checked struct extraction from any
// =============================================

struct Base
{
    value: s32 = 10
}

struct Mid
{
    using base: Base
    midValue:   s32 = 20
}

struct Derived
{
    using mid:    Mid
    derivedValue: s32 = 30
}

// Cast any to struct: exact type match
#test
{
    #[Swag.Safety(.Assume, true)]
    func castAnyToBase(a: any)->Base
    {
        return assume cast(Base, a)
    }

    const value = #run castAnyToBase(Base{value: 77})
    #assert(value.value == 77)
}

// Cast any to struct: using-field resolution (Derived contains Base via using)
#test
{
    #[Swag.Safety(.Assume, true)]
    func castAnyToBase2(a: any)->Base
    {
        return assume cast(Base, a)
    }

    const value = #run castAnyToBase2(Derived{mid: {base: {value: 99}, midValue: 50}, derivedValue: 60})
    #assert(value.value == 99)
}

// Cast any to struct: type mismatch (should panic)
#test
{
    struct Unrelated
    {
        x: s32 = 0
    }

    #[Swag.Safety(.Assume, true)]
    func castAnyToUnrelated(a: any)->Unrelated
    {
        return assume cast(Unrelated, a)     // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run castAnyToUnrelated(Base{value: 10})
}
