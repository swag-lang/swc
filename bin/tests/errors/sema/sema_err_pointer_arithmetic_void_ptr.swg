#global fileprivate

alias VoidAlias = void

#test
{
    var p: [*] void = null
    let a = p + 1 // swc-expected-error {{sema_err_pointer_arithmetic_void_ptr}}
}

#test
{
    var p: [*] void = null
    let a = p[0] // swc-expected-error {{sema_err_pointer_arithmetic_void_ptr}}
}

#test
{
    var p: [*] VoidAlias = null
    let a = p[0] // swc-expected-error {{sema_err_pointer_arithmetic_void_ptr}}
}
