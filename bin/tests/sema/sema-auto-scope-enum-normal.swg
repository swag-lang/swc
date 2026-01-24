#global internal

enum A { R, G, B }

#test
{
    let x: A = .C // swc-expected-error {{sema_err_auto_scope_missing_value}}
}

#test
{
    let x: A = .R
    let y = x == .C // swc-expected-error {{sema_err_auto_scope_missing_value}}
}

#test
{
    let y = .C // swc-expected-error {{sema_err_cannot_compute_auto_scope}}
}
