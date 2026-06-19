#global fileprivate

// A 'let' binding cannot be reassigned, regardless of the operator used.
#test
{
    let a = 1
    a = 2                        // swc-expected-error {{sema_err_assign_to_let}}
}

#test
{
    let b = 10
    b += 5                       // swc-expected-error {{sema_err_assign_to_let}}
}

#test
{
    let s = "hi"
    s = "bye"                    // swc-expected-error {{sema_err_assign_to_let}}
}
