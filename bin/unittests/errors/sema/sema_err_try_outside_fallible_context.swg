#global private

func fallibleValue()->s32 fail
{
    return 1
}

func tryFromPlainFunction()
{
    discard try fallibleValue()     // swc-expected-error {{sema_err_try_outside_fallible_context}}
}

// A test follows the same rule as another function without 'fail'.
#test
{
    discard try fallibleValue()     // swc-expected-error {{sema_err_try_outside_fallible_context}}
}

#test
{
    discard expect fallibleValue()
}
