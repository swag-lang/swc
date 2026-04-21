#global fileprivate

#test
{
    const L = #location(1 + 2) // swc-expected-error {{sema_err_invalid_location}}
}
