#global private

#test
{
    var pv: s32
    var p:  *s32 = &pv
    let a        = p + 1     // swc-expected-error {{sema_err_pointer_arithmetic_value_ptr}}
}

#test
{
    var pv: s32
    var p:  *s32 = &pv
    let a        = 1 + p     // swc-expected-error {{sema_err_pointer_arithmetic_value_ptr}}
}

#test
{
    var pv: s32
    var p:  *s32 = &pv
    let a        = p - 1     // swc-expected-error {{sema_err_pointer_arithmetic_value_ptr}}
}

#test
{
    var pv: s32
    var p:  *s32 = &pv
    var q:  *s32 = &pv
    let a        = p - q     // swc-expected-error {{sema_err_pointer_arithmetic_value_ptr}}
}

#test
{
    var pv: s32
    var p:  *s32 = &pv
    p += 1     // swc-expected-error {{sema_err_pointer_arithmetic_value_ptr}}
}

#test
{
    var pv: s32
    var p:  *s32 = &pv
    p -= 1     // swc-expected-error {{sema_err_pointer_arithmetic_value_ptr}}
}

#test
{
    var pv: s32
    var p:  *s32 = &pv
    let a        = p[0]     // swc-expected-error {{sema_err_pointer_arithmetic_value_ptr}}
}

#test
{
    let values = [11'u64, 17, 23, 31]
    let pointer: const *[4] u64 = &values
    let value  = pointer[0]     // swc-expected-error {{sema_err_pointer_arithmetic_value_ptr}}
}
