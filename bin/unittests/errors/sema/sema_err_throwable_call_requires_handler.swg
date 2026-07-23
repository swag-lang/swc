#global private

func throwableValue()->s32 throw
{
    return 1
}

func callWithoutHandler()
{
    let value = throwableValue()     // swc-expected-error {{sema_err_throwable_call_requires_handler}}
    @print(value)
}
