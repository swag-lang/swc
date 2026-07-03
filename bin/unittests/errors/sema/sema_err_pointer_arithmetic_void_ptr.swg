#global private

alias VoidAlias = void

#[Swag.Strict]
alias StrictVoidAlias = void

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

#test
{
    var p: [*] void = null
    let a = p[0 until 1] // swc-expected-error {{sema_err_pointer_arithmetic_void_ptr}}
}

#test
{
    var p: [*] VoidAlias = null
    let a = p[0 until 1] // swc-expected-error {{sema_err_pointer_arithmetic_void_ptr}}
}

#test
{
    var p: [*] StrictVoidAlias = null
    let a = p + 1 // swc-expected-error {{sema_err_pointer_arithmetic_void_ptr}}
}

#test
{
    var p: [*] StrictVoidAlias = null
    let a = 1 + p // swc-expected-error {{sema_err_pointer_arithmetic_void_ptr}}
}

#test
{
    var p: [*] StrictVoidAlias = null
    let a = p - 1 // swc-expected-error {{sema_err_pointer_arithmetic_void_ptr}}
}

#test
{
    var p: [*] StrictVoidAlias = null
    var q: [*] StrictVoidAlias = null
    let a = p - q // swc-expected-error {{sema_err_pointer_arithmetic_void_ptr}}
}

#test
{
    var p: [*] StrictVoidAlias = null
    p += 1 // swc-expected-error {{sema_err_pointer_arithmetic_void_ptr}}
}

#test
{
    var p: [*] StrictVoidAlias = null
    p -= 1 // swc-expected-error {{sema_err_pointer_arithmetic_void_ptr}}
}

#test
{
    var p: [*] StrictVoidAlias = null
    let a = p[0] // swc-expected-error {{sema_err_pointer_arithmetic_void_ptr}}
}

#test
{
    var p: [*] StrictVoidAlias = null
    let a = p[0 until 1] // swc-expected-error {{sema_err_pointer_arithmetic_void_ptr}}
}
