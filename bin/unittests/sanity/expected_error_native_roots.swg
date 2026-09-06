#global private

// Native entry points are selected before code generation can diagnose a callee.
// A matched diagnostic must remove its callers from startup as well as the code table.
#[Swag.Safety(.Math, false), Swag.Sanity(.Math, true)]
func rejectedNativeCallee()->s32
{
    var divisor = 0
    var value   = 10
    return value / divisor     // swc-expected-error {{sanity_err_division_zero}}
}

func rejectedNativeCaller()->s32
{
    return rejectedNativeCallee()
}

#test
{
    discard rejectedNativeCaller()
}

#test
{
    Swag.assert(6 * 7 == 42)
}
