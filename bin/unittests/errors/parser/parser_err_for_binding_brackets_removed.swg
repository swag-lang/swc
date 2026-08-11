#global private

#test
{
    for [index] in 3 {}     // swc-expected-error {{parser_err_for_binding_brackets_removed}}
}

#test
{
    let values = [10, 20, 30]
    for value, [index] in values {}     // swc-expected-error {{parser_err_for_binding_brackets_removed}}
}
