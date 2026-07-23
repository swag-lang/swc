#global private

func throwableValue()->s32 throw
{
    return 1
}

func tryFromPlainFunction()
{
    discard try throwableValue() // swc-expected-error {{sema_err_try_outside_throwable_context}}
}
