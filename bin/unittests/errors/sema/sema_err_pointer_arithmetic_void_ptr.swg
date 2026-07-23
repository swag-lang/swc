#global private

alias VoidAlias = void

#[Swag.Strict]
alias StrictVoidAlias = void

#test
{
    var pv: u8
    var p: [*] void = cast([*] void) &pv
    let a = p + 1     // swc-expected-error {{sema_err_pointer_arithmetic_void_ptr}}
}

#test
{
    var pv: u8
    var p: [*] void = cast([*] void) &pv
    let a = p[0]     // swc-expected-error {{sema_err_pointer_arithmetic_void_ptr}}
}

#test
{
    var pv: u8
    var p: [*] VoidAlias = cast([*] VoidAlias) &pv
    let a = p[0]     // swc-expected-error {{sema_err_pointer_arithmetic_void_ptr}}
}

#test
{
    var pv: u8
    var p: [*] void = cast([*] void) &pv
    let a = p[0 until 1]     // swc-expected-error {{sema_err_pointer_arithmetic_void_ptr}}
}

#test
{
    var pv: u8
    var p: [*] VoidAlias = cast([*] VoidAlias) &pv
    let a = p[0 until 1]     // swc-expected-error {{sema_err_pointer_arithmetic_void_ptr}}
}

#test
{
    var pv: u8
    var p: [*] StrictVoidAlias = cast([*] StrictVoidAlias) &pv
    let a = p + 1     // swc-expected-error {{sema_err_pointer_arithmetic_void_ptr}}
}

#test
{
    var pv: u8
    var p: [*] StrictVoidAlias = cast([*] StrictVoidAlias) &pv
    let a = 1 + p     // swc-expected-error {{sema_err_pointer_arithmetic_void_ptr}}
}

#test
{
    var pv: u8
    var p: [*] StrictVoidAlias = cast([*] StrictVoidAlias) &pv
    let a = p - 1     // swc-expected-error {{sema_err_pointer_arithmetic_void_ptr}}
}

#test
{
    var pv: u8
    var p: [*] StrictVoidAlias = cast([*] StrictVoidAlias) &pv
    var q: [*] StrictVoidAlias = cast([*] StrictVoidAlias) &pv
    let a = p - q     // swc-expected-error {{sema_err_pointer_arithmetic_void_ptr}}
}

#test
{
    var pv: u8
    var p: [*] StrictVoidAlias = cast([*] StrictVoidAlias) &pv
    p += 1     // swc-expected-error {{sema_err_pointer_arithmetic_void_ptr}}
}

#test
{
    var pv: u8
    var p: [*] StrictVoidAlias = cast([*] StrictVoidAlias) &pv
    p -= 1     // swc-expected-error {{sema_err_pointer_arithmetic_void_ptr}}
}

#test
{
    var pv: u8
    var p: [*] StrictVoidAlias = cast([*] StrictVoidAlias) &pv
    let a = p[0]     // swc-expected-error {{sema_err_pointer_arithmetic_void_ptr}}
}

#test
{
    var pv: u8
    var p: [*] StrictVoidAlias = cast([*] StrictVoidAlias) &pv
    let a = p[0 until 1]     // swc-expected-error {{sema_err_pointer_arithmetic_void_ptr}}
}
