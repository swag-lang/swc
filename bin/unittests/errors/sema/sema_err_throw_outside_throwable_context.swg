#global private

func throwFromPlainFunction()
{
    throw Swag.BaseError{"cannot propagate"}     // swc-expected-error {{sema_err_throw_outside_throwable_context}}
}
