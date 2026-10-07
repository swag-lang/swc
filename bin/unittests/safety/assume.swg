#global private

func failingAssumption()->*s32 fail { fail Swag.BaseError{"assumption violated"} }

#[Swag.Safety(.All, false), Swag.Safety(.Assume, true)]
func guardedAssumption()->*s32 => assume failingAssumption()     // swc-expected-error {{sema_err_compiler_panic}}

#test
{
    discard guardedAssumption()
}

#[Swag.Safety(.All, false), Swag.Safety(.Assume, true)]
func guardedPresence(value: *s32?)->*s32
{
    return assume (cast(*s32, value))     // swc-expected-error {{safety_err_runtime}}
}

#test
{
    discard guardedPresence(null)
}

#[Swag.Safety(.All, false), Swag.Safety(.Assume, true)]
func guardedType(value: any)->s32
{
    return assume cast(s32, value)     // swc-expected-error {{safety_err_runtime}}
}

#test
{
    discard guardedType("mismatch")
}
