#global internal

#test
{
    for to 4 {}
    for until 4 {}
    for 5 until 4 {} // swc-expected-error {{sema_err_range_invalid_bounds}}
}
