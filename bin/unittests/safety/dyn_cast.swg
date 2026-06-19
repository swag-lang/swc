#global fileprivate

// =============================================
// Safety flag configuration
// =============================================

#[Swag.Safety(.DynCast, false)]
func dynCastSafetyDisabled()->bool
{
    return #safety(Swag.SafetyWhat.DynCast)
}

#[Swag.Safety(.DynCast, true)]
func dynCastSafetyEnabled()->bool
{
    return #safety(Swag.SafetyWhat.DynCast)
}

#test
{
    const cfg      = #run dref @compiler.getBuildCfg()
    const expected = cfg.safetyGuards & Swag.SafetyWhat.DynCast ? true : false
    #assert(#safety(Swag.SafetyWhat.DynCast) == expected)
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
    #[Swag.Safety(.DynCast, true)]
    func castAnyToS32(a: any)->s32
    {
        return cast(s32) a
    }

    const value = #run castAnyToS32(42)
    #assert(value == 42)
}

#test
{
    #[Swag.Safety(.DynCast, true)]
    func castAnyToString(a: any)->string
    {
        return cast(string) a
    }

    const value = #run castAnyToString("hello")
    #assert(value == "hello")
}

#test
{
    #[Swag.Safety(.DynCast, true)]
    func castAnyToBool(a: any)->bool
    {
        return cast(bool) a
    }

    const value = #run castAnyToBool(true)
    #assert(value == true)
}

// =============================================
// Cast from any to mismatching type (should panic)
// =============================================

#test
{
    #[Swag.Safety(.DynCast, true)]
    func castAnyMismatch(a: any)->s32
    {
        return cast(s32) a // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run castAnyMismatch("not an int")
}

#test
{
    #[Swag.Safety(.DynCast, true)]
    func castAnyBoolMismatch(a: any)->bool
    {
        return cast(bool) a // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run castAnyBoolMismatch(42)
}

// =============================================
// Cast from any with safety disabled (should not panic)
// =============================================

#test
{
    #[Swag.Safety(.DynCast, false)]
    func castAnyNoSafety(a: any)->s32
    {
        return cast(s32) a
    }

    const value = #run castAnyNoSafety("not an int")
}

// =============================================
// Struct cast from any using @as mechanism
// =============================================

struct Base
{
    value: s32 = 10
}

struct Mid
{
    using base: Base
    midValue: s32 = 20
}

struct Derived
{
    using mid: Mid
    derivedValue: s32 = 30
}

// Cast any to struct: exact type match
#test
{
    #[Swag.Safety(.DynCast, true)]
    func castAnyToBase(a: any)->Base
    {
        return cast(Base) a
    }

    const value = #run castAnyToBase(Base{value: 77})
    #assert(value.value == 77)
}

// Cast any to struct: using-field resolution (Derived contains Base via using)
#test
{
    #[Swag.Safety(.DynCast, true)]
    func castAnyToBase2(a: any)->Base
    {
        return cast(Base) a
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

    #[Swag.Safety(.DynCast, true)]
    func castAnyToUnrelated(a: any)->Unrelated
    {
        return cast(Unrelated) a // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run castAnyToUnrelated(Base{value: 10})
}
