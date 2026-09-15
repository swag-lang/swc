#global private

#[Swag.Safety(.DynCast, true)]
func assumeWrongNullPointer(value: any?)
{
    // swc-expected-error@(+1) {{safety_err_runtime}}
    let pointer = cast #assume (*s32?) value
}

#test
{
    let absent: *s64? = null
    assumeWrongNullPointer(absent)
}

#[Swag.DynCast]
struct CheckedDynamicBase { value: s32 }
struct CheckedDynamicChild { using base: CheckedDynamicBase; extra: s32 }

#[Swag.Safety(.DynCast, true)]
func assumeDynamicChild(value: *CheckedDynamicBase)
{
    // swc-expected-error@(+1) {{safety_err_runtime}}
    let child = cast #assume (*CheckedDynamicChild) value
}

#test
{
    var value: CheckedDynamicBase
    assumeDynamicChild(&value)
}

#[Swag.Safety(.DynCast, true)]
func assumePresentChild(value: *CheckedDynamicBase?)
{
    // swc-expected-error@(+1) {{safety_err_runtime}}
    let child = cast #assume (*CheckedDynamicChild) value
}

#test
{
    assumePresentChild(null)
}

#[Swag.Safety(.DynCast, false)]
func tryDynamicChild(value: *CheckedDynamicBase)->*CheckedDynamicChild?
{
    return cast #try (*CheckedDynamicChild) value
}

#test
{
    var value: CheckedDynamicBase
    Swag.assert(tryDynamicChild(&value) == null)
}
