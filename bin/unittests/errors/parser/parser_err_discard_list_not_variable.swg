#global private

func value()->s32 => 1

// A 'discard' list names variables; an expression is discarded on its own.
#test
{
    let a = 0
    let b = 0
    discard a, b
    discard value()
}

#test
{
    let a = 0
    discard a, value()     // swc-expected-error {{parser_err_discard_list_not_variable}}
}

#test
{
    let a = 0
    discard value(), a     // swc-expected-error {{parser_err_discard_list_not_variable}}
}

#test
{
    let a = 0
    discard a, a + 1     // swc-expected-error {{parser_err_discard_list_not_variable}}
}
