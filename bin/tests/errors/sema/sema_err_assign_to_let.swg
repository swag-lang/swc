#global fileprivate

#test
{
    let a = 1
    a = 2 // swc-expected-error {{sema_err_assign_to_let}}
}
