#global fileprivate

#test
{
    let (a, b) = 12 // swc-expected-error {{sema_err_decomposition_not_struct}}
}
