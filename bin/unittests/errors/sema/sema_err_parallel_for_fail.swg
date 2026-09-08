#global private

func plainCaller()
{
    try parallel for || index in 4     // swc-expected-error {{sema_err_try_outside_fallible_context}}
    {
        fail Swag.BaseError{"parallel failure"}
    }
}

func unhandledLoop() fail
{
    parallel for || index in 4
    {
        fail Swag.BaseError{"parallel failure"}     // swc-expected-error {{sema_err_fail_outside_fallible_context}}
    }
}
