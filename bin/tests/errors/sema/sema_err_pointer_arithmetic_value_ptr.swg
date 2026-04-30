#global fileprivate

#test
{
    var p: *s32 = null
    let a = p + 1 // swc-expected-error {{sema_err_pointer_arithmetic_value_ptr}}
}

#test
{
    var p: *s32 = null
    let a = 1 + p // swc-expected-error {{sema_err_pointer_arithmetic_value_ptr}}
}

#test
{
    var p: *s32 = null
    let a = p - 1 // swc-expected-error {{sema_err_pointer_arithmetic_value_ptr}}
}

#test
{
    var p: *s32 = null
    var q: *s32 = null
    let a = p - q // swc-expected-error {{sema_err_pointer_arithmetic_value_ptr}}
}

#test
{
    var p: *s32 = null
    p += 1 // swc-expected-error {{sema_err_pointer_arithmetic_value_ptr}}
}

#test
{
    var p: *s32 = null
    p -= 1 // swc-expected-error {{sema_err_pointer_arithmetic_value_ptr}}
}

#test
{
    var p: *s32 = null
    let a = p[0] // swc-expected-error {{sema_err_pointer_arithmetic_value_ptr}}
}
