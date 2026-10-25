#global private

#test
{
    let (value) = (42,) // swc-expected-error {{parser_err_tuple_pattern_comma}}
}

#test
{
    let {_, x} = {x: 10, y: 20} // swc-expected-error {{parser_err_named_pattern_field}}
}
