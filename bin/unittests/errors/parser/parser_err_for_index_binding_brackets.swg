#global private

#test
{
    let values = [10, 20, 30]

    for value, index in values     // swc-expected-error {{parser_err_for_index_binding_brackets}}
    {
        discard value
        discard index
    }
}
