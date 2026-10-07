#global private

#[Swag.Safety(.Assume, true)]
func assumeWrongNullPointer(value: any?)
{
    // swc-expected-error@(+1) {{safety_err_runtime}}
    let pointer = assume cast (*s32?, value)
    discard pointer
}

#test
{
    let absent: *s64? = null
    assumeWrongNullPointer(absent)
}

#[Swag.DynCast]
struct CheckedDynamicBase { value: s32 }
struct CheckedDynamicChild { using base: CheckedDynamicBase; extra: s32 }

#[Swag.Safety(.Assume, true)]
func assumeDynamicChild(value: *CheckedDynamicBase)
{
    // swc-expected-error@(+1) {{safety_err_runtime}}
    let child = assume cast (*CheckedDynamicChild, value)
    discard child
}

#test
{
    var value: CheckedDynamicBase
    assumeDynamicChild(&value)
}

#[Swag.Safety(.Assume, true)]
func assumePresentChild(value: *CheckedDynamicBase?)
{
    // swc-expected-error@(+1) {{safety_err_runtime}}
    let child = assume cast (*CheckedDynamicChild, value)
    discard child
}

#test
{
    assumePresentChild(null)
}

#[Swag.Safety(.Assume, false)]
func tryDynamicChild(value: *CheckedDynamicBase)->*CheckedDynamicChild?
{
    return (catch cast(*CheckedDynamicChild?, value))
}

#test
{
    var value: CheckedDynamicBase
    Swag.assert(tryDynamicChild(&value) == null)
}
