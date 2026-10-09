#global private

// '=' inside a condition is a comparison written with the assignment operator.

func assignInIf(x: s32)->s32
{
    if x = 1 do     // swc-expected-error {{parser_err_assign_in_condition}}
        return 1
    return 0
}
