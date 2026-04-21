#global fileprivate

#test
{
    for "a" to 4 {} // swc-expected-error {{sema_err_invalid_range_type}}
}

#test
{
    for to "a" {} // swc-expected-error {{sema_err_invalid_range_type}}
}
