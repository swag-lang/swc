#global private

#test
{
    for #reverse value in [1, 2, 3] {}     // swc-expected-error {{parser_err_invalid_compiler}}
}
