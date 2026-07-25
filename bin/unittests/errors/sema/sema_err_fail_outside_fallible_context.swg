#global private

func throwFromPlainFunction()
{
    fail Swag.BaseError{"cannot propagate"}     // swc-expected-error {{sema_err_fail_outside_fallible_context}}
}
