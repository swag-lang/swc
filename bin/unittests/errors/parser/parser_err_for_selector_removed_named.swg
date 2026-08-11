#global private

#test
{
    for #Pairs left, right in [1, 2, 3] {}     // swc-expected-error {{parser_err_for_selector_removed}}
}
