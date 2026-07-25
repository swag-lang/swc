#global private

func fallibleValue()->s32 fail
{
    return 1
}

func callWithoutHandler()
{
    let value = fallibleValue()     // swc-expected-error {{sema_err_fallible_call_requires_handler}}
    @print(value)
}
