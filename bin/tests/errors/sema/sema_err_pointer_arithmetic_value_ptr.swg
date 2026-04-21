#global fileprivate

#test
{
    var p: *s32 = null
    let a = p + 1 // swc-expected-error {{sema_err_pointer_arithmetic_value_ptr}}
}

#test
{
    var p: *s32 = null
    var b: [*]s32 = null
    let a = p - b // swc-expected-error {{sema_err_pointer_arithmetic_value_ptr}}
}
