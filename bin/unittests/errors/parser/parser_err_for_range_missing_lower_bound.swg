#global private

#test
{
    for to 4 {}     // swc-expected-error {{parser_err_for_range_missing_lower_bound}}
}

#test
{
    for until 4 {}     // swc-expected-error {{parser_err_for_range_missing_lower_bound}}
}
