#global fileprivate

// Declaring the same name twice in the same scope is an error.
#test
{
    var x = 0
    var x = 0                        // swc-expected-error {{sema_err_already_defined}}
}

#test
{
    let y = 1
    let y = 2                        // swc-expected-error {{sema_err_already_defined}}
}

#test
{
    var a: s32
    let a: bool                      // swc-expected-error {{sema_err_already_defined}}
}
