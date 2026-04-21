#global fileprivate

#test
{
    let y = .C // swc-expected-error {{sema_err_cannot_compute_auto_scope}}
}
